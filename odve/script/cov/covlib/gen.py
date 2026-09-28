"""Generator: model -> the files the build compiles (doc/fcov-plan.md 3.4, 4.1).

  odve_cov_gen.svh          ODVE_COV_N / ODVE_COV_MODEL / ODVE_COV_HASH defines
  odve_cov_gen_classes.svh  one class odve_cov_<group> per covergroup, included
                            inside package odve_cov_pkg after odve_cov_group
  covmap.json               flat index -> names, kinds, at_least, sources; the
                            scripts' view of the same model

Bins are data: every point becomes parallel tables (lo/hi/kind/bidx rows,
plus transition sequences) scanned by the runtime's generic find_bin() /
find_trans(); every cross becomes a kinds table over the product of its
members' coverage bins. The generated code size does not depend on the
number of bins, only on the number of points and crosses.

A group the parser could not understand, or a name used by `odve_cov_create
without a covergroup, becomes a stub class whose sample() does nothing and
warns once - so the build never breaks because of the coverage model."""
import hashlib
import itertools
import json
import os

from .model import Group, Model

GEN_VERSION = "1"

# row kinds in the lo/hi/kind tables (must match odve_cov_pkg.sv)
K_BIN, K_IGNORE, K_ILLEGAL, K_BIN_WILD, K_IGNORE_WILD, K_ILLEGAL_WILD, K_DEFAULT = range(7)
_KIND_BASE = {"bin": K_BIN, "ignore": K_IGNORE, "illegal": K_ILLEGAL}
# cross bin kinds
X_BIN, X_IGNORE, X_ILLEGAL = 0, 1, 2

MASK64 = (1 << 64) - 1


# ----------------------------------------------------------------- layout

def model_hash(model, model_name):
    h = hashlib.sha256()
    h.update(f"odve-cov gen {GEN_VERSION} {model_name}\n".encode())
    for g in model.groups:
        h.update(f"{g.name}\n{g.text}\n{g.unsupported or ''}\n".encode())
    return h.hexdigest()[:12]


def effective_at_least(g, item):
    return item.at_least or g.at_least or 1


def eval_filter(expr, combo):
    """combo: {point name: bin name} for one cross bin."""
    op = expr[0]
    if op == "binsof":
        _, pn, bn = expr
        return combo[pn] == bn if bn is not None else True
    if op == "not":
        return not eval_filter(expr[1], combo)
    if op == "and":
        return eval_filter(expr[1], combo) and eval_filter(expr[2], combo)
    if op == "or":
        return eval_filter(expr[1], combo) or eval_filter(expr[2], combo)
    raise ValueError(expr)


def cross_bins(g, x):
    """[(name, kind)] over the product of the members' coverage bins, row-major
    in member order. Filters: an illegal filter wins over an ignore one."""
    members = [[b.name for b in g.point(pn).coverage_bins] for pn in x.points]
    out = []
    for combo in itertools.product(*members):
        d = dict(zip(x.points, combo))
        kind = X_BIN
        for f in x.filters:
            if eval_filter(f.expr, d):
                kind = X_ILLEGAL if f.kind == "illegal" else max(kind, X_IGNORE)
        out.append((",".join(combo), kind))
    return out


def layout(model):
    """Assign flat bases. Returns ({group: {"points": [base...], "crosses":
    [(base, [(name, kind)])]}}, total)."""
    lay, n = {}, 0
    for g in model.groups:
        if g.unsupported:
            continue
        entry = {"points": [], "crosses": []}
        for p in g.points:
            entry["points"].append(n)
            n += len(p.coverage_bins)
        for x in g.crosses:
            xb = cross_bins(g, x)
            entry["crosses"].append((n, xb))
            n += len(xb)
        lay[g.name] = entry
    return lay, max(n, 1)


# --------------------------------------------------------------- SV text

def sv_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def sv_long(v):
    """A longint literal. Masks above 2^63 are written as 64'h so they stay
    representable; everything else as a signed decimal."""
    if v < 0:
        return f"-{-v}"
    if v > (1 << 63) - 1:
        return f"64'h{v & MASK64:016X}"
    return str(v)


def sv_list(vals, fmt=str):
    return "'{ " + ", ".join(fmt(v) for v in vals) + " }"


def point_tables(p):
    """Rows for find_bin() (lo, hi, kind, bidx) and sequences for find_trans()
    (flattened values, lengths, bidx) of one point. Coverage bins are indexed
    in order; ignore/illegal rows carry bidx -1."""
    rows, trs = [], []
    bidx = 0
    for b in p.bins:
        idx = bidx if b.is_coverage else -1
        base = _KIND_BASE[b.kind]
        for lo, hi in b.ranges:
            rows.append((lo, hi, base, idx))
        for value, mask in b.wild:
            rows.append((value, mask, base + 3, idx))
        if b.default:
            rows.append((0, 0, K_DEFAULT, idx))
        for seq in b.trans:
            trs.append((seq, idx))
        if b.is_coverage:
            bidx += 1
    return rows, trs


