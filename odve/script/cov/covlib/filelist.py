"""Reader for the `-f` filelists the build already uses (vrf/list/fl_*.f):
one entry per line, `-f`/`-F` nesting, `+incdir+dir[+dir]`, `+define+X[=Y]`,
`${VAR}` / `$VAR` expansion, `//` comments. Other options (`-L x`, `-sv`,
`-v lib`, `-y dir`, ...) are skipped; only plain paths are sources. Relative
paths after `-f` are resolved against the current directory, after `-F`
against the filelist's own directory - as vlog and verilator do."""
import os
import re


class Filelist:
    def __init__(self):
        self.files = []      # source files, in order, without duplicates
        self.incdirs = []
        self.defines = []
        self._seen = set()

    def _add(self, lst, item):
        key = (len(lst) and id(lst), item)   # per-list dedup
        if (id(lst), item) in self._seen:
            return
        self._seen.add((id(lst), item))
        lst.append(item)


# options that take one argument which is not a source file
_SKIP_WITH_ARG = {"-L", "-v", "-y", "-work", "-l", "-top", "--top-module",
                  "-timescale", "--timescale", "-o"}


def read_filelist(path, env=None, into=None, _depth=0):
    """Parse `path` (and what it nests) into a Filelist."""
    env = os.environ if env is None else env
    fl = Filelist() if into is None else into
    if _depth > 20:
        raise RecursionError(f"filelist nesting too deep at {path}")
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError as e:
        raise FileNotFoundError(f"filelist {path}: {e}") from e
    base = os.path.dirname(os.path.abspath(path))

    toks = []
    for raw in text.splitlines():
        line = re.sub(r"//.*$", "", raw).strip()
        if line and not line.startswith("#"):
            toks.extend(line.split())

    i = 0
    while i < len(toks):
        tok = expand(toks[i], env)
        i += 1
        if tok in ("-f", "-F"):
            if i >= len(toks):
                break
            sub = expand(toks[i], env)
            i += 1
            if tok == "-F" and not os.path.isabs(sub):
                sub = os.path.join(base, sub)
            read_filelist(sub, env, fl, _depth + 1)
        elif tok in _SKIP_WITH_ARG:
            i += 1
        elif tok.startswith("+incdir+"):
            for d in tok[len("+incdir+"):].split("+"):
                if d:
                    fl._add(fl.incdirs, d)
        elif tok.startswith("+define+"):
            for d in tok[len("+define+"):].split("+"):
                if d:
                    fl._add(fl.defines, d)
        elif tok.startswith("-") or tok.startswith("+"):
            continue
        else:
            fl._add(fl.files, tok)
    return fl


def expand(tok, env):
    """${VAR} and $VAR from the given environment (unknown names stay as is)."""
    def rep(m):
        name = m.group(1) or m.group(2)
        return env.get(name, m.group(0))
    return re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)", rep, tok)


_INCLUDE_RE = re.compile(r'^[ \t]*`include[ \t]+"([^"]+)"', re.M)


def expand_includes(files, incdirs):
    """The files the compiler actually reads: `files` plus everything they
    `include, recursively, each resolved the way the tools do it - against
    the including file's directory first, then the +incdir+ list. Unresolved
    includes are skipped (the compiler will complain about them, not us)."""
    out, seen = [], set()

    def visit(path):
        real = os.path.abspath(path)
        if real in seen:
            return
        seen.add(real)
        out.append(path)
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError:
            return
        here = os.path.dirname(real)
        for name in _INCLUDE_RE.findall(text):
            for d in [here] + list(incdirs):
                cand = os.path.join(d, name)
                if os.path.isfile(cand):
                    visit(cand)
                    break

    for f in files:
        visit(f)
    return out
