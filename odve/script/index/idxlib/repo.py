"""The repository side of the index: where the root is, which files and
filelists exist, the units (filelist + top + env) to elaborate, the tools
that are available, file hashing (doc/index-plan.md 3.1-3.3).

Standard library only. The coverage flow's filelist reader
(script/cov/covlib/filelist.py) is reused for the `.f` syntax."""
import glob
import hashlib
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ODVE = os.path.abspath(os.path.join(HERE, "..", "..", ".."))        # .../odve (the framework root)
sys.path.insert(0, os.path.join(ODVE, "script", "cov"))
from covlib import filelist as covfl                                # noqa: E402

SV_EXT = {".sv": "sv", ".svh": "sv", ".v": "v", ".vh": "v", ".f": "f", ".vlt": "other"}
DEFAULT_EXCLUDES = ["/docs/", "/work/", "/obj_dir/", "/.odve-index/", "/build/", "/__run/", "/.git/",
                    "/svunit/svunit-3.38.1/test/", "/svunit/svunit-3.38.1/examples/"]
UNIT_GLOB = "comp/agents/*/vrf/list/fl.f"
DEFAULT_LIBRARY_PATHS = ["/uvm/uvm-1.1d/", "/uvm/1800.2-2020-2.0/", "/svunit/"]


# ------------------------------------------------------------------ root
def find_root(start=None):
    """ODVE_INDEX_ROOT, else the nearest ancestor with .odve-index/, else
    the nearest with .git (a working tree, not a submodule's .git file
    unless nothing better), else the start directory."""
    env = os.environ.get("ODVE_INDEX_ROOT")
    if env:
        return os.path.abspath(env)
    d = os.path.abspath(start or os.getcwd())
    first_git = None
    while True:
        if os.path.isdir(os.path.join(d, ".odve-index")):
            return d
        if os.path.exists(os.path.join(d, ".git")) and first_git is None:
            first_git = d
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return first_git or os.path.abspath(start or os.getcwd())


def rel(root, path):
    p = os.path.relpath(os.path.abspath(path), root)
    return p.replace(os.sep, "/")


def absp(root, relpath):
    return os.path.join(root, relpath)


def load_config(root):
    """<root>/.odve-index/config.json: excludes (substrings of '/'-paths),
    units (extra: name, filelist, top, sourceme), ctags, python."""
    cfg = {"excludes": list(DEFAULT_EXCLUDES), "units": []}
    p = os.path.join(root, ".odve-index", "config.json")
    if os.path.isfile(p):
        with open(p, encoding="utf-8") as f:
            user = json.load(f)
        cfg["excludes"] += user.get("excludes", [])
        cfg["units"] += user.get("units", [])
        for k in ("ctags", "python", "library_paths"):
            if k in user:
                cfg[k] = user[k]
    return cfg


def excluded(relpath, excludes):
    p = "/" + relpath
    return any(x in p for x in excludes)


# ------------------------------------------------------------------ tools
def find_ctags(root, cfg=None):
    """A Universal Ctags binary: config, ODVE_CTAGS, .odve-index/tools, PATH."""
    cands = []
    if cfg and cfg.get("ctags"):
        cands.append(cfg["ctags"])
    if os.environ.get("ODVE_CTAGS"):
        cands.append(os.environ["ODVE_CTAGS"])
    cands += [os.path.join(root, ".odve-index", "tools", "bin", "ctags"),
              os.path.join(root, ".odve-index", "tools", "ctags-env", "bin", "ctags")]
    for d in os.environ.get("PATH", "").split(os.pathsep):
        cands.append(os.path.join(d, "ctags"))
    for c in cands:
        if os.path.isfile(c) and os.access(c, os.X_OK):
            try:
                out = subprocess.run([c, "--version"], capture_output=True, text=True, timeout=10).stdout
            except (OSError, subprocess.SubprocessError):
                continue
            if "Universal Ctags" in out:
                return c
    return None


def venv_python(root):
    p = os.path.join(root, ".odve-index", "venv", "bin", "python")
    return p if os.path.isfile(p) else None


def have_pyslang():
    try:
        import pyslang  # noqa: F401
        return True
    except ImportError:
        return False


def tool_status(root, cfg=None):
    st = {"ctags": find_ctags(root, cfg), "venv_python": venv_python(root), "pyslang": have_pyslang()}
    if st["pyslang"]:
        import pyslang
        st["pyslang_version"] = pyslang.__version__
    return st


# ------------------------------------------------------------------ files
def git_files(root):
    """Tracked *.sv/*.svh/*.v/*.vh/*.f of the root and its submodules."""
    try:
        out = subprocess.run(["git", "-C", root, "ls-files", "--recurse-submodules", "-z"],
                             capture_output=True, text=True, timeout=120).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    return [p for p in out.split("\0") if p and os.path.splitext(p)[1] in SV_EXT]


def walk_files(root, excludes):
    out = []
    for dp, dn, fn in os.walk(root):
        rd = rel(root, dp) if dp != root else ""
        dn[:] = [d for d in dn if not excluded((rd + "/" if rd else "") + d + "/", excludes) and d != ".git"]
        for f in fn:
            if os.path.splitext(f)[1] in SV_EXT:
                out.append((rd + "/" if rd else "") + f)
    return out


def is_library(path, cfg=None):
    """A vendored library file (UVM, svunit): its internal references are
    not stored, only what the project code references in it."""
    pats = (cfg or {}).get("library_paths") or DEFAULT_LIBRARY_PATHS
    p = "/" + path
    return any(x in p for x in pats)