def gen_class(g, lay):
    """The table-driven class of one supported group."""
    args = ", ".join(f"longint {a.name}" for a in g.args)
    spares = [f"a{i}" for i in range(len(g.args) + 1, 9)]
    spare_decl = "".join(f",\n                         longint {s} = NA" for s in spares)
    out = []
    w = out.append
    w(f"// ---- {g.name}  ({os.path.basename(g.file)}:{g.line})")
    w(f"class odve_cov_{g.name} extends odve_cov_group;")
    for i, p in enumerate(g.points):
        w(f"    localparam int P{i}_BASE = {lay['points'][i]};   // {p.name}: {len(p.coverage_bins)} bins")
    for i, (base, xb) in enumerate(lay["crosses"]):
        x = g.crosses[i]
        w(f"    localparam int X{i}_BASE = {base};   // {x.name} = {' x '.join(x.points)}: {len(xb)} bins")
    tables = []
    for i, p in enumerate(g.points):
        rows, trs = point_tables(p)
        tables.append((rows, trs))
        w(f"    longint p{i}_lo[], p{i}_hi[]; byte p{i}_kind[]; int p{i}_bidx[];")
        if trs:
            w(f"    longint p{i}_tr[], p{i}_hist[]; int p{i}_trlen[], p{i}_trbidx[];")
    for i in range(len(lay["crosses"])):
        w(f"    byte x{i}_kind[];")
    w("")
    w(f"    function new(string name = {sv_str(g.name)});")
    w("        super.new(name);")
    for i, (rows, trs) in enumerate(tables):
        w(f"        p{i}_lo   = {sv_list([r[0] for r in rows], sv_long)};")
        w(f"        p{i}_hi   = {sv_list([r[1] for r in rows], sv_long)};")
        w(f"        p{i}_kind = {sv_list([r[2] for r in rows])};")
        w(f"        p{i}_bidx = {sv_list([r[3] for r in rows])};")
        if trs:
            flat = [v for seq, _ in trs for v in seq]
            w(f"        p{i}_tr     = {sv_list(flat, sv_long)};")
            w(f"        p{i}_trlen  = {sv_list([len(seq) for seq, _ in trs])};")
            w(f"        p{i}_trbidx = {sv_list([idx for _, idx in trs])};")
            w(f"        p{i}_hist   = new[{max(len(seq) for seq, _ in trs)}];")
    for i, (base, xb) in enumerate(lay["crosses"]):
        w(f"        x{i}_kind = {sv_list([k for _, k in xb])};")
    w("    endfunction")
    w("")
    w(f"    function void sample({args}{spare_decl});")
    decls = ["int " + ", ".join(f"b{i}" for i in range(len(g.points)))]
    if any(trs for _, trs in tables):
        decls.append("int " + ", ".join(f"t{i}" for i, (_, trs) in enumerate(tables) if trs))
    if lay["crosses"]:
        decls.append("int xi")
    for d in decls:
        w(f"        {d};")
    for k, s in enumerate(spares):
        w(f"        check_spare({s}, {len(g.args) + 1 + k});")
    for i, p in enumerate(g.points):
        rows, trs = tables[i]
        w(f"        b{i} = BIN_NONE;")
        if trs:
            w(f"        t{i} = -1;")
        cond = ""
        if p.iff:
            cond = f"({'!' if p.iff[1] else ''}({p.iff[0]} != 0))"
            w(f"        if {cond} begin")
        ind = "            " if cond else "        "
        w(f"{ind}b{i} = find_bin({p.arg}, p{i}_lo, p{i}_hi, p{i}_kind, p{i}_bidx);")
        if trs:
            w(f"{ind}t{i} = find_trans({p.arg}, p{i}_hist, p{i}_tr, p{i}_trlen, p{i}_trbidx);")
        w(f"{ind}if (b{i} == BIN_ILLEGAL) illegal({sv_str(p.name)}, {p.arg});")
        w(f"{ind}if (b{i} >= 0) odve_cov_store::hit(P{i}_BASE + b{i});")
        if trs:
            w(f"{ind}if (t{i} >= 0) odve_cov_store::hit(P{i}_BASE + t{i});")
        if cond:
            w("        end")
    for i, (base, xb) in enumerate(lay["crosses"]):
        x = g.crosses[i]
        pidx = [g.points.index(g.point(pn)) for pn in x.points]
        sizes = [len(g.point(pn).coverage_bins) for pn in x.points]
        guard = " && ".join(f"b{j} >= 0" for j in pidx)
        expr = f"b{pidx[0]}"
        for j, sz in zip(pidx[1:], sizes[1:]):
            expr = f"({expr}) * {sz} + b{j}"
        w(f"        if ({guard}) begin")
        w(f"            xi = {expr};")
        w(f"            if (x{i}_kind[xi] == {X_BIN}) odve_cov_store::hit(X{i}_BASE + xi);")
        w(f"            else if (x{i}_kind[xi] == {X_ILLEGAL}) illegal({sv_str(x.name)}, xi);")
        w("        end")
    w("    endfunction")
    w("endclass")
    w("")
    return "\n".join(out)


