"""Covergroup subset parser (doc/fcov-plan.md 4.1).

Finds the `ifdef ODVE_COV_NATIVE blocks and the `odve_cov_create /
`odve_cov_sample macro uses in a SystemVerilog file, and turns every
covergroup in those blocks into a model.Group. Everything the subset does
not cover raises Unsupported, which the caller turns into a stub group and
a warning - never a failed build.

Supported:
  covergroup NAME with function sample(<typed args>);   (explicit sampling only)
    [label:] coverpoint ARG [iff ([!]ARG)] { bin items }   or  ;  (auto bins)
      [wildcard] bins|ignore_bins|illegal_bins NAME[[]] = { v, [lo:hi], [lo:$] ... };
      bins NAME[[]] = ( v => v [=> v ...] [, v => v ...] );        (transition)
      bins NAME = default;
      option.at_least = N;  option.weight = N;
    [label:] cross P1, P2 [, P3] { ignore_bins|illegal_bins NAME = <binsof expr>; option.at_least = N; }  or  ;
    option.at_least = N;  option.weight = N;
  endgroup [: NAME]
  argument types: int integer byte shortint longint bit logic reg [signed|unsigned] [ [N:M] ]
"""
import re

from .model import Arg, Bin, Cross, Filter, Group, Point

AUTO_BIN_MAX = 64
ARRAY_BIN_MAX = 4096


class Unsupported(Exception):
    def __init__(self, what, line=0):
        super().__init__(what)
        self.what = what
        self.line = line


# ------------------------------------------------------------- source scan

def strip_comments(text):
    """Blank out // and /* */ comments, keeping every newline so line numbers
    stay valid."""
    out = []
    i, n = 0, len(text)
    while i < n:
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", text[i:j]))
            i = j
        elif text[i] == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


_IFDEF_RE = re.compile(r"^\s*`(ifdef|ifndef|elsif|else|endif)\b\s*(\w+)?")


def find_native_blocks(text):
    """Yield (first_line_number, block_text) for every `ifdef ODVE_COV_NATIVE
    ... `endif region (the `else part, if any, is excluded). Lines outside
    the region are blanked in block_text so line numbers are preserved."""
    lines = text.split("\n")
    depth = 0
    capture_depth = None
    blocks = []
    cur = None
    for ln, line in enumerate(lines, 1):
        m = _IFDEF_RE.match(line)
        if m:
            kw, name = m.group(1), m.group(2)
            if kw in ("ifdef", "ifndef"):
                depth += 1
                if capture_depth is None and kw == "ifdef" and name == "ODVE_COV_NATIVE":
                    capture_depth = depth
                    cur = [ln + 1, []]
                    continue
            elif kw in ("else", "elsif"):
                if capture_depth == depth:
                    blocks.append((cur[0], "\n".join(cur[1])))
                    cur, capture_depth = None, None
                    continue
            elif kw == "endif":
                if capture_depth == depth:
                    blocks.append((cur[0], "\n".join(cur[1])))
                    cur, capture_depth = None, None
                    depth = max(0, depth - 1)
                    continue
                depth = max(0, depth - 1)   # a nested `endif stays part of the block
        if cur is not None:
            cur[1].append(line)
    return blocks


_CREATE_RE = re.compile(r"`odve_cov_create\s*\(\s*([A-Za-z_]\w*)\s*\)")
_SAMPLE_RE = re.compile(r"`odve_cov_sample\s*\(\s*([A-Za-z_]\w*)\s*,")


def find_macro_uses(text):
    """Group names named by the two macros, in order of appearance."""
    return _CREATE_RE.findall(text), _SAMPLE_RE.findall(text)


# --------------------------------------------------------------- tokenizer

_TOK_RE = re.compile(r"""
    (?P<ws>\s+)
  | (?P<num>\d*'[sS]?[hHdDoObB][0-9a-fA-F_xXzZ?]+|\d[\d_]*)
  | (?P<id>[A-Za-z_$][A-Za-z0-9_$]*)
  | (?P<str>"(?:[^"\\]|\\.)*")
  | (?P<op>=>|&&|\|\||==|!=|<=|>=|[{}\[\]():;,=.!\-+*/<>?@#%&|^~`])
""", re.X)


