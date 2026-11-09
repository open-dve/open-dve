#!/usr/bin/env python3
"""odve_index.py - the code index of a Verilog/SystemVerilog repository
(doc/index-plan.md). Standard library + Universal Ctags for the tag layer;
pyslang (script/index/setup.sh) for the semantic layer.

  odve_index.py build [--no-elab] [--units U ...]   discover filelists/units, hash, tag, elaborate
  odve_index.py update <path>... [--elab auto|sync|background|none] [--note TEXT]
  odve_index.py elab [--dirty | UNIT ...]           (re-)elaborate units
  odve_index.py status | units
  odve_index.py query <tool> [key=value ...]        any MCP tool from the shell (JSON out)
  odve_index.py hook                                 PostToolUse hook body (reads the tool JSON on stdin)
  odve_index.py --root DIR ...                      another repository root (default: ODVE_INDEX_ROOT,
                                                     else the nearest .odve-index/ or .git above the cwd)

When pyslang is not importable but <root>/.odve-index/venv exists, the
command re-executes itself with that venv's Python."""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from idxlib import repo  # noqa: E402


def _reexec_in_venv(root):
    if os.environ.get("ODVE_INDEX_NO_REEXEC"):
        return
    if repo.have_pyslang():
        return
    py = repo.venv_python(root)
    if py and os.path.abspath(py) != os.path.abspath(sys.executable):   # the venv python is a symlink to the base one: no realpath
        os.environ["ODVE_INDEX_NO_REEXEC"] = "1"
        os.execv(py, [py] + sys.argv)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", help="repository root (default: ODVE_INDEX_ROOT or discovered)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--no-elab", action="store_true")
    b.add_argument("--no-tags", action="store_true")
    b.add_argument("--units", nargs="*")
    u = sub.add_parser("update")
    u.add_argument("paths", nargs="+")
    u.add_argument("--elab", default="auto", choices=["auto", "sync", "background", "none"])
    u.add_argument("--note")
    e = sub.add_parser("elab")
    e.add_argument("units", nargs="*")
    e.add_argument("--dirty", action="store_true")
    e.add_argument("--locked", action="store_true", help=argparse.SUPPRESS)
    sub.add_parser("status")
    sub.add_parser("units")
    q = sub.add_parser("query")
    q.add_argument("tool")
    q.add_argument("args", nargs="*", help="key=value (JSON values accepted)")
    sub.add_parser("hook")
    sub.add_parser("serve")
    a = ap.parse_args(argv)

    root = os.path.abspath(a.root) if a.root else repo.find_root()
    os.environ["ODVE_INDEX_ROOT"] = root
    if a.cmd in ("build", "update", "elab"):
        _reexec_in_venv(root)
    from idxlib import build, queries
    from idxlib.db import connect

    if a.cmd == "build":
        res = build.build(root, units=a.units, elab=not a.no_elab, do_tags=not a.no_tags)
        print(json.dumps(res, indent=1, default=str))
    elif a.cmd == "update":
        res = build.update(root, a.paths, elab=a.elab, note=a.note)
        print(json.dumps(res, indent=1, default=str))
    elif a.cmd == "elab":
        try:
            if a.dirty:
                res = build.elab_dirty(root)
            else:
                con = connect(root)
                res = [build.elaborate_unit(con, root, u) for u in a.units]
                con.close()
            print(json.dumps(res, indent=1, default=str))
        finally:
            if a.locked:
                try:
                    os.unlink(os.path.join(root, build.LOCK))
                except OSError:
                    pass
    elif a.cmd in ("status", "units"):
        con = connect(root)
        st = queries.index_status(con, root)
        con.close()
        if a.cmd == "units":
            for u in st["units"]:
                print(f"{u['name']:24} {u['status'] or '-':10} {u['filelist']}  top={u['top']}  errors={u['n_errors']} warnings={u['n_warnings']}")
        else:
            print(json.dumps(st, indent=1, default=str))
    elif a.cmd == "query":
        fn = getattr(queries, a.tool, None)
        if fn is None:
            sys.exit(f"no such tool: {a.tool}; tools: " + ", ".join(n for n in dir(queries) if not n.startswith("_") and callable(getattr(queries, n)) and n not in ("rows", "repo")))
        kw = {}
        for kv in a.args:
            k, _, v = kv.partition("=")
            try:
                kw[k] = json.loads(v)
            except ValueError:
                kw[k] = v
        con = connect(root)
        print(json.dumps(fn(con, root, **kw), indent=1, default=str))
        con.close()
    elif a.cmd == "hook":
        hook(root)
    elif a.cmd == "serve":
        import mcp_server
        mcp_server.srv.run()


def hook(root):
    """PostToolUse (Edit|Write|MultiEdit): the edited path from the hook's
    JSON on stdin -> update now, elaboration in the background. Exit 0
    always: the index never blocks an edit."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return
    ti = payload.get("tool_input") or {}
    path = ti.get("file_path") or ti.get("path") or ti.get("notebook_path")
    if not path or os.path.splitext(path)[1] not in repo.SV_EXT:
        return
    if not os.path.isfile(path):
        return
    try:
        from idxlib import build
        from idxlib.db import connect
        if connect(root, create=False) is None:
            return                      # no index here: nothing to keep current
        res = build.update(root, [path], elab="background")
        print(f"odve-index: {os.path.relpath(path, root)} re-tagged; units {res.get('dirty_units')} -> {res.get('elab_mode', 'nothing dirty')}", file=sys.stderr)
    except Exception as e:              # never fail the edit
        print(f"odve-index hook: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
