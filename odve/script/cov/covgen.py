#!/usr/bin/env python3
"""covgen.py - the functional-coverage tool of odve (doc/fcov-plan.md 5.2).

PHASE-0 SPIKE: only `merge` and `report` exist, working on a hand-written
covmap.json. `scan`/`gen`/`check`/`analyze`/`export`/`env` come with the
later phases.

  covgen.py merge  <covmap.json> <run-dir-or-dump>... -o cov.db.json
  covgen.py report <cov.db.json> -o <dir> [--pyucis <exe>]

`merge` reads each run's dump - `cov.dump` (written at `final`) or, when the
run was killed before that, the newest complete checkpoint `cov.dump.0/1` -
sums the bin counts and records which tests hit which bin.

`report` writes cov.txt, cov.json and attribution.html (ours), and when the
`pyucis` executable is available also cov.yaml (PyUCIS YAML), cov.xml (UCIS
XML) and cov.html (pyucis single-file HTML report). Standard library only.
"""
import argparse
import html
import json
import os
import shutil
import subprocess
import sys


# ----------------------------------------------------------------- dumps

def read_dump(path):
    """Parse one dump file. Returns (header dict, {idx: count}, end-tag) or
    None when the file is missing or truncated (no closing '# end' line)."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return None
    if not lines or not lines[-1].startswith("# end"):
        return None
    hdr, counts = {}, {}
    for line in lines[:-1]:
        if line.startswith("#"):
            toks = line[1:].split()
            # "# model apb_cov hash spike0" -> model=apb_cov, hash=spike0
            for k, v in zip(toks[::2], toks[1::2]):
                hdr[k] = v
            if toks and toks[0] == "odve-cov":
                hdr["version"] = toks[1]
        elif line.strip():
            idx, cnt = line.split()
            counts[int(idx)] = int(cnt)
    return hdr, counts, lines[-1].split()[-1]


def resolve_dump(arg):
    """A run directory or a dump path -> the best dump in it: the final dump
    when complete, else the checkpoint with the highest sequence number that
    is complete. Returns (path, parsed, kind) or (None, None, reason)."""
    if os.path.isdir(arg):
        base = os.path.join(arg, "cov.dump")
    else:
        base = arg
    d = read_dump(base)
    if d is not None:
        return base, d, "final"
    best = None
    for suffix in (".0", ".1"):
        p = base + suffix
        d = read_dump(p)
        if d is None:
            continue
        seq = int(d[2]) if d[2].isdigit() else -1
        if best is None or seq > best[2]:
            best = (p, d, seq)
    if best is not None:
        return best[0], best[1], f"checkpoint {best[2]}"
    if os.path.exists(base) or os.path.exists(base + ".0") or os.path.exists(base + ".1"):
        return None, None, "dump(s) present but truncated"
    return None, None, "no dump"


# ----------------------------------------------------------------- model

def bin_names(covmap):
    """Flat index -> (group, point-or-cross, bin name, is_cross)."""
    names = {}
    for g in covmap["groups"]:
        pts = {p["name"]: p for p in g["points"]}
        for p in g["points"]:
            for i, b in enumerate(p["bins"]):
                names[p["base"] + i] = (g["name"], p["name"], b, False)
        for x in g.get("crosses", []):
            members = [pts[n]["bins"] for n in x["points"]]
            combos = [[]]
            for m in members:                       # row-major product
                combos = [c + [b] for c in combos for b in m]
            for i, c in enumerate(combos):
                names[x["base"] + i] = (g["name"], x["name"], ",".join(c), True)
    return names


# ----------------------------------------------------------------- merge

def cmd_merge(args):
    covmap = json.load(open(args.covmap))
    names = bin_names(covmap)
    n = covmap["n"]
    counts = [0] * n
    tests_per_bin = [set() for _ in range(n)]
    runs = []
    rc = 0
    for arg in args.dumps:
        path, parsed, kind = resolve_dump(arg)
        if parsed is None:
            print(f"covgen merge: {arg}: {kind} - skipped", file=sys.stderr)
            rc = 1
            continue
        hdr, cnts, _ = parsed
        if hdr.get("hash") != covmap["hash"]:
            print(f"covgen merge: {path}: model hash {hdr.get('hash')} != map {covmap['hash']} - skipped",
                  file=sys.stderr)
            rc = 1
            continue
        test = hdr.get("test") or os.path.basename(os.path.dirname(os.path.abspath(path)))
        run = os.path.basename(os.path.dirname(os.path.abspath(path)))
        hits = 0
        for idx, c in cnts.items():
            if idx < n:
                counts[idx] += c
                tests_per_bin[idx].add(test)
                hits += 1
        runs.append({"test": test, "run": run, "dump": path, "kind": kind,
                     "samples": int(hdr.get("samples", 0)), "bins_hit": hits})
        print(f"covgen merge: {path}: {kind}, test {test}, {hits} bins hit")

    bins = []
    for idx in range(n):
        g, p, b, is_x = names.get(idx, ("?", "?", f"#{idx}", False))
        bins.append({"idx": idx, "group": g, "point": p, "bin": b, "cross": is_x,
                     "count": counts[idx], "tests": sorted(tests_per_bin[idx])})
    covered = sum(1 for b in bins if b["count"] > 0)
    db = {"format": "odve-covdb 1", "model": covmap["model"], "hash": covmap["hash"],
          "n": n, "covered": covered, "runs": runs, "bins": bins, "map": covmap}
    with open(args.out, "w") as f:
        json.dump(db, f, indent=1)
    print(f"covgen merge: {covered}/{n} bins covered ({100.0 * covered / n:.1f}%), "
          f"{len(runs)} run(s) -> {args.out}")
    return rc


# ----------------------------------------------------------------- report

def summarize(db):
    """Per group/point coverage percentages from the flat bins."""
    out = {}
    for b in db["bins"]:
        g = out.setdefault(b["group"], {})
        p = g.setdefault(b["point"], {"cross": b["cross"], "total": 0, "hit": 0, "bins": []})
        p["total"] += 1
        p["hit"] += 1 if b["count"] > 0 else 0
        p["bins"].append(b)
    return out


def write_txt(db, path):
    s = summarize(db)
    with open(path, "w") as f:
        f.write(f"model {db['model']} ({db['hash']}): {db['covered']}/{db['n']} bins "
                f"= {100.0 * db['covered'] / db['n']:.1f}%\n")
        f.write(f"runs: {', '.join(r['test'] + ' (' + r['kind'] + ')' for r in db['runs'])}\n")
        for g, pts in s.items():
            f.write(f"\n{g}\n")
            for p, d in pts.items():
                kind = "cross" if d["cross"] else "point"
                f.write(f"  {kind} {p}: {d['hit']}/{d['total']} = {100.0 * d['hit'] / d['total']:.1f}%\n")
                for b in d["bins"]:
                    mark = "   " if b["count"] > 0 else "-- "
                    f.write(f"    {mark}{b['bin']:<24} {b['count']:>8}  {' '.join(b['tests'])}\n")


def write_attribution_html(db, path):
    s = summarize(db)
    e = html.escape
    rows = []
    for g, pts in s.items():
        for p, d in pts.items():
            for b in d["bins"]:
                cls = "hit" if b["count"] > 0 else "miss"
                rows.append(f"<tr class='{cls}'><td>{e(g)}</td><td>{e(p)}</td><td>{e(b['bin'])}</td>"
                            f"<td class='n'>{b['count']}</td><td>{e(', '.join(b['tests'])) or '&mdash;'}</td></tr>")
    tests = {}
    for b in db["bins"]:
        for t in b["tests"]:
            tests.setdefault(t, {"bins": 0, "unique": 0})
            tests[t]["bins"] += 1
            if len(b["tests"]) == 1:
                tests[t]["unique"] += 1
    trows = "".join(f"<tr><td>{e(t)}</td><td class='n'>{v['bins']}</td><td class='n'>{v['unique']}</td></tr>"
                    for t, v in sorted(tests.items()))
    pct = 100.0 * db["covered"] / db["n"]
    doc = f"""<!doctype html><meta charset="utf-8"><title>{e(db['model'])} - test attribution</title>
