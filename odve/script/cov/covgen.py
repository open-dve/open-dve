#!/usr/bin/env python3
"""covgen.py - the functional-coverage tool of odve (doc/fcov-plan.md 5.2).

  covgen.py scan   -f <filelist>... -o <dir> [--model NAME]     pre-compile step (`acov`)
  covgen.py merge  <covmap.json> <run-dir-or-dump>... -o cov.db.json
  covgen.py report <cov.db.json> -o <dir> [--pyucis <exe>]

scan   reads the sources on the filelists, parses the covergroups in their
       `ifdef ODVE_COV_NATIVE blocks and writes odve_cov_gen.svh,
       odve_cov_gen_classes.svh and covmap.json into <dir>. A covergroup it
       cannot understand becomes a stub class plus a warning; the exit code is
       0 whatever the model looks like, so the build is never broken by it.
merge  reads each run's dump - cov.dump (written at `final`) or, when the run
       was killed before that, the newest complete checkpoint cov.dump.0/1 -
       sums the bin counts and records which tests hit which bin.
report writes cov.txt, cov.json and attribution.html (ours) and, when the
       `pyucis` executable is available, cov.yaml (PyUCIS YAML), cov.xml (UCIS
       XML) and cov.html (pyucis single-file HTML report).

Standard library only. `analyze`/`export`/`env` come with the later phases."""
import argparse
import html
import json
import os
import shutil
import subprocess
import sys
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from covlib import gen                              # noqa: E402
from covlib.cgparse import parse_file               # noqa: E402
from covlib.filelist import read_filelist, expand_includes   # noqa: E402
from covlib.model import Model                      # noqa: E402

WARN = "[ODVE_COV] warning:"


# ------------------------------------------------------------------ scan

def cmd_scan(args):
    os.makedirs(args.out, exist_ok=True)
    try:
        files, incdirs = [], []
        for fl in args.f:
            r = read_filelist(fl)
            files.extend(f for f in r.files if f not in files)
            incdirs.extend(d for d in r.incdirs if d not in incdirs)
        files = expand_includes(files, incdirs)   # `include'd files carry covergroups too
        model = Model()
        for path in files:
            if not os.path.isfile(path):
                print(f"{WARN} {path}: not found (listed in a filelist) - skipped", file=sys.stderr)
                continue
            groups, created, sampled = parse_file(path)
            model.groups.extend(groups)
            model.created.extend(c for c in created if c not in model.created)
            model.sampled.extend(s for s in sampled if s not in model.sampled)
        summary, warnings = gen.generate(model, args.out, args.model)
        for w in warnings:
            print(f"{WARN} {w}", file=sys.stderr)
        print(f"covgen scan: {len(files)} file(s), {len(summary['groups'])} covergroup(s) "
              f"[{', '.join(summary['groups']) or '-'}], {len(summary['stubs'])} stub(s), "
              f"{summary['n']} bins, model {args.model} hash {summary['hash']} -> {args.out}")
    except Exception:
        # A crash must still leave a compilable include behind: an empty model.
        traceback.print_exc()
        gen.generate(Model(), args.out, args.model)
        print(f"{WARN} covgen scan crashed (see above) - generated an EMPTY coverage model so the build can go on",
              file=sys.stderr)
    return 0


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
            for k, v in zip(toks[::2], toks[1::2]):
                hdr[k] = v
        elif line.strip():
            idx, cnt = line.split()
            counts[int(idx)] = int(cnt)
    return hdr, counts, lines[-1].split()[-1]


def resolve_dump(arg):
    """A run directory or a dump path -> the best dump in it: the final dump
    when complete, else the checkpoint with the highest sequence number that
    is complete. Returns (path, parsed, kind) or (None, None, reason)."""
    base = os.path.join(arg, "cov.dump") if os.path.isdir(arg) else arg
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
    if any(os.path.exists(base + s) for s in ("", ".0", ".1")):
        return None, None, "dump(s) present but truncated"
    return None, None, "no dump"


# ----------------------------------------------------------------- model

def bin_table(covmap):
    """The coverage-eligible bins of a covmap (v2): {flat idx: bin dict}.
    Ignored and illegal cross bins are left out - they are never coverage."""
    table = {}
    for g in covmap["groups"]:
        if g.get("unsupported"):
            continue
        for p in g["points"]:
            for i, b in enumerate(p["bins"]):
                table[p["base"] + i] = {"group": g["name"], "point": p["name"], "bin": b,
                                        "cross": False, "at_least": p["at_least"]}
        for x in g["crosses"]:
            for i, (b, kind) in enumerate(zip(x["bins"], x["kinds"])):
                if kind == gen.X_BIN:
                    table[x["base"] + i] = {"group": g["name"], "point": x["name"], "bin": b,
                                            "cross": True, "at_least": x["at_least"]}
    return table


# ----------------------------------------------------------------- merge

def cmd_merge(args):
    covmap = json.load(open(args.covmap))
    if not str(covmap.get("format", "")).startswith("odve-covmap 2"):
        print(f"covgen merge: {args.covmap}: unsupported map format {covmap.get('format')!r}", file=sys.stderr)
        return 1
    table = bin_table(covmap)
    counts = {i: 0 for i in table}
    tests_per_bin = {i: set() for i in table}
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
            if idx in table:
                counts[idx] += c
                tests_per_bin[idx].add(test)
                hits += 1
        runs.append({"test": test, "run": run, "dump": path, "kind": kind,
                     "samples": int(hdr.get("samples", 0)), "bins_hit": hits})
        print(f"covgen merge: {path}: {kind}, test {test}, {hits} bins hit")

    bins = []
    for idx in sorted(table):
        b = dict(table[idx])
        b.update({"idx": idx, "count": counts[idx], "tests": sorted(tests_per_bin[idx]),
                  "covered": counts[idx] >= b["at_least"]})
        bins.append(b)
    total = len(bins)
    covered = sum(1 for b in bins if b["covered"])
    db = {"format": "odve-covdb 2", "model": covmap["model"], "hash": covmap["hash"],
          "n": total, "covered": covered, "runs": runs, "bins": bins,
          "skipped": [g["name"] for g in covmap["groups"] if g.get("unsupported")], "map": covmap}
    with open(args.out, "w") as f:
        json.dump(db, f, indent=1)
    pct = 100.0 * covered / total if total else 0.0
    print(f"covgen merge: {covered}/{total} bins covered ({pct:.1f}%), {len(runs)} run(s) -> {args.out}")
    return rc


