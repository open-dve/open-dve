"""The query side: every MCP tool and CLI query is a function here that takes
the open database and plain arguments and returns a JSON-able dict
(doc/index-plan.md 3.5). Every answer carries `stale` - the files of the
answer whose content changed since they were indexed - so the caller knows
when to run index_update."""
import os

from . import repo
from .db import rows

LIMIT = 200


def _stale(con, root, files):
    out = []
    for f in sorted(set(x for x in files if x)):
        r = con.execute("SELECT path, sha1, mtime, size FROM files WHERE path = ?", (f,)).fetchone()
        if r is None:
            if os.path.isfile(repo.absp(root, f)):
                out.append(f)       # on disk, never indexed
            continue
        if repo.file_changed(root, r):
            out.append(f)
    return out


def _finish(con, root, res, files):
    res["stale"] = _stale(con, root, files)
    dirty = rows(con.execute("SELECT name FROM units WHERE status = 'dirty'"))
    if dirty:
        res["dirty_units"] = [d["name"] for d in dirty]
        res["hint"] = "index_update to refresh dirty units"
    return res


# ------------------------------------------------------------------ status
def index_status(con, root):
    units = rows(con.execute("SELECT name, filelist, top, status, parse_s, elab_s, visit_s, node_count, n_errors, n_warnings, built_at, message FROM units ORDER BY name"))
    counts = {t: con.execute(f"SELECT count(*) FROM {t}").fetchone()[0] for t in ("files", "tags", "symbols", "refs", "instances", "classes", "creates", "diags")}
    stale_n = 0
    for r in con.execute("SELECT path, sha1, mtime, size FROM files"):
        if repo.file_changed(root, r):
            stale_n += 1
    tools = repo.tool_status(root)
    last = rows(con.execute("SELECT at, what, detail FROM log ORDER BY at DESC LIMIT 5"))
    return {"root": root, "units": units, "counts": counts, "stale_files": stale_n, "tools": tools, "log": last}


# ------------------------------------------------------------------ filelists
def fl_list(con, root):
    out = rows(con.execute("SELECT path, kind, agent, resolved_at FROM filelists ORDER BY path"))
    for o in out:
        o["files"] = con.execute("SELECT count(*) FROM fl_entries WHERE filelist = ? AND kind = 'file'", (o["path"],)).fetchone()[0]
        o["nested"] = [r["value"] for r in con.execute("SELECT value FROM fl_entries WHERE filelist = ? AND kind = 'nested_f'", (o["path"],))]
        o["units"] = [r["name"] for r in con.execute("SELECT name FROM units WHERE filelist = ?", (o["path"],))]
    return {"filelists": out}


def fl_resolve(con, root, filelist, with_defines=True):
    fl = _match_one(con, "filelists", "path", filelist)
    if fl is None:
        return {"error": f"no filelist matching {filelist!r}", "fallback": "fl_list, then the exact path"}
    ents = rows(con.execute("SELECT ordinal, kind, value FROM fl_entries WHERE filelist = ? ORDER BY ordinal", (fl,)))
    res = {"filelist": fl, "files": [e["value"] for e in ents if e["kind"] == "file"],
           "incdirs": [e["value"] for e in ents if e["kind"] == "incdir"],
           "nested": [e["value"] for e in ents if e["kind"] == "nested_f"],
           "included": [e["value"] for e in ents if e["kind"] == "included"]}
    if with_defines:
        res["defines"] = [e["value"] for e in ents if e["kind"] == "define"]
    return _finish(con, root, res, res["files"])


