#!/usr/bin/env python3
"""Upload the portable Verilator bundle to a GitHub release (standard library only, no gh).

    release.py --upload [--asset FILE] [--repo OWNER/REPO] [--tag TAG] [--replace]
               [--token-env GITHUB_TOKEN | --token-file FILE] [--notes FILE]
    release.py --check [--asset FILE]        verify the .sha256 sidecar

Defaults come from bundle.lock next to this script: the asset is bundle/<BUNDLE_ASSET>, the
release is RELEASE_TAG on RELEASE_REPO (created when missing). The token is read from the
environment or a file and never printed. The .sha256 sidecar is uploaded next to the tarball.
"""
import argparse
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))


def read_lock(path=os.path.join(HERE, "bundle.lock")):
    lock = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            v = v.strip().strip('"')
            lock[k.strip()] = re.sub(r"\$\{(\w+)\}", lambda m: lock.get(m.group(1), ""), v)
    return lock


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def check(asset):
    side = asset + ".sha256"
    if not os.path.exists(side):
        print(f"no sidecar {side}")
        return 1
    want = open(side).read().split()[0]
    got = sha256_of(asset)
    print(f"{'ok' if want == got else 'MISMATCH'}: {os.path.basename(asset)} {got[:16]}... ({os.path.getsize(asset) >> 20} MiB)")
    return 0 if want == got else 1


def gh(method, url, token, data=None, ctype="application/json"):
    body = None
    if data is not None:
        body = data if isinstance(data, bytes) else json.dumps(data).encode()
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if body is not None:
        req.add_header("Content-Type", ctype)
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")


def upload(asset, repo, tag, token, replace, notes):
    api = f"https://api.github.com/repos/{repo}"
    st, rel = gh("GET", f"{api}/releases/tags/{tag}", token)
    if st == 404:
        body = notes or f"Portable Verilator bundle `{os.path.basename(asset)}`: Verilator + g++ + make + perl for Linux x86_64 (glibc >= 2.17), no root, no network. Install with `odve/script/verilator-portable/install.sh --release`."
        st, rel = gh("POST", f"{api}/releases", token, {"tag_name": tag, "name": tag, "body": body, "draft": False, "prerelease": False})
        if st not in (200, 201):
            print(f"creating release {tag} failed: HTTP {st} {rel}", file=sys.stderr)
            return 1
        print(f"created release {tag}")
    elif st != 200:
        print(f"GET release {tag} failed: HTTP {st} {rel}", file=sys.stderr)
        return 1
    have = {a["name"]: a for a in rel.get("assets", [])}
    upload_url = rel["upload_url"].split("{")[0]
    for path in (asset, asset + ".sha256"):
        if not os.path.exists(path):
            print(f"missing {path}", file=sys.stderr)
            return 1
        name = os.path.basename(path)
        if name in have:
            if not replace:
                print(f"{name} already on {tag} (use --replace)", file=sys.stderr)
                return 1
            st, _ = gh("DELETE", f"{api}/releases/assets/{have[name]['id']}", token)
            if st != 204:
                print(f"deleting old {name} failed: HTTP {st}", file=sys.stderr)
                return 1
        ctype = "application/gzip" if name.endswith(".gz") else "text/plain"
        with open(path, "rb") as f:
            data = f.read()
        print(f"uploading {name} ({len(data) >> 20} MiB)...")
        st, res = gh("POST", f"{upload_url}?{urllib.parse.urlencode({'name': name})}", token, data, ctype)
        if st not in (200, 201):
            print(f"upload of {name} failed: HTTP {st} {str(res)[:300]}", file=sys.stderr)
            return 1
        print(f"  {res['browser_download_url']}")
    print(f"release: {rel['html_url']}")
    return 0


def main():
    lock = read_lock()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--upload", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--asset", default=os.path.join(HERE, "bundle", lock["BUNDLE_ASSET"]))
    ap.add_argument("--repo", default=lock["RELEASE_REPO"])
    ap.add_argument("--tag", default=lock["RELEASE_TAG"])
    ap.add_argument("--replace", action="store_true", help="overwrite assets of the same name")
    ap.add_argument("--token-env", default="GITHUB_TOKEN")
    ap.add_argument("--token-file")
    ap.add_argument("--notes", help="file with the release body (markdown) when the release is created")
    a = ap.parse_args()
    if not (a.upload or a.check):
        ap.print_help()
        return 2
    if check(a.asset) and a.upload:
        return 1
    if not a.upload:
        return 0
    token = open(a.token_file).read().strip() if a.token_file else os.environ.get(a.token_env, "")
    if not token:
        print(f"no token: set ${a.token_env} or pass --token-file", file=sys.stderr)
        return 1
    notes = open(a.notes).read() if a.notes else None
    return upload(a.asset, a.repo, a.tag, token, a.replace, notes)


if __name__ == "__main__":
    sys.exit(main())
