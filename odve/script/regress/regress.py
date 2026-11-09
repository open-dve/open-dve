#!/usr/bin/env python3
"""Regression runner. Builds once (`make clean all`), then runs every entry of
../rlist/<name>.list as `make run RUN_DIR=<entry> <entry opts>` with up to
-max_jobs in flight. Each run is judged from its own <RUN_DIR>/run.log (UVM
report summary, last UVM_ERROR/UVM_FATAL message) and its log is printed the
moment that job finishes, while the rest keep running; a summary table follows
once all of them are done. Every run gets RUN_OPTS+=+UVM_MAX_QUIT_COUNT=1 so a
simulation stops at its first UVM error, unless the list entry or -ropts sets
+UVM_MAX_QUIT_COUNT itself; other UVM plusargs go the same way, e.g.
-ropts="RUN_OPTS+=+UVM_VERBOSITY=UVM_HIGH". Every run gets its own random
seed (make's SEED, see script/common/run.mk) unless -ropts="SEED=<n>" or the
list entry pins one; the seed is shown on each status line and, with -exer,
with the command that re-runs the failure under it. Each run is also capped at
TIMEOUT minutes by the Makefiles (default 180, see script/common/run.mk);
a run killed on the clock says so in its verdict."""
import sys
import argparse
import json
import os
import re
import subprocess
import time


odve_name="ODVE"
if odve_name in os.environ:
    odve=os.environ[odve_name]
    print ( f"ODVE variable is ({odve})")
else : 
    print ( f"ODVE is not defined")
    exit (1)

lib_path=f"{odve}/script/regress/"
sys.path.append(lib_path)
#local python classes
from readlist  import readlist
from list2json import list2json
from jobrunner import JobRunner
from runlog    import parse_run_log, extract_error


def seed_tag(status):
    """" seed=<n>" for a status line, empty when the log carried no marker."""
    return f"  seed={status.seed}" if status.seed else ""


def repro_cmd(result, status):
    """The make command that re-runs this job with the same seed: make takes
    the last assignment on its command line, so SEED= appended to the
    original command pins the seed and changes nothing else."""
    return f"{result.command} SEED={status.seed}" if status.seed else result.command

cwd=os.getcwd()
RULE = "=" * 78
THIN = "-" * 78
# Plusargs every run gets through RUN_OPTS+= unless the list entry or -ropts
# already carries the same +UVM_ key: stop at the first UVM error rather than
# simulate on past it. UVM takes the first +UVM_MAX_QUIT_COUNT it sees, so a
# user's value must replace ours, not follow it.
DEFAULT_PLUSARGS = "+UVM_MAX_QUIT_COUNT=1"


def test_name(opts):
    """UVM test a list entry names, for the -exer report. Empty when the entry
    sets none: the TB then runs whatever top.sv's run_test() call hardcodes."""
    m = re.search(r"(?:^|\s)TESTNAME=(\S+)", opts)
    return m.group(1).strip("'\"") if m else ""


def print_output(result, tail):
    """Dump a job's captured make output (whole thing, or the last `tail` lines)."""
    text = result.stdout
    if result.stderr.strip():
        text += ("\n" if text and not text.endswith("\n") else "") + result.stderr
    lines = text.splitlines()
    if tail and len(lines) > tail:
        print(f"... ({len(lines) - tail} earlier lines omitted, -tail {tail})")
        lines = lines[-tail:]
    for line in lines:
        print(line)