def fl_of_file(con, root, path):
    p = _norm_path(root, path)
    hits = rows(con.execute("SELECT filelist, ordinal, kind FROM fl_entries WHERE value = ? OR value LIKE ? ORDER BY filelist", (p, "%/" + os.path.basename(p))))
    hits = [h for h in hits if h["kind"] in ("file", "included")]
    units = rows(con.execute("SELECT name, filelist, status FROM units"))
    for h in hits:
        h["units"] = [u["name"] for u in units if u["filelist"] == h["filelist"]]
        # nested: a unit whose list -f's this one
        nested = rows(con.execute("SELECT filelist FROM fl_entries WHERE kind = 'nested_f' AND value = ?", (h["filelist"],)))
        for n in nested:
            h["units"] += [u["name"] for u in units if u["filelist"] == n["filelist"]]
    return _finish(con, root, {"path": p, "filelists": hits, "listed": bool(hits)}, [p])


# ------------------------------------------------------------------ symbols
def sym_find(con, root, name, kind=None, prefix=False, unit=None, limit=50):
    q = "SELECT id, unit, name, kind, file, line, end_line, qualified, parent, decl, via_macro FROM symbols WHERE "
    args = []
    if prefix:
        q += "name LIKE ?"
        args.append(name + "%")
    else:
        q += "name = ?"
        args.append(name)
    if kind:
        q += " AND kind = ?"
        args.append(kind)
    if unit:
        q += " AND unit = ?"
        args.append(unit)
    q += " ORDER BY file, line LIMIT ?"
    args.append(min(limit, LIMIT))
    sem = rows(con.execute(q, args))
    for s in sem:
        s["semantic"] = True
    seen = {(s["file"], s["line"]) for s in sem}
    tq = "SELECT t.name, t.kind, t.file, t.line, t.end_line, t.scope, t.scope_kind, t.signature, t.inherits, f.listed FROM tags t LEFT JOIN files f ON f.path = t.file WHERE " + ("t.name LIKE ?" if prefix else "t.name = ?")
    targs = [name + "%" if prefix else name]
    if kind:
        tq += " AND t.kind = ?"
        targs.append(_tag_kind(kind))
    tq += " ORDER BY f.listed DESC, t.file, t.line LIMIT ?"
    targs.append(min(limit, LIMIT))
    tg = [t for t in rows(con.execute(tq, targs)) if (t["file"], t["line"]) not in seen]
    for t in tg:
        t["semantic"] = False
    res = {"name": name, "matches": sem + tg}
    if not res["matches"]:
        res["error"] = f"no definition of {name!r} in the index"
        res["fallback"] = "sym_find with prefix=true, or grep the name in the filelist's files (fl_resolve)"
    return _finish(con, root, res, [m["file"] for m in res["matches"]])


def sym_def(con, root, name, scope=None):
    r = sym_find(con, root, name, limit=20)
    ms = r.get("matches", [])
    if scope:
        ms2 = [m for m in ms if scope in (m.get("qualified") or "") or scope == (m.get("scope") or "")]
        ms = ms2 or ms
    res = {"name": name, "definition": ms[0] if ms else None, "candidates": ms[1:] if len(ms) > 1 else []}
    if not ms:
        res["error"] = r.get("error")
        res["fallback"] = r.get("fallback")
    return _finish(con, root, res, [m["file"] for m in ms[:1]])


def sym_refs(con, root, name=None, symbol_id=None, kind=None, file=None, limit=200, include_decl=True):
    if symbol_id is None:
        if not name:
            return {"error": "name or symbol_id required"}
        syms = rows(con.execute("SELECT id, name, kind, file, line, qualified FROM symbols WHERE name = ? ORDER BY file, line LIMIT 50", (name,)))
        if file:
            syms = [s for s in syms if s["file"] == _norm_path(root, file)] or syms
    else:
        syms = rows(con.execute("SELECT id, name, kind, file, line, qualified FROM symbols WHERE id = ?", (symbol_id,)))
    if not syms:
        tg = rows(con.execute("SELECT name, kind, file, line FROM tags WHERE name = ? LIMIT 10", (name,)))
        return _finish(con, root, {"name": name, "error": "no semantic symbol; references need an elaborated unit",
                                   "tags": tg, "fallback": "grep the name over fl_resolve(files) of the unit"}, [])
    out = []
    files = set()
    for s in syms:
        q = "SELECT unit, file, line, col, kind, via_macro FROM refs WHERE symbol_id = ?"
        args = [s["id"]]
        if kind:
            q += " AND kind = ?"
            args.append(kind)
        q += " ORDER BY file, line LIMIT ?"
        args.append(min(limit, 2000))
        refs = rows(con.execute(q, args))
        by_file = {}
        for r in refs:
            by_file.setdefault(r["file"], []).append({"line": r["line"], "kind": r["kind"], **({"via_macro": r["via_macro"]} if r["via_macro"] else {})})
            files.add(r["file"])
        out.append({"symbol": s, "n_refs": len(refs), "refs": by_file})
    return _finish(con, root, {"name": name, "symbols": out}, list(files))