# ---------------------------------------------------------------- report

def summarize(db):
    """Per group/point coverage from the flat bins."""
    out = {}
    for b in db["bins"]:
        g = out.setdefault(b["group"], {})
        p = g.setdefault(b["point"], {"cross": b["cross"], "total": 0, "hit": 0, "bins": []})
        p["total"] += 1
        p["hit"] += 1 if b["covered"] else 0
        p["bins"].append(b)
    return out


def pct(hit, total):
    return 100.0 * hit / total if total else 0.0


def write_txt(db, path):
    s = summarize(db)
    with open(path, "w") as f:
        f.write(f"model {db['model']} ({db['hash']}): {db['covered']}/{db['n']} bins "
                f"= {pct(db['covered'], db['n']):.1f}%\n")
        f.write(f"runs: {', '.join(r['test'] + ' (' + r['kind'] + ')' for r in db['runs'])}\n")
        if db.get("skipped"):
            f.write(f"skipped covergroups (unsupported, no coverage): {', '.join(db['skipped'])}\n")
        for g, pts in s.items():
            f.write(f"\n{g}\n")
            for p, d in pts.items():
                kind = "cross" if d["cross"] else "point"
                f.write(f"  {kind} {p}: {d['hit']}/{d['total']} = {pct(d['hit'], d['total']):.1f}%\n")
                for b in d["bins"]:
                    mark = "   " if b["covered"] else "-- "
                    al = f" (at_least {b['at_least']})" if b["at_least"] > 1 else ""
                    f.write(f"    {mark}{b['bin']:<24} {b['count']:>8}{al}  {' '.join(b['tests'])}\n")


def write_attribution_html(db, path):
    s = summarize(db)
    e = html.escape
    rows = []
    for g, pts in s.items():
        for p, d in pts.items():
            for b in d["bins"]:
                cls = "hit" if b["covered"] else "miss"
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
    skipped = ""
    if db.get("skipped"):
        skipped = f"<p class='warn'>Skipped covergroups (unsupported, no coverage collected): {e(', '.join(db['skipped']))}</p>"
    doc = f"""<!doctype html><meta charset="utf-8"><title>{e(db['model'])} - test attribution</title>
<style>body{{font:14px system-ui,sans-serif;margin:24px}} table{{border-collapse:collapse;margin:12px 0}}
td,th{{border:1px solid #ccc;padding:3px 8px;text-align:left}} .n{{text-align:right}}
tr.miss td{{background:#fde8e8}} tr.hit td:nth-child(4){{background:#e6f4e6}} h2{{margin-top:28px}}
.warn{{background:#fff3cd;padding:8px}}</style>
<h1>{e(db['model'])}: {db['covered']}/{db['n']} bins = {pct(db['covered'], db['n']):.1f}%</h1>
{skipped}
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
    crosses_of = {g["name"]: {x["name"]: x["points"] for x in g.get("crosses", [])}
                  for g in db["map"]["groups"] if not g.get("unsupported")}
    q = lambda name: "'" + name.replace("'", "''") + "'"
    lines = ["coverage:", "  covergroups:"]
    for g, pts in s.items():
        lines += [f"  - name: {g}", "    weight: 1", "    instances:", f"    - name: {g}_i", "      coverpoints:"]
        for p, d in pts.items():
            if d["cross"]:
                continue
            lines += [f"      - name: {p}", f"        atleast: {d['bins'][0]['at_least']}", "        bins:"]
            lines += [f"        - {{name: {q(b['bin'])}, count: {b['count']}}}" for b in d["bins"]]
        crosses = [(p, d) for p, d in pts.items() if d["cross"]]
        if crosses:
            lines.append("      crosses:")
            for p, d in crosses:
                lines += [f"      - name: {p}", f"        atleast: {d['bins'][0]['at_least']}",
                          f"        coverpoints: [{', '.join(crosses_of[g][p])}]", "        bins:"]
                lines += [f"        - {{name: {q(b['bin'])}, count: {b['count']}}}" for b in d["bins"]]
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
    ok = subprocess.run([pyucis, "convert", "-if", "yaml", "-of", "xml", "-o",
                         os.path.join(args.out, "cov.xml"), yaml], **quiet).returncode == 0
    ok &= subprocess.run([pyucis, "report", "-if", "yaml", "-of", "html", "-o",
                          os.path.join(args.out, "cov.html"), yaml], **quiet).returncode == 0
    print(f"covgen report: pyucis {'ok' if ok else 'FAILED'}: {args.out}/cov.yaml, cov.xml, cov.html")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("scan", help="parse the covergroups in the sources and generate the build files")
    s.add_argument("-f", action="append", required=True, metavar="FILELIST", help="filelist to scan (repeatable)")
    s.add_argument("-o", "--out", required=True, help="output directory ($(COV_DIR))")
    s.add_argument("--model", default="cov", help="model name for the dump header / reports")
    s.set_defaults(func=cmd_scan)
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