<style>body{{font:14px system-ui,sans-serif;margin:24px}} table{{border-collapse:collapse;margin:12px 0}}
td,th{{border:1px solid #ccc;padding:3px 8px;text-align:left}} .n{{text-align:right}}
tr.miss td{{background:#fde8e8}} tr.hit td:nth-child(4){{background:#e6f4e6}} h2{{margin-top:28px}}</style>
<h1>{e(db['model'])}: {db['covered']}/{db['n']} bins = {pct:.1f}%</h1>
<h2>Which test hit which bin</h2>
<table><tr><th>group</th><th>point / cross</th><th>bin</th><th>hits</th><th>tests</th></tr>{''.join(rows)}</table>
<h2>Per test</h2>
<table><tr><th>test</th><th>bins hit</th><th>bins only this test hit</th></tr>{trows}</table>
<p>Runs: {e(', '.join(r['test'] + ' (' + r['kind'] + ', ' + str(r['samples']) + ' samples)' for r in db['runs']))}</p>
"""
    with open(path, "w") as f:
        f.write(doc)


def write_pyucis_yaml(db, path):
    """PyUCIS YAML (ucis/schema/coverage.json): covergroup types -> instances
    -> coverpoints/crosses -> bins{name,count}."""
    s = summarize(db)
    lines = ["coverage:", "  covergroups:"]
    for g, pts in s.items():
        lines += [f"  - name: {g}", "    weight: 1", "    instances:", f"    - name: {g}_i", "      coverpoints:"]
        for p, d in pts.items():
            if d["cross"]:
                continue
            lines += [f"      - name: {p}", "        atleast: 1", "        bins:"]
            lines += [f"        - {{name: '{b['bin']}', count: {b['count']}}}" for b in d["bins"]]
        crosses = [(p, d) for p, d in pts.items() if d["cross"]]
        if crosses:
            lines.append("      crosses:")
            for p, d in crosses:
                members = next(x["points"] for gg in db["map"]["groups"] if gg["name"] == g
                               for x in gg.get("crosses", []) if x["name"] == p)
                lines += [f"      - name: {p}", "        atleast: 1",
                          f"        coverpoints: [{', '.join(members)}]", "        bins:"]
                lines += [f"        - {{name: '{b['bin']}', count: {b['count']}}}" for b in d["bins"]]
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def cmd_report(args):
    db = json.load(open(args.db))
    os.makedirs(args.out, exist_ok=True)
    txt = os.path.join(args.out, "cov.txt")
    write_txt(db, txt)
    shutil.copyfile(args.db, os.path.join(args.out, "cov.json"))
    write_attribution_html(db, os.path.join(args.out, "attribution.html"))
    print(open(txt).read())
    print(f"covgen report: {args.out}/cov.txt, cov.json, attribution.html")

    pyucis = args.pyucis or os.environ.get("PYUCIS") or shutil.which("pyucis")
    yaml = os.path.join(args.out, "cov.yaml")
    write_pyucis_yaml(db, yaml)
    if not pyucis:
        print("covgen report: pyucis not found (PYUCIS=<exe> or --pyucis) - cov.yaml written, "
              "cov.xml/cov.html skipped")
        return 0
    quiet = {"stderr": subprocess.DEVNULL, "stdout": subprocess.DEVNULL}
    ok = True
    for fmt, out in (("xml", "cov.xml"), ):
        r = subprocess.run([pyucis, "convert", "-if", "yaml", "-of", fmt, "-o",
                            os.path.join(args.out, out), yaml], **quiet)
        ok &= r.returncode == 0
    r = subprocess.run([pyucis, "report", "-if", "yaml", "-of", "html", "-o",
                        os.path.join(args.out, "cov.html"), yaml], **quiet)
    ok &= r.returncode == 0
    print(f"covgen report: pyucis {'ok' if ok else 'FAILED'}: {args.out}/cov.yaml, cov.xml, cov.html")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    m = sub.add_parser("merge", help="merge run dumps into cov.db.json")
    m.add_argument("covmap")
    m.add_argument("dumps", nargs="+", help="run directories or dump files")
    m.add_argument("-o", "--out", default="cov.db.json")
    m.set_defaults(func=cmd_merge)
    r = sub.add_parser("report", help="write reports from cov.db.json")
    r.add_argument("db")
    r.add_argument("-o", "--out", default="cov")
    r.add_argument("--pyucis", help="pyucis executable (default: $PYUCIS, then PATH)")
    r.set_defaults(func=cmd_report)
    args = ap.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