def sym_outline(con, root, path, depth=2):
    p = _norm_path(root, path)
    sem = rows(con.execute("SELECT name, kind, line, end_line, qualified, parent, decl, via_macro FROM symbols WHERE file = ? ORDER BY line, col", (p,)))
    if sem:
        # drop the noise: arguments and variables inside methods are shown only when depth > 2
        n_macro = len([s for s in sem if s["via_macro"]])
        if depth <= 2:
            sem = [s for s in sem if s["kind"] not in ("argument",) and not s["via_macro"] and not (s["kind"] == "variable" and _inside_method(s, sem))]
        res = {"path": p, "semantic": True, "symbols": sem, "macro_generated_hidden": n_macro if depth <= 2 else 0}
    else:
        tg = rows(con.execute("SELECT name, kind, line, end_line, scope, scope_kind, signature, inherits FROM tags WHERE file = ? ORDER BY line", (p,)))
        res = {"path": p, "semantic": False, "symbols": tg}
        if not tg:
            res["error"] = "file not indexed"
            res["fallback"] = "index_update(paths=[path]) then retry; or code_at"
    return _finish(con, root, res, [p])


def _inside_method(s, all_syms):
    for m in all_syms:
        if m["kind"] in ("function", "task") and m["end_line"] and m["line"] < s["line"] <= m["end_line"]:
            return True
    return False


def sym_members(con, root, name):
    owners = rows(con.execute("SELECT id, name, kind, file, line, end_line, qualified FROM symbols WHERE name = ? AND kind IN ('class','package','module','interface','program','covergroup','typedef') ORDER BY file, line LIMIT 10", (name,)))
    if not owners:
        # modules come from instances' definitions
        inst = rows(con.execute("SELECT definition, def_kind, def_file, def_line FROM instances WHERE definition = ? LIMIT 1", (name,)))
        if inst:
            owners = [{"name": name, "kind": inst[0]["def_kind"], "file": inst[0]["def_file"], "line": inst[0]["def_line"], "end_line": None, "qualified": name}]
    if not owners:
        return _finish(con, root, {"name": name, "error": "no class/package/module of that name", "fallback": "sym_find(prefix=true)"}, [])
    out = []
    for o in owners:
        q = o["qualified"] or o["name"]
        mem = rows(con.execute("SELECT name, kind, file, line, decl, via_macro FROM symbols WHERE parent = ? OR parent = ? ORDER BY line LIMIT 500", (q, o["name"])))
        if not mem and o.get("end_line"):
            mem = rows(con.execute("SELECT name, kind, file, line, decl, via_macro FROM symbols WHERE file = ? AND line > ? AND line <= ? AND kind != 'argument' ORDER BY line LIMIT 500", (o["file"], o["line"], o["end_line"])))
        if not mem and o["kind"] in ("module", "interface", "program"):
            mem = rows(con.execute("SELECT s.name, s.kind, s.file, s.line, s.decl, s.via_macro FROM symbols s WHERE s.file = ? AND s.kind IN ('port','parameter','variable','net','modport','function','task','typedef') ORDER BY s.line LIMIT 500", (o["file"],)))
        n_macro = len([m for m in mem if m["via_macro"]])
        mem = [m for m in mem if not m["via_macro"] and not (m["kind"] == "variable" and _inside_method(m, mem))]
        out.append({"owner": o, "members": mem, "macro_generated_hidden": n_macro})
    return _finish(con, root, {"name": name, "owners": out}, [o["file"] for o in owners])


