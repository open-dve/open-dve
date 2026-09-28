#!/usr/bin/env python3
"""covgen.py - the functional-coverage tool of odve (doc/fcov-plan.md 5.2).

  covgen.py scan    -f <filelist>... -o <dir> [--model NAME]        pre-compile step (`acov`)
  covgen.py merge   <covmap.json> <run-dir-or-dump>... -o cov.db.json
  covgen.py report  <cov.db.json> -o <dir> [--code-cov <coverage.dat|.info|run-dir>...] [--pyucis <exe>]
  covgen.py codecov <coverage.dat|.info|run-dir>... -o <dir>          code coverage alone (Verilator)
  covgen.py analyze <cov.db.json> [--holes] [--tests] [--min]
  covgen.py export  <cov.db.json> --format ucis-xml|pyucis-yaml|json -o <file>
  covgen.py env     [--check]

scan     reads the sources on the filelists (following `include), parses the
         covergroups in their `ifdef ODVE_COV_NATIVE blocks and writes
         odve_cov_gen.svh, odve_cov_gen_classes.svh and covmap.json. A group it
         cannot understand becomes a stub class plus a warning; the exit code
         is 0 whatever the model looks like - the build is never broken by it.
merge    each run's dump (cov.dump at `final`, else the newest complete
         checkpoint cov.dump.0/1) -> one database with per-bin test attribution.
report   cov.txt, cov.json, cov.html (single file), cov.yaml (PyUCIS YAML),
         cov.xml (UCIS XML), index.html; with --code-cov also code/ (lines and
         branches per file, from Verilator's coverage.dat via
         verilator_coverage --write-info, or from lcov .info files directly).
         --pyucis adds cov_pyucis.html from the pyucis tool when it is installed.

Standard library only; nothing to install."""
import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from covlib import analyze, db as covdb, gen, lcov, report, ucisxml   # noqa: E402
from covlib.cgparse import parse_file                               # noqa: E402
from covlib.filelist import read_filelist, expand_includes          # noqa: E402
from covlib.model import Model                                      # noqa: E402

WARN = "[ODVE_COV] warning:"
CODE_EXCLUDE = r"verilated_std\.sv|/uvm/|uvm-1\.1d|1800\.2-2020"


# ------------------------------------------------------------------ scan

def cmd_scan(args):
    os.makedirs(args.out, exist_ok=True)
    try:
        files, incdirs = [], []
        for fl in args.f:
            r = read_filelist(fl)
            files.extend(f for f in r.files if f not in files)
            incdirs.extend(d for d in r.incdirs if d not in incdirs)
        files = expand_includes(files, incdirs)
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
        traceback.print_exc()
        gen.generate(Model(), args.out, args.model)
        print(f"{WARN} covgen scan crashed (see above) - generated an EMPTY coverage model so the build can go on",
              file=sys.stderr)
    return 0


# ----------------------------------------------------------------- merge

def cmd_merge(args):
    covmap = json.load(open(args.covmap))
    if not str(covmap.get("format", "")).startswith("odve-covmap 2"):
        print(f"covgen merge: {args.covmap}: unsupported map format {covmap.get('format')!r}", file=sys.stderr)
        return 1
    database, messages, ok = covdb.merge(covmap, args.dumps)
    for m in messages:
        print(f"covgen merge: {m}", file=sys.stderr if "skipped" in m else sys.stdout)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w") as f:
        json.dump(database, f, indent=1)
    print(f"covgen merge: {database['covered']}/{database['n']} bins covered "
          f"({covdb.pct(database['covered'], database['n']):.1f}%), {len(database['runs'])} run(s) -> {args.out}")
    return 0 if ok else 1


# ------------------------------------------------------------ code cov

def find_verilator_coverage():
    root = os.environ.get("VERILATOR_ROOT")
    if root and os.path.isfile(os.path.join(root, "bin", "verilator_coverage")):
        return os.path.join(root, "bin", "verilator_coverage")
    return shutil.which("verilator_coverage")


def code_data(paths, out_dir):
    """coverage.dat files, run dirs holding one, or .info files -> merged lcov
    data (dict) or None with a reason."""
    dats, infos = [], []
    for p in paths:
        if os.path.isdir(p):
            p = os.path.join(p, "coverage.dat")
        if not os.path.isfile(p):
            print(f"{WARN} code coverage: {p} not found - skipped", file=sys.stderr)
            continue
        (infos if p.endswith(".info") else dats).append(p)
    if dats:
        vc = find_verilator_coverage()
        if not vc:
            return None, "verilator_coverage not found (VERILATOR_ROOT or PATH) - cannot read coverage.dat"
        os.makedirs(out_dir, exist_ok=True)
        info = os.path.join(out_dir, "code.info")
        r = subprocess.run([vc, "--write-info", info] + dats, capture_output=True, text=True)
        if r.returncode != 0:
            return None, f"verilator_coverage failed: {r.stderr.strip()[:200]}"
        infos.append(info)
    if not infos:
        return None, "no coverage.dat / .info found"
    return lcov.merge_infos(infos), None


