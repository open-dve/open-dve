#!/usr/bin/env python3
"""Build (and optionally upload) the portable tool bundle of the code index.

    script/index/release.py [--out DIR] [--cache DIR] [--version V]
                            [--upload [--repo OWNER/NAME] [--token-env GITHUB_TOKEN | --token-file F] [--replace]]
    script/index/release.py --check BUNDLE.tar.gz

The bundle holds everything setup.sh needs that is not in git, for a host
without network and without pip - but with a Python 3.12 (python itself is
not bundled; nanobind-backend, the pyslang dependency, ships cp312-only
wheels, so the bundle is per Python minor):

    odve-index-tools-<ver>/
      VERSION            key=value: version, python tag, platform, glibc floor
      MANIFEST.sha256    sha256 of every file (sha256sum -c compatible)
      README.txt         how to install
      wheels/            pyslang, nanobind-backend (requirements.lock) and pip (tools.lock PIP_VER)
      tools/             uctags-<ver>-linux-x86_64.release.tar.xz (tools.lock)

Wheels are resolved through the PyPI JSON API (no pip needed here either),
picked for cp312 / manylinux x86_64 and verified against PyPI's sha256;
ctags against the sha256 in tools.lock. Standard library only.

Upload (--upload) creates the GitHub release `index-tools-<ver>` in --repo
if it does not exist and attaches the tarball and its .sha256 sidecar; the
token comes from an environment variable (--token-env, default GITHUB_TOKEN)
or a file (--token-file) and is never printed. Install on the other side:

    odve/script/index/setup.sh --bundle odve-index-tools-<ver>-cp312-linux-x86_64.tar.gz
"""
import argparse
import datetime as _dt
import hashlib
import io
import json
import os
import re
import shutil
import sys
import tarfile
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PLATFORM = "linux-x86_64"
UA = "odve-index-release/1 (+https://github.com/open-dve/open-dve)"


# ---------------------------------------------------------------- locks
def read_lock(path=os.path.join(HERE, "tools.lock")):
    """tools.lock as a dict, ${KEY} references expanded in file order."""
    d = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            d[k.strip()] = re.sub(r"\$\{(\w+)\}", lambda m: d.get(m.group(1), os.environ.get(m.group(1), "")), v.strip())
    return d


def read_requirements(path=os.path.join(HERE, "requirements.lock")):
    reqs = []
    with open(path) as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if line:
                name, ver = line.split("==")
                reqs.append((name.strip(), ver.strip()))
    return reqs


# ---------------------------------------------------------------- http
def http(url, data=None, headers=None, method=None, timeout=120):
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("User-Agent", UA)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, r.read(), dict(r.headers)


def fetch(url, dest, sha256=None, cache=None):
    """Download url to dest (through cache when given), verify sha256."""
    name = os.path.basename(dest)
    src = os.path.join(cache, name) if cache else None
    if src and os.path.exists(src) and (not sha256 or sha256_of(src) == sha256):
        shutil.copyfile(src, dest)
        return "cache"
    print(f"release: fetching {name}")
    _, body, _ = http(url, timeout=600)
    if sha256 and hashlib.sha256(body).hexdigest() != sha256:
        raise SystemExit(f"release: sha256 mismatch for {name} ({url})")
    with open(dest, "wb") as f:
        f.write(body)
    if src:
        os.makedirs(cache, exist_ok=True)
        shutil.copyfile(dest, src)
    return "download"


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ---------------------------------------------------------------- wheels
WHEEL_RE = re.compile(r"^(?P<name>[^-]+)-(?P<ver>[^-]+)(-(?P<build>\d[^-]*))?-(?P<py>[^-]+)-(?P<abi>[^-]+)-(?P<plat>[^-]+)\.whl$")
MANYLINUX_RE = re.compile(r"^manylinux_(\d+)_(\d+)_x86_64$")
LEGACY_MANYLINUX = {"manylinux1_x86_64": (2, 5), "manylinux2010_x86_64": (2, 12), "manylinux2014_x86_64": (2, 17)}


def wheel_fit(filename, py_tag):
    """(glibc floor, filename) when the wheel runs on CPython `py_tag` on
    linux x86_64, else None. A pure wheel has floor (0, 0)."""
    m = WHEEL_RE.match(filename)
    if not m:
        return None
    minor = int(py_tag[3:])
    pys, abis, plats = (m.group("py").split("."), m.group("abi").split("."), m.group("plat").split("."))
    ok_py = False
    for p in pys:
        if p in ("py3", py_tag):
            ok_py = True
        elif p.startswith("cp3") and p[2:].isdigit() and int(p[3:]) <= minor and "abi3" in abis:
            ok_py = True
    if not ok_py or not ({"none", "abi3", py_tag} & set(abis)):
        return None
    floors = []
    for p in plats:
        if p == "any":
            floors.append((0, 0))
        elif p in LEGACY_MANYLINUX:
            floors.append(LEGACY_MANYLINUX[p])
        else:
            mm = MANYLINUX_RE.match(p)
            if mm:
                floors.append((int(mm.group(1)), int(mm.group(2))))
    if not floors:
        return None
    return min(floors)