# ------------------------------------------------------------------ hierarchy
def hier_tree(con, root, unit=None, root_path=None, depth=3):
    u = _unit(con, unit)
    if u is None:
        return {"error": "no such unit", "units": [r["name"] for r in con.execute("SELECT name FROM units")]}
    allrows = rows(con.execute("SELECT path, parent, inst_name, definition, def_kind, def_file, def_line, file, line, params FROM instances WHERE unit = ? ORDER BY path", (u,)))
    if not allrows:
        return _finish(con, root, {"unit": u, "error": "no instances: unit not elaborated (status %s)" % _unit_status(con, u), "fallback": "index_update or index_rebuild"}, [])
    kids = {}
    for r in allrows:
        kids.setdefault(r["parent"], []).append(r)
    start = root_path or None
    tops = [r for r in allrows if r["parent"] is None] if start is None else [r for r in allrows if r["path"] == start]
    if not tops:
        return {"unit": u, "error": f"no instance {start!r}", "fallback": "hier_tree without root"}

    def node(r, d):
        n = {"path": r["path"], "def": r["definition"], "kind": r["def_kind"], "def_at": f"{r['def_file']}:{r['def_line']}"}
        if r["params"]:
            n["params"] = r["params"]
        ch = kids.get(r["path"], [])
        if ch and d > 0:
            n["children"] = [node(c, d - 1) for c in ch]
        elif ch:
            n["children_count"] = len(ch)
        return n
    return _finish(con, root, {"unit": u, "tree": [node(t, depth) for t in tops], "total_instances": len(allrows)}, [])


def hier_instance(con, root, path, unit=None):
    q = "SELECT * FROM instances WHERE path = ?"
    args = [path]
    if unit:
        q += " AND unit = ?"
        args.append(_unit(con, unit))
    r = rows(con.execute(q, args))
    if not r:
        like = rows(con.execute("SELECT unit, path FROM instances WHERE path LIKE ? LIMIT 20", ("%" + path.split(".")[-1] + "%",)))
        return {"error": f"no instance {path!r}", "similar": like, "fallback": "hier_tree"}
    out = []
    for i in r:
        i["children"] = rows(con.execute("SELECT path, inst_name, definition FROM instances WHERE unit = ? AND parent = ? ORDER BY path", (i["unit"], i["path"])))
        out.append(i)
    return _finish(con, root, {"instances": out}, [i["def_file"] for i in out])


def hier_of_module(con, root, definition):
    r = rows(con.execute("SELECT unit, path, parent, def_file, def_line, params FROM instances WHERE definition = ? ORDER BY unit, path LIMIT 500", (definition,)))
    if not r:
        return {"definition": definition, "error": "not instantiated in any unit", "fallback": "sym_find(definition)"}
    return _finish(con, root, {"definition": definition, "instances": r}, [x["def_file"] for x in r[:1]])


