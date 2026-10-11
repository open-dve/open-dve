#!/usr/bin/env python3
"""Find random-number calls that bypass odve_rand_pkg.

$urandom, $urandom_range, $random, srandom() and randomize() use each
simulator's own generator, so the same seed gives different values on
Verilator and Questa/ModelSim; a bare $dist_* call is evaluated more or less
than once by Verilator in some expressions. Every value should come from an
odve_rand stream (comp/common/rand/README). This scans SystemVerilog sources,
comments and strings excluded, and lists every such call.

    rand_check.py <file or directory> ...    # exit 1 if anything is found

Directories are searched for *.sv, *.svh, *.v, *.vh. odve_rand_pkg.sv itself
is skipped. A line may carry a waiver comment, for a call whose value does
not affect stimulus or checking:

    seed = $urandom;   // odve_rand: ok - <why>
"""
import argparse
import os
import re
import sys

EXTS = (".sv", ".svh", ".v", ".vh")
SKIP = {"odve_rand_pkg.sv"}
CALL = re.compile(
    r"(\$urandom_range|\$urandom|\$random|\$dist_\w+"
    r"|\bstd\s*::\s*randomize|\brandomize\s*\(|\bsrandom\s*\(|\b[gs]et_randstate\s*\()")
WAIVER = re.compile(r"//\s*odve_rand:\s*ok\b")


def strip(text):
    """Comments and string literals blanked out, line breaks kept, so line
    numbers stay right. Returns the stripped text and the comment text per
    line (where a waiver is looked for)."""
    out, notes = [], {}
    i, n, line = 0, len(text), 1
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            notes[line] = notes.get(line, "") + text[i:j]
            out.append(" " * (j - i))
            i = j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            chunk = text[i:j]
            out.append("".join("\n" if ch == "\n" else " " for ch in chunk))
            line += chunk.count("\n")
            i = j
        elif c == '"':
            j = i + 1
            while j < n and text[j] != '"' and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            j = min(j + 1, n)
            out.append(" " * (j - i))
            i = j
        else:
            if c == "\n":
                line += 1
            out.append(c)
            i += 1
    return "".join(out), notes


def scan(path):
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError as e:
        print(f"rand_check: {path}: {e}", file=sys.stderr)
        return []
    code, notes = strip(text)
    raw = text.split("\n")
    hits = []
    for no, ln in enumerate(code.split("\n"), 1):
        for m in CALL.finditer(ln):
            if WAIVER.search(notes.get(no, "")):
                continue
            hits.append((path, no, m.group(1).replace(" ", ""), raw[no - 1].strip()))
    return hits


def files(args):
    for a in args:
        if os.path.isdir(a):
            for root, dirs, names in os.walk(a):
                dirs.sort()
                for f in sorted(names):
                    if f.endswith(EXTS) and f not in SKIP:
                        yield os.path.join(root, f)
        elif os.path.basename(a) not in SKIP:
            yield a


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+", help="SystemVerilog files or directories")
    ap.add_argument("-q", "--quiet", action="store_true", help="print only the summary line")
    a = ap.parse_args()
    hits, nfiles = [], 0
    for f in files(a.paths):
        nfiles += 1
        hits += scan(f)
    if not a.quiet:
        for path, no, what, src in hits:
            print(f"{path}:{no}: {what}: {src}")
    print(f"rand_check: {len(hits)} call(s) outside odve_rand in {nfiles} file(s)")
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())