def resolve_wheel(name, ver, py_tag):
    """The best PyPI wheel of name==ver for py_tag/linux-x86_64: (url, filename, sha256, glibc)."""
    url = f"https://pypi.org/pypi/{urllib.parse.quote(name)}/{urllib.parse.quote(ver)}/json"
    try:
        _, body, _ = http(url, headers={"Accept": "application/json"})
    except urllib.error.HTTPError as e:
        raise SystemExit(f"release: PyPI has no {name}=={ver} ({e.code})")
    cands = []
    for u in json.loads(body)["urls"]:
        if u.get("packagetype") != "bdist_wheel" or u.get("yanked"):
            continue
        fit = wheel_fit(u["filename"], py_tag)
        if fit is not None:
            cands.append((fit, u["filename"], u["url"], u["digests"]["sha256"]))
    if not cands:
        raise SystemExit(f"release: no {py_tag}/{PLATFORM} wheel of {name}=={ver} on PyPI")
    cands.sort()
    fit, fn, url, sha = cands[0]
    return url, fn, sha, fit


# ---------------------------------------------------------------- build
def build(out, cache, version, lock):
    py_tag = lock["PY_TAG"]
    name = f"odve-index-tools-{version}"
    stage = os.path.join(out, "stage", name)
    shutil.rmtree(os.path.join(out, "stage"), ignore_errors=True)
    os.makedirs(os.path.join(stage, "wheels"))
    os.makedirs(os.path.join(stage, "tools"))
    glibc = (0, 0)
    wheels = []
    for pkg, ver in read_requirements() + [("pip", lock["PIP_VER"])]:
        url, fn, sha, fit = resolve_wheel(pkg, ver, py_tag)
        how = fetch(url, os.path.join(stage, "wheels", fn), sha, cache)
        glibc = max(glibc, fit)
        wheels.append((pkg, ver, fn, how))
    ctags_fn = os.path.basename(lock["CTAGS_URL"])
    how = fetch(lock["CTAGS_URL"], os.path.join(stage, "tools", ctags_fn), lock["CTAGS_SHA"], cache)
    with open(os.path.join(stage, "VERSION"), "w") as f:
        f.write(f"version={version}\npython={py_tag}\nplatform={PLATFORM}\nglibc_min={glibc[0]}.{glibc[1]}\n"
                f"ctags={lock['CTAGS_VER']}\npip={lock['PIP_VER']}\n")
        for pkg, ver, fn, _ in wheels:
            f.write(f"wheel:{pkg}={ver}\n")
    with open(os.path.join(stage, "README.txt"), "w") as f:
        f.write(README.format(name=name, py=py_tag[2] + "." + py_tag[3:], glibc=f"{glibc[0]}.{glibc[1]}",
                              ctags=lock["CTAGS_VER"], wheels="\n".join(f"  wheels/{w[2]}" for w in wheels), tarball=ctags_fn))
    lines = []
    for sub in ("wheels", "tools"):
        for fn in sorted(os.listdir(os.path.join(stage, sub))):
            lines.append(f"{sha256_of(os.path.join(stage, sub, fn))}  {sub}/{fn}")
    for fn in ("VERSION", "README.txt"):
        lines.append(f"{sha256_of(os.path.join(stage, fn))}  {fn}")
    with open(os.path.join(stage, "MANIFEST.sha256"), "w") as f:
        f.write("\n".join(lines) + "\n")
    asset = os.path.join(out, f"{name}-{py_tag}-{PLATFORM}.tar.gz")
    with tarfile.open(asset, "w:gz") as tf:
        tf.add(stage, arcname=name, filter=_tar_filter)
    with open(asset + ".sha256", "w") as f:
        f.write(f"{sha256_of(asset)}  {os.path.basename(asset)}\n")
    shutil.rmtree(os.path.join(out, "stage"))
    print(f"release: {asset} ({os.path.getsize(asset) // 1024} KiB)")
    for pkg, ver, fn, how in wheels:
        print(f"  {fn} [{how}]")
    print(f"  tools/{ctags_fn} [{how}]  glibc >= {glibc[0]}.{glibc[1]}")
    return asset


def _tar_filter(ti):
    ti.uid = ti.gid = 0
    ti.uname = ti.gname = "odve"
    ti.mtime = int(_dt.datetime(2000, 1, 1, tzinfo=_dt.timezone.utc).timestamp())  # reproducible
    return ti


README = """{name}: portable tools of the odve code index (Linux x86_64, CPython {py})

Contents
  VERSION, MANIFEST.sha256 (sha256sum -c MANIFEST.sha256)
{wheels}
  tools/{tarball}      Universal Ctags {ctags}, static build

Needs on the target: a CPython {py} (any patch level; python is not bundled)
with its venv module, glibc >= {glibc}, bash, tar, xz. No pip, no network.

Install, from a clone of the repository that contains odve:
  odve/script/index/setup.sh --bundle <this tarball> [--python /path/to/python{py}]
  odve/script/index/odve_index.py build

setup.sh creates <root>/.odve-index/venv from the given python (without
ensurepip), installs pip and the wheels from this bundle into it, unpacks
ctags into <root>/.odve-index/tools, and reports what is active (--check).
"""