def gen_stub(name, reason, where=""):
    out = [f"// ---- {name}: STUB - {reason}{('  (' + where + ')') if where else ''}",
           f"class odve_cov_{name} extends odve_cov_group;",
           "    bit warned = 0;",
           f"    function new(string name = {sv_str(name)});",
           "        super.new(name);",
           "    endfunction",
           "    function void sample(longint a1 = NA, longint a2 = NA, longint a3 = NA, longint a4 = NA,",
           "                         longint a5 = NA, longint a6 = NA, longint a7 = NA, longint a8 = NA);",
           "        if (!warned) begin",
           "            warned = 1;",
           f"            `ODVE_COV_WARN({sv_str(name + ': no coverage collected - ' + reason)})",
           "        end",
           "    endfunction",
           "endclass",
           ""]
    return "\n".join(out)


# -------------------------------------------------------------- covmap

def covmap(model, model_name, lay, n, warnings, hsh):
    groups = []
    for g in model.groups:
        entry = {"name": g.name, "file": g.file, "line": g.line, "text": g.text,
                 "weight": g.weight, "unsupported": g.unsupported, "points": [], "crosses": []}
        if not g.unsupported:
            for i, p in enumerate(g.points):
                entry["points"].append({
                    "name": p.name, "arg": p.arg, "base": lay[g.name]["points"][i],
                    "at_least": effective_at_least(g, p),
                    "iff": None if p.iff is None else {"arg": p.iff[0], "negated": p.iff[1]},
                    "bins": [b.name for b in p.coverage_bins],
                    "ignore": [b.name for b in p.bins if b.kind == "ignore"],
                    "illegal": [b.name for b in p.bins if b.kind == "illegal"]})
            for i, x in enumerate(g.crosses):
                base, xb = lay[g.name]["crosses"][i]
                entry["crosses"].append({
                    "name": x.name, "base": base, "points": x.points,
                    "at_least": effective_at_least(g, x),
                    "bins": [name for name, _ in xb], "kinds": [k for _, k in xb]})
        groups.append(entry)
    return {"format": "odve-covmap 2", "generator": GEN_VERSION, "model": model_name, "hash": hsh,
            "n": n, "groups": groups, "created": model.created, "sampled": model.sampled,
            "warnings": warnings}


# --------------------------------------------------------------- entry

def generate(model, out_dir, model_name):
    """Write the three files. Returns (summary dict, warnings list)."""
    warnings = []
    known = {g.name for g in model.groups}
    for name in dict.fromkeys(model.created + model.sampled):
        if name not in known:
            reason = "no covergroup of this name in any `ifdef ODVE_COV_NATIVE block"
            model.groups.append(Group(name=name, unsupported=reason))
            warnings.append(f"{name}: {reason} - stub generated")
    for g in model.groups:
        if g.unsupported and g.name != "?" and g.file:
            warnings.append(f"{g.name} ({g.file}:{g.line}): skipped - {g.unsupported}")
        elif g.unsupported:
            warnings.append(f"{g.file}:{g.line}: unreadable ODVE_COV_NATIVE block - {g.unsupported}")
        elif g.name not in model.created:
            warnings.append(f"{g.name} ({g.file}:{g.line}): covergroup found but never `odve_cov_create'd")
    model.groups = [g for g in model.groups if g.name != "?"]

    lay, n = layout(model)
    hsh = model_hash(model, model_name)
    os.makedirs(out_dir, exist_ok=True)

    with open(os.path.join(out_dir, "odve_cov_gen.svh"), "w") as f:
        f.write("// GENERATED by covgen.py scan - do not edit\n"
                "`ifndef ODVE_COV_GEN_SVH\n`define ODVE_COV_GEN_SVH\n"
                f"`define ODVE_COV_N     {n}\n"
                f"`define ODVE_COV_MODEL {sv_str(model_name)}\n"
                f"`define ODVE_COV_HASH  {sv_str(hsh)}\n"
                "`endif\n")

    with open(os.path.join(out_dir, "odve_cov_gen_classes.svh"), "w") as f:
        f.write("// GENERATED by covgen.py scan - do not edit. Included inside package odve_cov_pkg.\n\n")
        for g in model.groups:
            if g.unsupported:
                f.write(gen_stub(g.name, g.unsupported, f"{g.file}:{g.line}" if g.file else ""))
            else:
                f.write(gen_class(g, lay[g.name]))
            f.write("\n")

    cm = covmap(model, model_name, lay, n, warnings, hsh)
    with open(os.path.join(out_dir, "covmap.json"), "w") as f:
        json.dump(cm, f, indent=1)

    supported = [g.name for g in model.groups if not g.unsupported]
    return {"n": n, "hash": hsh, "groups": supported,
            "stubs": [g.name for g in model.groups if g.unsupported]}, warnings