class Tok:
    __slots__ = ("kind", "text", "line", "pos")

    def __init__(self, kind, text, line, pos):
        self.kind, self.text, self.line, self.pos = kind, text, line, pos

    def __repr__(self):
        return f"{self.kind}:{self.text}@{self.line}"


def tokenize(text, base_line=1):
    toks = []
    line = base_line
    pos = 0
    while pos < len(text):
        m = _TOK_RE.match(text, pos)
        if not m:
            raise Unsupported(f"unexpected character {text[pos]!r}", line)
        kind = m.lastgroup
        s = m.group(0)
        if kind != "ws":
            toks.append(Tok(kind, s, line, pos))
        line += s.count("\n")
        pos = m.end()
    return toks


# ----------------------------------------------------------------- numbers

def parse_number(text, line=0):
    """SystemVerilog integer literal -> (value, care_mask). care_mask is None
    for an exact value; for `?`/x/z digits it clears the don't-care bits."""
    t = text.replace("_", "")
    if "'" not in t:
        return int(t), None
    size, rest = t.split("'", 1)
    rest = rest.lstrip("sS")
    base, digits = rest[0].lower(), rest[1:]
    bits = {"h": 4, "o": 3, "b": 1, "d": None}[base]
    if bits is None:
        if any(c in digits.lower() for c in "xz?"):
            raise Unsupported(f"wildcard digits in a decimal literal {text}", line)
        return int(digits), None
    value, mask, wild = 0, 0, False
    for ch in digits:
        value <<= bits
        mask <<= bits
        if ch.lower() in "xz?":
            wild = True
        else:
            value |= int(ch, 16)
            mask |= (1 << bits) - 1
    if not wild:
        return value, None
    width = int(size) if size else len(digits) * bits
    full = (1 << 64) - 1
    care = (full & ~((1 << width) - 1)) | mask   # bits above the literal must be 0
    return value & ((1 << width) - 1), care


_TYPES = {"int": (32, True), "integer": (32, True), "byte": (8, True), "shortint": (16, True),
          "longint": (64, True), "bit": (1, False), "logic": (1, False), "reg": (1, False)}


# ------------------------------------------------------------------ parser