def sha1_of(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def stat_of(path):
    st = os.stat(path)
    return st.st_mtime, st.st_size


def file_changed(root, row):
    """True when the file on disk differs from a `files` row (mtime/size
    first, hash only when they moved)."""
    p = absp(root, row["path"])
    try:
        mtime, size = stat_of(p)
    except OSError:
        return True
    if abs(mtime - (row["mtime"] or 0)) < 1e-6 and size == row["size"]:
        return False
    return sha1_of(p) != row["sha1"]


# ------------------------------------------------------------------ units
def sourceme_env(sourceme):
    """Run the agent's sourceme in a subshell and return the ODVE*/PROJ
    variables it exports (what the filelists need for ${ODVE_...})."""
    d, f = os.path.split(sourceme)
    cmd = f'cd "$1" && source ./{f} >/dev/null 2>&1; env -0'
    try:
        out = subprocess.run(["bash", "-c", cmd, "_", d], capture_output=True, text=True, timeout=60).stdout
    except (OSError, subprocess.SubprocessError):
        return {}
    env = {}
    for kv in out.split("\0"):
        if "=" in kv:
            k, v = kv.split("=", 1)
            if k.startswith("ODVE") or k == "PROJ":
                env[k] = v
    return env


def _top_of(agent_dir):
    for mk in (os.path.join(agent_dir, "vrf", "work", "common", "Makefile"),):
        try:
            with open(mk, encoding="utf-8", errors="replace") as f:
                for line in f:
                    m = re.match(r"\s*(?:override\s+)?TOP\s*[:?]?=\s*(\S+)", line)
                    if m:
                        return m.group(1)
        except OSError:
            pass
    return "top"


def discover_units(root, cfg):
    """One unit per comp/agents/<proto>/vrf/list/fl.f (the flat list every
    scaffolded agent has), anywhere under the root (a consumer's own agents
    and the odve submodule's), plus config units. Returns dicts: name,
    filelist, top, agent, sourceme (all repo-relative)."""
    units = []
    seen = set()
    pats = [UNIT_GLOB, "*/" + UNIT_GLOB, "*/*/" + UNIT_GLOB, "*/*/*/" + UNIT_GLOB]
    for pat in pats:
        for fl in sorted(glob.glob(os.path.join(root, pat))):
            r = rel(root, fl)
            if r in seen or excluded(r, cfg["excludes"]):
                continue
            seen.add(r)
            agent = r[: -len("/vrf/list/fl.f")]
            proto = os.path.basename(agent)
            prefix = agent[: -len("comp/agents/" + proto)].strip("/")   # '' | 'odve/odve' (submodule) | other
            name = proto if not prefix else ("odve:" if prefix.split("/")[0] == "odve" else prefix.replace("/", ":") + ":") + proto
            sm = None
            for cand in ("vrf/work/run/sourceme", "vrf/work/mini/sourceme", "vrf/work/common/sourceme"):
                if os.path.isfile(os.path.join(root, agent, cand)):
                    sm = agent + "/" + cand
                    break
            units.append({"name": name, "filelist": r, "top": _top_of(os.path.join(root, agent)),
                          "agent": agent, "sourceme": sm})
    for u in cfg.get("units", []):
        if u.get("filelist") and u["filelist"] not in seen:
            units.append({"name": u.get("name") or os.path.basename(os.path.dirname(u["filelist"])),
                          "filelist": u["filelist"], "top": u.get("top", "top"),
                          "agent": u.get("agent", ""), "sourceme": u.get("sourceme")})
    return units


def resolve_filelist(root, fl_rel, env):
    """The ordered entries of a filelist with the given env: list of
    (kind, value) with values repo-relative when inside the root."""
    path = absp(root, fl_rel)
    fl = covfl.read_filelist(path, env=env)
    entries = []
    for f in fl.files:
        entries.append(("file", _norm(root, f, os.path.dirname(path))))
    for d in fl.incdirs:
        entries.append(("incdir", _norm(root, d, os.path.dirname(path))))
    for d in fl.defines:
        entries.append(("define", d))
    files = [v for k, v in entries if k == "file"]
    incs = [absp(root, v) if not os.path.isabs(v) else v for k, v in entries if k == "incdir"]
    all_files = covfl.expand_includes([absp(root, f) if not os.path.isabs(f) else f for f in files], incs)
    included = [_norm(root, f, root) for f in all_files if _norm(root, f, root) not in files]
    return entries, included


def _norm(root, p, base):
    if not os.path.isabs(p):
        p = os.path.join(base, p)
    p = os.path.abspath(p)
    if p.startswith(root + os.sep):
        return rel(root, p)
    return p


def nested_filelists(root, fl_rel, env):
    """The -f/-F files a filelist pulls in (repo-relative), recursively."""
    out = []
    todo = [fl_rel]
    seen = set()
    while todo:
        cur = todo.pop()
        if cur in seen:
            continue
        seen.add(cur)
        try:
            with open(absp(root, cur) if not os.path.isabs(cur) else cur, encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError:
            continue
        base = os.path.dirname(absp(root, cur) if not os.path.isabs(cur) else cur)
        toks = []
        for raw in text.splitlines():
            line = re.sub(r"//.*$", "", raw).strip()
            if line and not line.startswith("#"):
                toks.extend(line.split())
        for i, t in enumerate(toks):
            if t in ("-f", "-F") and i + 1 < len(toks):
                sub = covfl.expand(toks[i + 1], env)
                sub = _norm(root, sub, base if t == "-F" else os.getcwd())
                out.append(sub)
                todo.append(sub)
    return out


def now():
    return time.time()