def cmd_codecov(args):
    data, why = code_data(args.inputs, args.out)
    if data is None:
        print(f"covgen codecov: {why}", file=sys.stderr)
        return 1
    summ = lcov.write_html(data, os.path.join(args.out, "code"), args.code_exclude, "code coverage")
    t = summ["total"]
    print(f"covgen codecov: lines {t['lh']}/{t['lf']} ({covdb.pct(t['lh'], t['lf']):.1f}%), "
          f"branches {t['bh']}/{t['bf']} ({covdb.pct(t['bh'], t['bf']):.1f}%), {len(summ['files'])} file(s) "
          f"-> {args.out}/code/index.html")
    return 0


# ---------------------------------------------------------------- report

def cmd_report(args):
    database = json.load(open(args.db))
    os.makedirs(args.out, exist_ok=True)
    code = None
    if args.code_cov:
        data, why = code_data(args.code_cov, args.out)
        if data is None:
            print(f"{WARN} code coverage skipped: {why}", file=sys.stderr)
        else:
            code = lcov.write_html(data, os.path.join(args.out, "code"), args.code_exclude, "code coverage")
    txt = os.path.join(args.out, "cov.txt")
    report.write_txt(database, txt)
    shutil.copyfile(args.db, os.path.join(args.out, "cov.json"))
    report.write_html(database, os.path.join(args.out, "cov.html"), code)
    report.write_pyucis_yaml(database, os.path.join(args.out, "cov.yaml"))
    ucisxml.write(database, os.path.join(args.out, "cov.xml"))
    report.write_index(os.path.join(args.out, "index.html"), database, code)
    if not args.quiet:
        print(open(txt).read())
    made = "index.html, cov.html, cov.txt, cov.json, cov.yaml, cov.xml" + (", code/" if code else "")
    print(f"covgen report: {args.out}/{{{made}}}")
    pyucis = args.pyucis or os.environ.get("PYUCIS") or shutil.which("pyucis")
    if pyucis:
        r = subprocess.run([pyucis, "report", "-if", "yaml", "-of", "html", "-o",
                            os.path.join(args.out, "cov_pyucis.html"), os.path.join(args.out, "cov.yaml")],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(f"covgen report: pyucis html {'ok' if r.returncode == 0 else 'FAILED'}: {args.out}/cov_pyucis.html")
    return 0


# ---------------------------------------------------------- analyze/export

def cmd_analyze(args):
    database = json.load(open(args.db))
    which = [w for w, on in (("holes", args.holes), ("tests", args.tests), ("min", args.min)) if on] \
        or ["holes", "tests", "min"]
    for w in which:
        print(analyze.text(database, w))
        print()
    return 0


def cmd_export(args):
    database = json.load(open(args.db))
    if args.format == "ucis-xml":
        ucisxml.write(database, args.out)
    elif args.format == "pyucis-yaml":
        report.write_pyucis_yaml(database, args.out)
    else:
        with open(args.out, "w") as f:
            json.dump(database, f, indent=1)
    print(f"covgen export: {args.format} -> {args.out}")
    return 0


def cmd_env(args):
    print(f"python: {platform.python_version()} ({sys.executable})")
    vc = find_verilator_coverage()
    print(f"verilator_coverage: {vc or 'not found - Verilator code coverage (CCOV=1) cannot be reported'}")
    py = os.environ.get("PYUCIS") or shutil.which("pyucis")
    print(f"pyucis (optional): {py or 'not installed - cov_pyucis.html skipped, everything else works'}")
    print("covgen itself needs nothing beyond the standard library.")
    return 0


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

    r = sub.add_parser("report", help="write the reports from cov.db.json")
    r.add_argument("db")
    r.add_argument("-o", "--out", default="cov")
    r.add_argument("--code-cov", nargs="*", metavar="DAT", help="coverage.dat / .info files or run dirs")
    r.add_argument("--code-exclude", default=CODE_EXCLUDE, help="regex of source files to leave out of code coverage")
    r.add_argument("--pyucis", help="pyucis executable for an extra cov_pyucis.html (default: $PYUCIS, then PATH)")
    r.add_argument("-q", "--quiet", action="store_true", help="do not print cov.txt")
    r.set_defaults(func=cmd_report)

    c = sub.add_parser("codecov", help="code-coverage report alone")
    c.add_argument("inputs", nargs="+", help="coverage.dat / .info files or run dirs")
    c.add_argument("-o", "--out", default="cov")
    c.add_argument("--code-exclude", default=CODE_EXCLUDE)
    c.set_defaults(func=cmd_codecov)

    a = sub.add_parser("analyze", help="holes, per-test contribution, minimal test set")
    a.add_argument("db")
    a.add_argument("--holes", action="store_true")
    a.add_argument("--tests", action="store_true")
    a.add_argument("--min", action="store_true")
    a.set_defaults(func=cmd_analyze)

    x = sub.add_parser("export", help="write the database in another format")
    x.add_argument("db")
    x.add_argument("--format", choices=["ucis-xml", "pyucis-yaml", "json"], required=True)
    x.add_argument("-o", "--out", required=True)
    x.set_defaults(func=cmd_export)

    e = sub.add_parser("env", help="what the environment provides")
    e.add_argument("--check", action="store_true")
    e.set_defaults(func=cmd_env)

    args = ap.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