class Parser:
    def __init__(self, toks, text, file=""):
        self.toks = toks
        self.text = text
        self.file = file
        self.i = 0

    # -- token helpers
    def peek(self, k=0):
        j = self.i + k
        return self.toks[j] if j < len(self.toks) else Tok("eof", "", self.toks[-1].line if self.toks else 0, len(self.text))

    def next(self):
        t = self.peek()
        self.i += 1
        return t

    def accept(self, text):
        if self.peek().text == text:
            return self.next()
        return None

    def expect(self, text):
        t = self.next()
        if t.text != text:
            raise Unsupported(f"expected '{text}', got '{t.text or 'end of block'}'", t.line)
        return t

    def ident(self, what="identifier"):
        t = self.next()
        if t.kind != "id" or t.text == "$":
            raise Unsupported(f"expected {what}, got '{t.text or 'end of block'}'", t.line)
        return t.text

    # -- top level: all covergroups in the token stream
    def parse_all(self):
        groups = []
        while self.peek().kind != "eof":
            t = self.next()
            if t.text == "covergroup":
                start = t
                g = Group(name="?", file=self.file, line=t.line)
                try:
                    self.i -= 1
                    self.parse_group(g)
                except Unsupported as e:
                    g.unsupported = f"{e.what} (line {e.line})"
                    self.skip_to_endgroup()
                end = self.toks[self.i - 1] if self.i > 0 else start
                g.text = self.text[start.pos:end.pos + len(end.text)]
                groups.append(g)
        return groups

    def skip_to_endgroup(self):
        while self.peek().kind != "eof":
            if self.next().text == "endgroup":
                if self.accept(":"):
                    self.next()
                return

    # -- covergroup
    def parse_group(self, g):
        self.expect("covergroup")
        g.name = self.ident("covergroup name")
        if not self.accept("with"):
            raise Unsupported("covergroup without `with function sample(...)` (clocking-event or implicit sampling)", self.peek().line)
        self.expect("function")
        self.expect("sample")
        self.expect("(")
        while not self.accept(")"):
            g.args.append(self.parse_arg())
            if not self.accept(","):
                self.expect(")")
                break
        if not g.args:
            raise Unsupported("sample() without arguments", self.peek().line)
        self.expect(";")
        while True:
            t = self.peek()
            if t.text == "endgroup":
                self.next()
                if self.accept(":"):
                    self.ident()
                break
            if t.kind == "eof":
                raise Unsupported("missing endgroup", t.line)
            if t.text in ("option", "type_option"):
                self.parse_option(g, t.text)
            elif t.text == "coverpoint":
                g.points.append(self.parse_point(g, None))
            elif t.text == "cross":
                raise Unsupported("cross without a label (it needs a name in the report)", t.line)
            elif t.kind == "id" and self.peek(1).text == ":":
                label = self.next().text
                self.next()
                if self.peek().text == "coverpoint":
                    g.points.append(self.parse_point(g, label))
                elif self.peek().text == "cross":
                    g.crosses.append(self.parse_cross(g, label))
                else:
                    raise Unsupported(f"'{self.peek().text}' after label {label}", t.line)
            else:
                raise Unsupported(f"'{t.text}' at covergroup level", t.line)
        self.validate(g)

    def parse_arg(self):
        t = self.next()
        if t.text not in _TYPES:
            raise Unsupported(f"sample argument type '{t.text}' (only the integral types are supported)", t.line)
        width, signed = _TYPES[t.text]
        if self.accept("signed"):
            signed = True
        elif self.accept("unsigned"):
            signed = False
        typ = t.text
        if self.accept("["):
            hi = self.parse_int()
            self.expect(":")
            lo = self.parse_int()
            self.expect("]")
            width = abs(hi - lo) + 1
            typ = f"{t.text} [{hi}:{lo}]"
        name = self.ident("argument name")
        return Arg(typ, name, width, signed)

    def parse_option(self, target, which):
        t = self.next()
        self.expect(".")
        opt = self.ident("option name")
        self.expect("=")
        val = self.parse_int()
        self.expect(";")
        if which == "type_option" and opt == "weight":
            target.weight = val
        elif which == "option" and opt == "at_least":
            target.at_least = val
        elif which == "option" and opt == "weight":
            target.weight = val
        else:
            raise Unsupported(f"{which}.{opt}", t.line)

    def parse_int(self):
        neg = bool(self.accept("-"))
        t = self.next()
        if t.kind != "num":
            raise Unsupported(f"expected a number, got '{t.text}'", t.line)
        v, mask = parse_number(t.text, t.line)
        if mask is not None:
            raise Unsupported(f"wildcard literal {t.text} outside a wildcard bin", t.line)
        return -v if neg else v

    # -- coverpoint
    def parse_point(self, g, label):
        t = self.expect("coverpoint")
        argname = self.ident("coverpoint argument")
        arg = next((a for a in g.args if a.name == argname), None)
        if arg is None:
            raise Unsupported(f"coverpoint '{argname}' is not a sample() argument (expressions are not supported)", t.line)
        if self.peek().text not in (";", "{", "iff"):
            raise Unsupported(f"coverpoint expression after '{argname}'", t.line)
        p = Point(name=label or argname, arg=argname, bins=[], line=t.line)
        if self.accept("iff"):
            self.expect("(")
            neg = bool(self.accept("!"))
            cond = self.ident("iff argument")
            if cond not in [a.name for a in g.args]:
                raise Unsupported(f"iff ({cond}) is not a sample() argument", t.line)
            self.expect(")")
            p.iff = (cond, neg)
        if self.accept("{"):
            while not self.accept("}"):
                if self.peek().text == "option":
                    self.parse_option(p, "option")
                else:
                    p.bins.extend(self.parse_bin(arg))
            self.accept(";")
        else:
            self.expect(";")
            p.bins = auto_bins(arg)
        if not p.coverage_bins:
            raise Unsupported(f"coverpoint {p.name} has no coverage bins", t.line)
        return p

    def parse_bin(self, arg):
        t = self.peek()
        wildcard = bool(self.accept("wildcard"))
        kw = self.next().text
        kinds = {"bins": "bin", "ignore_bins": "ignore", "illegal_bins": "illegal"}
        if kw not in kinds:
            raise Unsupported(f"'{kw}' inside a coverpoint", t.line)
        kind = kinds[kw]
        name = self.ident("bin name")
        array = False
        if self.accept("["):
            if not self.accept("]"):
                raise Unsupported(f"fixed-size bins {name}[N]", t.line)
            array = True
        self.expect("=")
        b = Bin(name=name, kind=kind)
        if self.accept("default"):
            if self.accept("sequence"):
                raise Unsupported("default sequence", t.line)
            if array or wildcard:
                raise Unsupported(f"bins {name}[] = default", t.line)
            b.default = True
        elif self.accept("{"):
            while not self.accept("}"):
                if wildcard:
                    tk = self.next()
                    if tk.kind != "num":
                        raise Unsupported(f"wildcard bins {name}: expected a literal", tk.line)
                    v, mask = parse_number(tk.text, tk.line)
                    b.wild.append((v, mask if mask is not None else (1 << 64) - 1))
                elif self.accept("["):
                    lo = self.parse_bound(arg, "lo")
                    self.expect(":")
                    hi = self.parse_bound(arg, "hi")
                    self.expect("]")
                    b.ranges.append((lo, hi))
                else:
                    v = self.parse_int()
                    b.ranges.append((v, v))
                if not self.accept(","):
                    self.expect("}")
                    break
        elif self.accept("("):
            while True:
                seq = [self.parse_int()]
                while self.accept("=>"):
                    seq.append(self.parse_int())
                if self.peek().text == "[":
                    raise Unsupported("repetition in a transition bin", self.peek().line)
                b.trans.append(seq)
                if not self.accept(","):
                    break
            self.expect(")")
        else:
            raise Unsupported(f"bin {name}: expected {{ ... }}, ( ... ) or default", t.line)
        if self.peek().text in ("with", "iff", "intersect"):
            raise Unsupported(f"'{self.peek().text}' on bin {name}", t.line)
        if kind != "bin" and (b.trans or b.default):
            raise Unsupported(f"{kw} {name}: only values, ranges and wildcards are supported for {kw}", t.line)
        self.expect(";")
        return expand_array(b) if array else [b]

    def parse_bound(self, arg, which):
        if self.accept("$"):
            return arg.max if which == "hi" else arg.min
        return self.parse_int()

    # -- cross
    def parse_cross(self, g, label):
        t = self.expect("cross")
        x = Cross(name=label, points=[self.ident("cross member")], line=t.line)
        while self.accept(","):
            x.points.append(self.ident("cross member"))
        if self.accept("{"):
            while not self.accept("}"):
                kt = self.peek()
                if kt.text == "option":
                    self.parse_option(x, "option")
                    continue
                kw = self.next().text
                if kw == "bins":
                    raise Unsupported("bins inside a cross (only ignore_bins/illegal_bins filters)", kt.line)
                if kw not in ("ignore_bins", "illegal_bins"):
                    raise Unsupported(f"'{kw}' inside a cross", kt.line)
                name = self.ident("cross bin name")
                self.expect("=")
                expr = self.parse_binsof_or()
                self.expect(";")
                x.filters.append(Filter(name, "ignore" if kw == "ignore_bins" else "illegal", expr))
            self.accept(";")
        else:
            self.expect(";")
        return x

    def parse_binsof_or(self):
        e = self.parse_binsof_and()
        while self.accept("||"):
            e = ("or", e, self.parse_binsof_and())
        return e

    def parse_binsof_and(self):
        e = self.parse_binsof_unary()
        while self.accept("&&"):
            e = ("and", e, self.parse_binsof_unary())
        return e

    def parse_binsof_unary(self):
        if self.accept("!"):
            return ("not", self.parse_binsof_unary())
        if self.accept("("):
            e = self.parse_binsof_or()
            self.expect(")")
            return e
        t = self.expect("binsof")
        self.expect("(")
        point = self.ident("point in binsof")
        bin_ = None
        if self.accept("."):
            bin_ = self.ident("bin in binsof")
            if self.accept("["):
                inner = []
                while self.peek().text != "]":
                    if self.peek().kind == "eof":
                        raise Unsupported("unterminated bin index in binsof", t.line)
                    inner.append(self.next().text)
                self.expect("]")
                bin_ += "[" + "".join(inner) + "]"
        self.expect(")")
        if self.peek().text == "intersect":
            raise Unsupported("binsof(...) intersect", t.line)
        return ("binsof", point, bin_)

    # -- checks that need the whole group
    def validate(self, g):
        names = set()
        for p in g.points:
            if p.name in names:
                raise Unsupported(f"duplicate name {p.name}", p.line)
            names.add(p.name)
            bnames = set()
            for b in p.bins:
                if b.name in bnames:
                    raise Unsupported(f"duplicate bin {p.name}.{b.name}", p.line)
                bnames.add(b.name)
        for x in g.crosses:
            if x.name in names:
                raise Unsupported(f"duplicate name {x.name}", x.line)
            names.add(x.name)
            for pn in x.points:
                if g.point(pn) is None:
                    raise Unsupported(f"cross {x.name}: '{pn}' is not a coverpoint of this covergroup", x.line)
            for f in x.filters:
                self.check_binsof(g, x, f.expr)

    def check_binsof(self, g, x, e):
        if e[0] == "binsof":
            _, pn, bn = e
            if pn not in x.points:
                raise Unsupported(f"cross {x.name}: binsof({pn}) is not a member", x.line)
            if bn is not None and bn not in [b.name for b in g.point(pn).coverage_bins]:
                raise Unsupported(f"cross {x.name}: binsof({pn}.{bn}) names no coverage bin", x.line)
        else:
            for sub in e[1:]:
                self.check_binsof(g, x, sub)


