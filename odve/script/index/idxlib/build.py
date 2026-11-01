"""Building and updating the index (doc/index-plan.md 3.2-3.3, 3.6):
units from the filelists, the file set, tags, includes, and the per-unit
elaboration - in full (`build`), for a few changed paths (`update`), or
for whatever is dirty (`elab_dirty`, what the background job runs)."""
import json
import os
import re
import subprocess
import sys
import time

from . import repo, tags as tagmod
from .db import connect, log, rows

HERE = os.path.dirname(os.path.abspath(__file__))
CLI = os.path.join(os.path.dirname(HERE), "odve_index.py")
SYNC_BUDGET_S = 6.0      # an update elaborates in the caller when the unit's last build was faster than this


def _say(msg):
    print(msg, file=sys.stderr, flush=True)


# ------------------------------------------------------------------ units & files
def refresh_units(con, root, cfg):
    """Discover units, resolve their filelists with the agents' sourceme env,
    store filelists/fl_entries, mark listed files. Returns the unit dicts."""
    units = repo.discover_units(root, cfg)
    env_cache = {}
    for u in units:
        env = {}
        if u["sourceme"]:
            if u["sourceme"] not in env_cache:
                env_cache[u["sourceme"]] = repo.sourceme_env(repo.absp(root, u["sourceme"]))
            env = env_cache[u["sourceme"]]
        u["env"] = env
        _store_filelist(con, root, u["filelist"], "fl", u["agent"], env)
        for nested in repo.nested_filelists(root, u["filelist"], env):
            if con.execute("SELECT 1 FROM filelists WHERE path = ?", (nested,)).fetchone() is None:
                _store_filelist(con, root, nested, "nested", u["agent"], env)
        row = con.execute("SELECT status FROM units WHERE name = ?", (u["name"],)).fetchone()
        if row is None:
            con.execute("INSERT INTO units (name, filelist, top, agent, sourceme, status) VALUES (?,?,?,?,?,'dirty')",
                        (u["name"], u["filelist"], u["top"], u["agent"], u["sourceme"]))
        else:
            con.execute("UPDATE units SET filelist=?, top=?, agent=?, sourceme=? WHERE name=?",
                        (u["filelist"], u["top"], u["agent"], u["sourceme"], u["name"]))
    # agent-level lists (list/agent.f etc.) that no unit nests: still resolve them for fl_of_file
    for fl in sorted(set(repo.rel(root, p) for p in _glob_lists(root)) - {r["path"] for r in con.execute("SELECT path FROM filelists")}):
        if repo.excluded(fl, cfg["excludes"]):
            continue
        env = next((u["env"] for u in units if fl.startswith(u["agent"] + "/")), {})
        try:
            _store_filelist(con, root, fl, "other", _agent_of(fl), env)
        except Exception as e:      # a list that needs an env we do not have
            _say(f"filelist {fl}: {e}")
    con.commit()
    return units


def _glob_lists(root):
    import glob
    out = []
    for pat in ("comp/agents/*/list/*.f", "*/comp/agents/*/list/*.f", "*/*/comp/agents/*/list/*.f",
                "comp/agents/*/vrf/list/*.f", "*/comp/agents/*/vrf/list/*.f", "*/*/comp/agents/*/vrf/list/*.f"):
        out += glob.glob(os.path.join(root, pat))
    return out


def _agent_of(fl):
    m = re.search(r"(.*comp/agents/[^/]+)/", fl)
    return m.group(1) if m else ""


def _store_filelist(con, root, fl_rel, kind, agent, env):
    entries, included = repo.resolve_filelist(root, fl_rel, env)
    nested = repo.nested_filelists(root, fl_rel, env)
    con.execute("DELETE FROM fl_entries WHERE filelist = ?", (fl_rel,))
    rows_ = []
    i = 0
    for k, v in entries:
        rows_.append((fl_rel, i, k, v))
        i += 1
    for v in nested:
        rows_.append((fl_rel, i, "nested_f", v))
        i += 1
    for v in included:
        rows_.append((fl_rel, i, "included", v))
        i += 1
    con.executemany("INSERT INTO fl_entries VALUES (?,?,?,?)", rows_)
    con.execute("INSERT OR REPLACE INTO filelists VALUES (?,?,?,?,?)", (fl_rel, kind, agent, json.dumps(env), time.time()))
    con.execute("INSERT OR IGNORE INTO files (path, lang) VALUES (?, 'f')", (fl_rel,))
    for v in nested:
        con.execute("INSERT OR IGNORE INTO files (path, lang) VALUES (?, 'f')", (v,))


