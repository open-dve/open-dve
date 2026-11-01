"""Layer 1: Universal Ctags over the file set (doc/index-plan.md 3.2).
`ctags --output-format=json` per file list; a per-file re-tag costs
milliseconds, so `update` just re-runs it for the changed files."""
import json
import os
import subprocess
import tempfile

from . import repo

CTAGS_ARGS = ["--languages=SystemVerilog,Verilog", "--langmap=SystemVerilog:+.svh", "--langmap=Verilog:+.vh",
              "--extras=+q", "--fields=+nKSzZe", "--output-format=json", "--sort=no"]


def run_ctags(ctags, root, rel_files):
    """Tag the given repo-relative files; returns the parsed tag dicts."""
    if not rel_files:
        return []
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".lst") as f:
        for p in rel_files:
            f.write(p + "\n")
        lst = f.name
    try:
        r = subprocess.run([ctags] + CTAGS_ARGS + ["-L", lst, "-o", "-"], cwd=root, capture_output=True, text=True, timeout=600)
    finally:
        os.unlink(lst)
    out = []
    for line in r.stdout.splitlines():
        if not line.startswith("{"):
            continue
        try:
            j = json.loads(line)
        except ValueError:
            continue
        if j.get("_type") != "tag":
            continue
        out.append(j)
    return out


def store_tags(con, root, rel_files, tags):
    """Replace the tags of `rel_files` with `tags`."""
    con.executemany("DELETE FROM tags WHERE file = ?", [(p,) for p in rel_files])
    rows = []
    for t in tags:
        path = t.get("path", "").replace(os.sep, "/")
        rows.append((t.get("name"), t.get("kind"), path, t.get("line"), t.get("end"),
                     t.get("scope"), t.get("scopeKind"), t.get("signature"), t.get("typeref"), t.get("inherits")))
    con.executemany("INSERT INTO tags VALUES (?,?,?,?,?,?,?,?,?,?)", rows)
    t = repo.now()
    con.executemany("UPDATE files SET tagged_at = ? WHERE path = ?", [(t, p) for p in rel_files])