# ------------------------------------------------------------------ testbench
def tb_tree(con, root, unit=None, root_class=None, depth=6):
    u = _unit(con, unit)
    if u is None:
        return {"error": "no such unit", "units": [r["name"] for r in con.execute("SELECT name FROM units")]}
    cr = rows(con.execute("SELECT in_class, in_method, created, inst_name, file, line FROM creates WHERE unit = ? AND in_class IS NOT NULL", (u,)))
    if not cr:
        return _finish(con, root, {"unit": u, "error": "no type_id::create() calls recorded (unit not elaborated, or no UVM)", "fallback": "class_info / sym_refs"}, [])
    by_class = {}
    for c in cr:
        by_class.setdefault(c["in_class"], []).append(c)
    comp_classes = {r["name"] for r in con.execute("SELECT name FROM classes WHERE unit = ?", (u,))}
    if root_class is None:
        # tests: classes whose base chain reaches uvm_test
        tests = _derived_of(con, u, "uvm_test")
        roots = sorted(tests) or sorted(by_class)
    else:
        roots = [root_class]
    seen = set()

    def node(cls, d):
        n = {"class": cls, "base": _base_of(con, u, cls)}
        ch = []
        for c in by_class.get(cls, []):
            item = {"creates": c["created"], "name": c["inst_name"], "in": c["in_method"], "at": f"{c['file']}:{c['line']}"}
            if d > 0 and c["created"] in comp_classes and c["created"] not in seen and c["created"] != cls:
                seen.add(c["created"])
                item["tree"] = node(c["created"], d - 1)
            ch.append(item)
        if ch:
            n["children"] = ch
        return n
    return _finish(con, root, {"unit": u, "roots": [node(r, depth) for r in roots]}, [])


def class_info(con, root, name):
    cl = rows(con.execute("SELECT unit, name, package, base, file, line, end_line FROM classes WHERE name = ? ORDER BY unit LIMIT 10", (name,)))
    if not cl:
        tg = rows(con.execute("SELECT file, line, inherits FROM tags WHERE name = ? AND kind = 'class' LIMIT 5", (name,)))
        return _finish(con, root, {"name": name, "error": "class not in an elaborated unit", "tags": tg, "fallback": "sym_find / code_at"}, [])
    c = cl[0]
    u = c["unit"]
    chain, cur = [], c["base"]
    while cur and len(chain) < 20:
        chain.append(cur)
        cur = _base_of(con, u, cur)
    derived = rows(con.execute("SELECT name, file, line FROM classes WHERE unit = ? AND base = ? ORDER BY name", (u, name)))
    creates_in = rows(con.execute("SELECT in_method, created, inst_name, line FROM creates WHERE unit = ? AND in_class = ?", (u, name)))
    created_by = rows(con.execute("SELECT in_class, in_method, inst_name, file, line FROM creates WHERE unit = ? AND created = ?", (u, name)))
    members = sym_members(con, root, name).get("owners", [])
    mem = members[0]["members"] if members else []
    return _finish(con, root, {"class": c, "base_chain": chain, "derived": derived, "creates": creates_in, "created_by": created_by,
                               "methods": [m for m in mem if m["kind"] in ("function", "task")],
                               "properties": [m for m in mem if m["kind"] in ("property", "variable", "parameter", "typedef", "enum")]},
                   [c["file"]])


# ------------------------------------------------------------------ files
def file_deps(con, root, path):
    p = _norm_path(root, path)
    inc = rows(con.execute("SELECT included, line FROM includes WHERE file = ? ORDER BY line", (p,)))
    by = rows(con.execute("SELECT file, line FROM includes WHERE included = ? ORDER BY file", (p,)))
    imports = rows(con.execute("SELECT DISTINCT s.name AS package FROM refs r JOIN symbols s ON s.id = r.symbol_id WHERE r.file = ? AND s.kind = 'package'", (p,)))
    uses = rows(con.execute("SELECT s.name, s.kind, s.file, count(*) AS n FROM refs r JOIN symbols s ON s.id = r.symbol_id WHERE r.file = ? AND s.file != ? AND s.kind IN ('class','module','interface','package','typedef','function','task') GROUP BY s.name, s.kind, s.file ORDER BY n DESC LIMIT 60", (p, p)))
    fls = fl_of_file(con, root, p).get("filelists", [])
    return _finish(con, root, {"path": p, "includes": inc, "included_by": by, "packages": [i["package"] for i in imports], "uses": uses, "filelists": fls}, [p])