def print_log(path, tail):
    """Print a run's run.log (whole thing, or the last `tail` lines)."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError as e:
        print(f"(cannot read {path}: {e})")
        return
    if tail and len(lines) > tail:
        print(f"... ({len(lines) - tail} earlier lines omitted, -tail {tail})")
        lines = lines[-tail:]
    for line in lines:
        print(line)


def main():
    parser = argparse.ArgumentParser(description="Regression runner script by regress list")
    parser.add_argument("top_list", help="Regression list name")
    parser.add_argument("-max_jobs", "-j", "--max_jobs", type=int, default=4,
                        help="How many runs to simulate at the same time (default 4)")
    parser.add_argument("-no_comp", "--no_comp", action="store_true", help="Skip the compile step and run the list against the existing build")
    parser.add_argument("-ropts", "--ropts", default="",
                        help='Extra make variables applied to BOTH the compile and the run jobs, '
                             'e.g. -ropts="VERILATOR=1" (or "VERI=1") to run the list under '
                             'Verilator instead of Questa. UVM plusargs go through RUN_OPTS, '
                             'e.g. -ropts="RUN_OPTS+=+UVM_VERBOSITY=UVM_HIGH"; giving '
                             '+UVM_MAX_QUIT_COUNT there replaces the default '
                             f'"{DEFAULT_PLUSARGS}". Other make variables work too, '
                             'e.g. -ropts="TIMEOUT=30" for a 30-minute cap per run, or '
                             '-ropts="SEED=101" to run the whole list under one seed instead of '
                             'a random seed per run')
    parser.add_argument("-tail", "--tail", type=int, default=0, metavar="LINES",
                        help="Print only the last LINES lines of each log (default: whole log)")
    parser.add_argument("-quiet", "-q", "--quiet", action="store_true",
                        help="Print only the status line per run, not its run.log")
    parser.add_argument("-cov", "--cov", action="store_true",
                        help="Functional coverage: build and run with FCOV=1, then merge every run's dump and "
                             "write cov/index.html (cov.html, cov.txt, cov.xml ...) next to the run dirs")
    parser.add_argument("-ccov", "--ccov", action="store_true",
                        help="Code coverage: build and run with CCOV=1 (Verilator: coverage.dat per run, "
                             "reported into cov/code/; Questa needs a licensed edition)")
    parser.add_argument("-exer", "--exer", action="store_true",
                        help="Extract errors: after the summary, re-read every failed run's "
                             "run.log and print its test name, error message and make command")

    args = parser.parse_args()
    maxj = args.max_jobs
    if args.cov:
        args.ropts = (args.ropts + " FCOV=1").strip()
    if args.ccov:
        args.ropts = (args.ropts + " CCOV=1").strip()

    tlist=f"{cwd}/../rlist/{args.top_list}.list"
    print (f"file.list is : {tlist}")

    rf = readlist(f"{tlist}")
    rf.readfile()
    rf.printline()

    l2j = list2json ()
    try:
        cmdsj = l2j.convert2j(rf.getlines())
    except ValueError as e:
        print(f"Bad regression list {tlist}: {e}")
        exit(1)
    if not cmdsj:
        print(f"Regression list {tlist} has no runs.")
        exit(1)
    print(json.dumps(cmdsj, indent=4))

    cmdsl = l2j.gencmd(cmdsj, args.ropts, DEFAULT_PLUSARGS)
    names = list(cmdsj)
    jobs = list(zip(names, cmdsl))
    for name, cmd in jobs:
        print(f"{name}: {cmd}")

    if args.ropts:
        print(f"extra make args (-ropts): {args.ropts}")
    print(f"max parallel runs: {maxj}; default plusargs: {DEFAULT_PLUSARGS} (RUN_OPTS+=; override via -ropts)")

    if not args.no_comp:
        # -ropts must reach the compile too, otherwise the list would be built
        # with one simulator and run with another.
        comp_cmd = f"make clean all {args.ropts}".rstrip()
        print(f"\n{RULE}\ncompile: {comp_cmd}")
        result = JobRunner(1).run_jobs([("compile", comp_cmd)])[0]
        print_output(result, args.tail)
        print(f"{THIN}\ncompile: {'OK' if result.returncode == 0 else 'FAIL'} "
              f"(exit {result.returncode}, {result.seconds:.1f}s)")
        if result.returncode != 0:
            print("Compile failed (see output above) -- aborting regression run.")
            exit(1)

    statuses = {}

    def on_done(result, done, total):
        """Called as each run finishes: judge it from its log, print the status
        line and (unless -quiet) the log itself, then let the others continue."""
        log = os.path.join(cwd, list2json.run_dir(result.name, cmdsj[result.name]["cmd"]), "run.log")
        status = parse_run_log(log, result.returncode)
        statuses[result.name] = (status, result, log)
        print(f"\n{RULE}")
        print(f"[{done}/{total}] {result.name}: {status.verdict}  ({result.seconds:.1f}s)  {status.reason}{seed_tag(status)}")
        if status.last_error:
            print(f"  last: {status.last_error}")
        print(f"  log : {log}")
        if not args.quiet:
            print(THIN)
            if os.path.isfile(log):
                print_log(log, args.tail)
            else:
                # No log to show -- fall back to what make itself printed.
                print_output(result, args.tail)
        sys.stdout.flush()

    started = time.monotonic()
    JobRunner(maxj).run_jobs(jobs, on_done)
    elapsed = time.monotonic() - started

    # Summary table in list order, once everything has finished.
    failed = [n for n in names if not statuses[n][0].passed]
    print(f"\n{RULE}")
    print(f"Regression {args.top_list}: {len(names)} run(s), {len(names) - len(failed)} passed, "
          f"{len(failed)} failed, {elapsed:.1f}s")
    print(THIN)
    width = max(len(n) for n in names)
    for name in names:
        status, result, log = statuses[name]
        line = f"{status.verdict}  {name:<{width}}  {result.seconds:7.1f}s  {status.reason}{seed_tag(status)}"
        if not status.passed and status.last_error:
            line += f"\n      last: {status.last_error}"
        print(line)
    print(RULE)

    # -exer: one block per failed run, read back from its own log so it also
    # picks up a reason the log only got at the end (e.g. the TIMEOUT marker).
    if args.exer:
        if failed:
            print(f"\nExtracted errors (-exer): {len(failed)} failed run(s)")
            print(RULE)
            for name in failed:
                status, result, log = statuses[name]
                test = test_name(cmdsj[name]["cmd"])
                print(f"TestName: {name}" + (f" ({test})" if test else ""))
                print(f"ErrorMsg: {extract_error(log, status.reason)}")
                print(f"Seed    : {status.seed or 'not recorded (no ODVE_SEED marker in the log)'}")
                print(f"Cmd     : {result.command}")
                print(f"Repro   : {repro_cmd(result, status)}")
                print(f"Log     : {log}")
                print(THIN)
        else:
            print("-exer: every run passed, no errors to extract.")

    if args.cov or args.ccov:
        coverage_report(args, names, cmdsj)

    if failed:
        print("One or more regression runs failed: " + ", ".join(failed))
        exit(1)


def coverage_report(args, names, cmdsj):
    """After the runs: merge the dumps (and the Verilator coverage.dat files)
    into cov/ and print one line. Coverage trouble never changes the exit
    code - the tests decide that - but it is said out loud."""
    covgen = os.path.join(odve, "script", "cov", "covgen.py")
    out = os.path.join(cwd, "cov")
    run_dirs = [os.path.join(cwd, list2json.run_dir(n, cmdsj[n]["cmd"])) for n in names]
    print(f"\n{RULE}")
    if args.cov:
        covmap = os.path.join(cwd, "build", "cov", "covmap.json")
        dbfile = os.path.join(out, "cov.db.json")
        os.makedirs(out, exist_ok=True)
        r = subprocess.run([sys.executable, covgen, "merge", covmap] + run_dirs + ["-o", dbfile],
                           capture_output=True, text=True)
        for line in (r.stdout + r.stderr).splitlines():
            if "skipped" in line:
                print(line)
        if not os.path.isfile(dbfile):
            print("coverage: merge failed:\n" + (r.stdout + r.stderr).strip())
            return
        cmd = [sys.executable, covgen, "report", dbfile, "-o", out, "-q"]
        if args.ccov:
            dats = [d for d in run_dirs if os.path.isfile(os.path.join(d, "coverage.dat"))]
            if dats:
                cmd += ["--code-cov"] + dats
        r = subprocess.run(cmd, capture_output=True, text=True)
        for line in (r.stdout + r.stderr).splitlines():
            if line.startswith("[ODVE_COV]") or "code coverage" in line:
                print(line)
        try:
            d = json.load(open(dbfile))
            print(f"functional cov: {100.0 * d['covered'] / d['n'] if d['n'] else 0.0:.1f}% "
                  f"({d['covered']}/{d['n']} bins" + (f", {len(d['skipped'])} covergroup(s) skipped" if d['skipped'] else "")
                  + f") -> {out}/index.html")
        except (OSError, ValueError, KeyError):
            print("coverage: report failed:\n" + (r.stdout + r.stderr).strip())
    elif args.ccov:
        dats = [d for d in run_dirs if os.path.isfile(os.path.join(d, "coverage.dat"))]
        if not dats:
            print("code coverage: no coverage.dat in any run dir (Verilator writes one with CCOV=1; ModelSim Starter cannot)")
            return
        r = subprocess.run([sys.executable, covgen, "codecov"] + dats + ["-o", out], capture_output=True, text=True)
        text = (r.stdout + r.stderr).strip()
        print(text.splitlines()[-1] if text else "code coverage: no output")


if __name__ == "__main__":
    main()