# ---------------------------------------------------------------- check
def check(path):
    with tarfile.open(path, "r:gz") as tf:
        names = tf.getnames()
        top = names[0].split("/")[0]
        man = tf.extractfile(f"{top}/MANIFEST.sha256").read().decode().splitlines()
        bad = []
        for line in man:
            sha, fn = line.split("  ", 1)
            data = tf.extractfile(f"{top}/{fn}").read()
            if hashlib.sha256(data).hexdigest() != sha:
                bad.append(fn)
        ver = tf.extractfile(f"{top}/VERSION").read().decode()
    print(ver.strip())
    print(f"{len(man)} files, {'all verified' if not bad else 'MISMATCH: ' + ' '.join(bad)}")
    return 0 if not bad else 1


# ---------------------------------------------------------------- upload
def gh(token, url, data=None, method=None, ctype="application/json"):
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json",
               "X-GitHub-Api-Version": "2022-11-28"}
    if data is not None:
        headers["Content-Type"] = ctype
    try:
        status, body, _ = http(url, data=data, headers=headers, method=method, timeout=600)
    except urllib.error.HTTPError as e:
        if e.code == 404 and method in (None, "GET"):
            return None
        raise SystemExit(f"release: GitHub {method or 'GET'} {url.split('?')[0]} -> {e.code} {e.read().decode(errors='replace')[:300]}")
    return json.loads(body) if body else {}


def upload(asset, repo, token, lock, version, replace):
    tag = f"index-tools-{version}"
    api = f"https://api.github.com/repos/{repo}"
    rel = gh(token, f"{api}/releases/tags/{tag}")
    if rel is None:
        body = {"tag_name": tag, "name": f"Code index tools {version}", "prerelease": False,
                "body": RELEASE_BODY.format(version=version, py=lock["PY_TAG"], ctags=lock["CTAGS_VER"],
                                            reqs=", ".join(f"{n}=={v}" for n, v in read_requirements()), pip=lock["PIP_VER"])}
        rel = gh(token, f"{api}/releases", json.dumps(body).encode(), "POST")
        print(f"release: created {rel['html_url']}")
    else:
        print(f"release: release exists {rel['html_url']}")
    existing = {a["name"]: a for a in rel.get("assets", [])}
    for path, ctype in ((asset, "application/gzip"), (asset + ".sha256", "text/plain")):
        name = os.path.basename(path)
        if name in existing:
            if not replace:
                raise SystemExit(f"release: asset {name} already attached (use --replace)")
            gh(token, f"{api}/releases/assets/{existing[name]['id']}", method="DELETE")
        with open(path, "rb") as f:
            data = f.read()
        up = rel["upload_url"].split("{")[0] + "?" + urllib.parse.urlencode({"name": name})
        a = gh(token, up, data, "POST", ctype)
        print(f"release: uploaded {a['browser_download_url']}")


RELEASE_BODY = """Portable tools of the odve code index (`odve/script/index/`): the Python wheels
({reqs}, pip=={pip}) for CPython {py} on linux x86_64 and the Universal Ctags {ctags}
static build, with a sha256 manifest. Python itself is not included.

Install from a clone: `odve/script/index/setup.sh --bundle <tarball>` (see README.txt inside).
"""


# ---------------------------------------------------------------- main
def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--out", help="output directory (default <root>/.odve-index/release)")
    ap.add_argument("--cache", help="download cache directory (default <out>/cache)")
    ap.add_argument("--version", help="bundle version (default tools.lock RELEASE_VER)")
    ap.add_argument("--check", metavar="BUNDLE", help="verify a bundle's manifest and exit")
    ap.add_argument("--upload", action="store_true", help="attach the bundle to the GitHub release index-tools-<ver>")
    ap.add_argument("--asset", help="with --upload: an already built bundle instead of building one")
    ap.add_argument("--repo", help="GitHub owner/name (default tools.lock RELEASE_REPO)")
    ap.add_argument("--token-env", default="GITHUB_TOKEN", help="environment variable holding the token")
    ap.add_argument("--token-file", help="file holding the token (one line)")
    ap.add_argument("--replace", action="store_true", help="replace assets already attached")
    a = ap.parse_args(argv)
    if a.check:
        return check(a.check)
    lock = read_lock()
    version = a.version or lock["RELEASE_VER"]
    out = a.out
    if not out:
        sys.path.insert(0, HERE)
        from idxlib import repo
        out = os.path.join(repo.find_root(), ".odve-index", "release")
    os.makedirs(out, exist_ok=True)
    cache = a.cache or os.path.join(out, "cache")
    asset = a.asset or build(out, cache, version, lock)
    if a.upload:
        token = ""
        if a.token_file:
            with open(a.token_file) as f:
                token = f.read().strip()
        else:
            token = os.environ.get(a.token_env, "")
        if not token:
            raise SystemExit(f"release: no token (set ${a.token_env} or --token-file)")
        upload(asset, a.repo or lock["RELEASE_REPO"], token, lock, version, a.replace)
    return 0


if __name__ == "__main__":
    sys.exit(main())