def diag(con, root, unit=None, file=None, severity=None, limit=100):
    q = "SELECT unit, severity, code, file, line, message FROM diags WHERE 1=1"
    args = []
    if unit:
        q += " AND unit = ?"
        args.append(_unit(con, unit))
    if file:
        q += " AND file = ?"
        args.append(_norm_path(root, file))
    if severity:
        q += " AND severity = ?"
        args.append(severity)
    q += " ORDER BY CASE severity WHEN 'error' THEN 0 WHEN 'fatal' THEN 0 ELSE 1 END, file, line LIMIT ?"
    args.append(min(limit, 1000))
    d = rows(con.execute(q, args))
    units = rows(con.execute("SELECT name, status, n_errors, n_warnings FROM units"))
    return {"diags": d, "units": units, "note": "advisory: slang is stricter than the simulators; the vrf-workflow gate decides"}


def code_at(con, root, path, line, context=8, end_line=None):
    p = _norm_path(root, path)
    ap = repo.absp(root, p) if not os.path.isabs(p) else p
    try:
        with open(ap, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError as e:
        return {"error": f"cannot read {p}: {e}"}
    lo = max(1, int(line) - int(context))
    hi = min(len(lines), (int(end_line) if end_line else int(line)) + int(context))
    text = "\n".join(f"{i:5d}  {lines[i - 1]}" for i in range(lo, hi + 1))
    return _finish(con, root, {"path": p, "from": lo, "to": hi, "total_lines": len(lines), "text": text}, [p])


# ------------------------------------------------------------------ helpers
def _norm_path(root, path):
    if os.path.isabs(path):
        return repo.rel(root, path) if os.path.abspath(path).startswith(root + os.sep) else path.replace(os.sep, "/")
    p = path.replace(os.sep, "/")
    if os.path.isfile(os.path.join(root, p)):
        return p
    cand = os.path.abspath(os.path.join(os.getcwd(), p))
    if os.path.isfile(cand) and cand.startswith(root + os.sep):
        return repo.rel(root, cand)
    return p


def _match_one(con, table, col, value):
    r = con.execute(f"SELECT {col} FROM {table} WHERE {col} = ?", (value,)).fetchone()
    if r:
        return r[0]
    r = con.execute(f"SELECT {col} FROM {table} WHERE {col} LIKE ? ORDER BY length({col}) LIMIT 1", ("%" + value,)).fetchone()
    return r[0] if r else None


def _unit(con, unit):
    if unit is None:
        r = con.execute("SELECT name FROM units ORDER BY (status = 'ok') DESC, name LIMIT 1").fetchone()
        return r[0] if r else None
    r = con.execute("SELECT name FROM units WHERE name = ? OR name LIKE ? ORDER BY length(name) LIMIT 1", (unit, "%:" + unit)).fetchone()
    return r[0] if r else None


def _unit_status(con, u):
    r = con.execute("SELECT status FROM units WHERE name = ?", (u,)).fetchone()
    return r[0] if r else None


def _base_of(con, unit, cls):
    r = con.execute("SELECT base FROM classes WHERE unit = ? AND name = ? LIMIT 1", (unit, cls)).fetchone()
    return r[0] if r else None


def _derived_of(con, unit, base):
    out, todo = set(), [base]
    while todo:
        b = todo.pop()
        for r in con.execute("SELECT name FROM classes WHERE unit = ? AND base = ?", (unit, b)):
            if r[0] not in out:
                out.add(r[0])
                todo.append(r[0])
    return out


_TAG_KINDS = {"class": "class", "module": "module", "interface": "interface", "package": "package", "function": "function",
              "task": "task", "typedef": "typedef", "port": "port", "variable": "register", "property": "register",
              "parameter": "constant", "covergroup": "covergroup", "modport": "modport", "instance": "instance", "define": "define"}


def _tag_kind(kind):
    return _TAG_KINDS.get(kind, kind)