def refresh_files(con, root, cfg, only=None):
    """Upsert the file rows: every listed file plus git-tracked HDL files.
    Returns the repo-relative paths whose content changed (or are new)."""
    listed = {r["value"] for r in con.execute("SELECT value FROM fl_entries WHERE kind IN ('file','included')")}
    tracked = repo.git_files(root)
    if not tracked:                    # not a git repository: walk it
        tracked = repo.walk_files(root, cfg["excludes"])
    paths = set(listed) | set(tracked)
    paths = {p for p in paths if not os.path.isabs(p) and not repo.excluded(p, cfg["excludes"])}
    if only is not None:
        paths = {p for p in paths if p in only} | {p for p in only if os.path.isfile(repo.absp(root, p))}
    changed = []
    for p in sorted(paths):
        ap = repo.absp(root, p)
        if not os.path.isfile(ap):
            con.execute("DELETE FROM files WHERE path = ?", (p,))
            con.execute("DELETE FROM tags WHERE file = ?", (p,))
            continue
        row = con.execute("SELECT path, sha1, mtime, size, tagged_at FROM files WHERE path = ?", (p,)).fetchone()
        if row is not None and row["sha1"] and not repo.file_changed(root, row):
            con.execute("UPDATE files SET listed = ? WHERE path = ?", (int(p in listed), p))
            if row["tagged_at"] is None:
                changed.append(p)
            continue
        mtime, size = repo.stat_of(ap)
        lang = repo.SV_EXT.get(os.path.splitext(p)[1], "other")
        con.execute("INSERT OR REPLACE INTO files (path, sha1, mtime, size, lang, listed, tagged_at, elab_at) VALUES (?,?,?,?,?,?,NULL,NULL)",
                    (p, repo.sha1_of(ap), mtime, size, lang, int(p in listed)))
        changed.append(p)
    con.commit()
    return changed


def retag(con, root, cfg, paths):
    sv = [p for p in paths if repo.SV_EXT.get(os.path.splitext(p)[1]) in ("sv", "v")]
    if not sv:
        return 0
    ctags = repo.find_ctags(root, cfg)
    if not ctags:
        _say("ctags: not found (setup.sh --check) - tag layer skipped")
        return 0
    t = tagmod.run_ctags(ctags, root, sv)
    tagmod.store_tags(con, root, sv, t)
    con.commit()
    return len(t)


_INC_RE = re.compile(r'^[ \t]*`include[ \t]+"([^"]+)"', re.M)