def expand_array(b):
    """bins b[] = {values} -> one bin per value, named b[value] (a transition
    array gets one bin per sequence)."""
    out = []
    if b.trans:
        for i, seq in enumerate(b.trans):
            out.append(Bin(name=f"{b.name}[{i}]", kind=b.kind, trans=[seq]))
        return out
    values = []
    for lo, hi in b.ranges:
        if hi - lo + 1 > ARRAY_BIN_MAX or len(values) + hi - lo + 1 > ARRAY_BIN_MAX:
            raise Unsupported(f"bins {b.name}[] would create more than {ARRAY_BIN_MAX} bins")
        values.extend(range(lo, hi + 1))
    for v in values:
        out.append(Bin(name=f"{b.name}[{v}]", kind=b.kind, ranges=[(v, v)]))
    return out


def auto_bins(arg):
    """LRM automatic bins for a coverpoint without a bin list: one bin per
    value when the type has at most AUTO_BIN_MAX values, else AUTO_BIN_MAX
    equal ranges."""
    span = 1 << arg.width
    if span <= AUTO_BIN_MAX:
        return [Bin(name=f"auto[{v}]", ranges=[(v, v)]) for v in range(arg.min, arg.max + 1)]
    size = span // AUTO_BIN_MAX
    bins = []
    lo = arg.min
    for _ in range(AUTO_BIN_MAX):
        hi = lo + size - 1
        bins.append(Bin(name=f"auto[{lo}:{hi}]", ranges=[(lo, hi)]))
        lo = hi + 1
    return bins


# ---------------------------------------------------------------- entry

def parse_file(path, text=None):
    """All covergroups of one source file (from its ODVE_COV_NATIVE blocks) plus
    the names its macros mention. Returns (groups, created, sampled)."""
    if text is None:
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
    clean = strip_comments(text)
    groups = []
    for first_line, block in find_native_blocks(clean):
        try:
            toks = tokenize(block, first_line)
        except Unsupported as e:
            groups.append(Group(name="?", file=path, line=e.line, unsupported=f"{e.what} (line {e.line})"))
            continue
        for g in Parser(toks, block, path).parse_all():
            groups.append(g)
    created, sampled = find_macro_uses(clean)
    return groups, created, sampled