def refresh_includes(con, root, paths):
    """`include edges of the given files, resolved against the including
    file's directory and the incdirs of every filelist that lists it."""
    incdirs_of = {}
    for r in con.execute("SELECT filelist, value FROM fl_entries WHERE kind = 'incdir'"):
        incdirs_of.setdefault(r["filelist"], []).append(r["value"])
    for p in paths:
        if repo.SV_EXT.get(os.path.splitext(p)[1]) not in ("sv", "v"):
            continue
        ap = repo.absp(root, p)
        try:
            with open(ap, encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError:
            continue
        con.execute("DELETE FROM includes WHERE file = ?", (p,))
        lists = [r["filelist"] for r in con.execute("SELECT filelist FROM fl_entries WHERE value = ? AND kind IN ('file','included')", (p,))]
        dirs = [os.path.dirname(ap)]
        for fl in lists:
            dirs += [repo.absp(root, d) if not os.path.isabs(d) else d for d in incdirs_of.get(fl, [])]
        for i, line in enumerate(text.splitlines(), 1):
            m = _INC_RE.match(line)
            if not m:
                continue
            target = m.group(1)
            for d in dirs:
                cand = os.path.join(d, target)
                if os.path.isfile(cand):
                    target = repo.rel(root, cand) if os.path.abspath(cand).startswith(root + os.sep) else cand
                    break
            con.execute("INSERT INTO includes VALUES (?,?,?,NULL)", (p, target, i))
    con.commit()


# ------------------------------------------------------------------ elaboration
def elaborate_unit(con, root, unit_name):
    from . import semantic
    u = con.execute("SELECT * FROM units WHERE name = ?", (unit_name,)).fetchone()
    if u is None:
        return {"error": f"no unit {unit_name}"}
    if not repo.have_pyslang():
        con.execute("UPDATE units SET status='no_pyslang', message=? WHERE name=?", ("pyslang not importable: run script/index/setup.sh", unit_name))
        con.commit()
        return {"unit": unit_name, "status": "no_pyslang"}
    env = {}
    r = con.execute("SELECT env FROM filelists WHERE path = ?", (u["filelist"],)).fetchone()
    if r and r["env"]:
        env = json.loads(r["env"])
    ud = {"name": u["name"], "filelist": u["filelist"], "top": u["top"]}
    t0 = time.time()
    try:
        ex = semantic.Extractor(root, ud, env, repo.load_config(root))
        ex.run()
    except Exception as e:
        con.execute("UPDATE units SET status='failed', message=?, built_at=? WHERE name=?", (str(e)[:500], time.time(), unit_name))
        log(con, "elab_failed", {"unit": unit_name, "error": str(e)[:500]})
        con.commit()
        return {"unit": unit_name, "status": "failed", "error": str(e)[:500]}
    con.execute("BEGIN")
    counts = semantic.store(con, ex)
    st = "ok" if ex.stats.get("n_errors", 0) == 0 else "errors"
    con.execute("UPDATE units SET status=?, parse_s=?, elab_s=?, visit_s=?, node_count=?, n_errors=?, n_warnings=?, built_at=?, message=NULL WHERE name=?",
                (st, ex.stats.get("parse_s"), ex.stats.get("elab_s"), ex.stats.get("visit_s"), ex.stats.get("node_count"),
                 ex.stats.get("n_errors"), ex.stats.get("n_warnings"), time.time(), unit_name))
    files = {r_["file"] for r_ in ex.sym_rows} | {i["file"] for i in ex.instances if i["file"]}
    con.executemany("UPDATE files SET elab_at = ? WHERE path = ?", [(time.time(), f) for f in files])
    con.commit()
    res = {"unit": unit_name, "status": st, "seconds": round(time.time() - t0, 2), **counts, **{k: round(v, 3) if isinstance(v, float) else v for k, v in ex.stats.items()}}
    log(con, "elab", res)
    con.commit()
    return res


def units_of_paths(con, paths):
    """Units whose filelist (or a nested one) lists any of the paths; a
    changed .f dirties its own units."""
    names = set()
    for p in paths:
        for r in con.execute("SELECT filelist FROM fl_entries WHERE value = ? AND kind IN ('file','included')", (p,)):
            names |= _units_of_filelist(con, r["filelist"])
        if p.endswith(".f"):
            names |= _units_of_filelist(con, p)
    return names


def _units_of_filelist(con, fl):
    names = {r["name"] for r in con.execute("SELECT name FROM units WHERE filelist = ?", (fl,))}
    for r in con.execute("SELECT filelist FROM fl_entries WHERE kind = 'nested_f' AND value = ?", (fl,)):
        names |= _units_of_filelist(con, r["filelist"])
    return names


# ------------------------------------------------------------------ entry points
def build(root, units=None, elab=True, do_tags=True):
    cfg = repo.load_config(root)
    con = connect(root)
    t0 = time.time()
    found = refresh_units(con, root, cfg)
    changed = refresh_files(con, root, cfg)
    n_tags = retag(con, root, cfg, changed) if do_tags else 0
    refresh_includes(con, root, [r["path"] for r in con.execute("SELECT path FROM files WHERE listed = 1")])
    res = {"root": root, "units": [u["name"] for u in found], "files_changed": len(changed), "tags": n_tags, "elab": []}
    if elab:
        for u in found:
            if units and u["name"] not in units and u["name"].split(":")[-1] not in units:
                continue
            r = elaborate_unit(con, root, u["name"])
            res["elab"].append(r)
            _say(f"elab {u['name']}: {r.get('status')} {r.get('seconds', '')}s symbols={r.get('symbols', '')} refs={r.get('refs', '')} instances={r.get('instances', '')}")
    res["seconds"] = round(time.time() - t0, 2)
    log(con, "build", {"units": res["units"], "files_changed": len(changed), "seconds": res["seconds"]})
    con.commit()
    con.close()
    return res


def update(root, paths, elab="auto", note=None):
    """Re-index the given files now (hash, tags, includes), dirty their
    units and elaborate them: elab = auto (in-process when the units are
    quick, else in the background), sync, background or none."""
    cfg = repo.load_config(root)
    con = connect(root)
    rels = []
    for p in paths:
        ap = os.path.abspath(p)
        if os.path.isdir(ap):
            for dp, dn, fn in os.walk(ap):
                dn[:] = [d for d in dn if not repo.excluded(repo.rel(root, os.path.join(dp, d)) + "/", cfg["excludes"])]
                for f in fn:
                    if os.path.splitext(f)[1] in repo.SV_EXT:
                        rels.append(repo.rel(root, os.path.join(dp, f)))
        else:
            rels.append(repo.rel(root, ap))
    rels = sorted(set(rels))
    fl_changed = [p for p in rels if p.endswith(".f")]
    if fl_changed:
        refresh_units(con, root, cfg)
    changed = refresh_files(con, root, cfg, only=set(rels))
    n_tags = retag(con, root, cfg, rels)
    refresh_includes(con, root, rels)
    dirty = units_of_paths(con, rels)
    for u in dirty:
        con.execute("UPDATE units SET status = 'dirty' WHERE name = ? AND status != 'no_pyslang'", (u,))
    log(con, "update", {"paths": rels, "units": sorted(dirty), "note": note})
    con.commit()
    res = {"paths": rels, "changed": changed, "tags": n_tags, "dirty_units": sorted(dirty), "elab": []}
    if not dirty or elab == "none":
        con.close()
        return res
    quick = all((con.execute("SELECT parse_s + elab_s + visit_s FROM units WHERE name = ?", (u,)).fetchone()[0] or 0) < SYNC_BUDGET_S for u in dirty)
    if elab == "sync" or (elab == "auto" and quick and repo.have_pyslang()):
        for u in sorted(dirty):
            res["elab"].append(elaborate_unit(con, root, u))
        res["elab_mode"] = "sync"
    else:
        con.close()
        res["elab_mode"] = "background"
        res["background"] = spawn_background(root)
        return res
    con.close()
    return res


def elab_dirty(root):
    """Elaborate every dirty unit (and keep going while an update marks more)."""
    con = connect(root)
    out = []
    for _ in range(20):
        dirty = [r["name"] for r in con.execute("SELECT name FROM units WHERE status = 'dirty'")]
        if not dirty:
            break
        for u in dirty:
            out.append(elaborate_unit(con, root, u))
    con.close()
    return out


LOCK = ".odve-index/elab.lock"


def spawn_background(root):
    """Start `odve_index.py elab --dirty` detached, once: a running job
    (live pid in the lock) will pick up the new dirty units itself."""
    lock = os.path.join(root, LOCK)
    try:
        with open(lock) as f:
            pid = int(f.read().strip() or 0)
        if pid and _alive(pid):
            return {"running": pid}
    except (OSError, ValueError):
        pass
    py = repo.venv_python(root) or sys.executable
    logf = open(os.path.join(root, ".odve-index", "elab.log"), "a")
    p = subprocess.Popen([py, CLI, "--root", root, "elab", "--dirty", "--locked"], stdout=logf, stderr=subprocess.STDOUT,
                         start_new_session=True, close_fds=True)
    with open(lock, "w") as f:
        f.write(str(p.pid))
    return {"started": p.pid, "log": os.path.join(root, ".odve-index", "elab.log")}


def _alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False
