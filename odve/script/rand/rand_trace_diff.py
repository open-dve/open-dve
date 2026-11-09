#!/usr/bin/env python3
"""Compare the odve_rand draw traces of two runs (+ODVE_RAND_TRACE).

Each trace line is "<time> <stream> <value>". Streams are compared one by
one, so draws of different streams in one time step may come in any order.
For every stream that differs the first differing draw is reported: by value
(the stimulus itself differs: a stream was drawn more or fewer times, or by
another code path) or only by time (the same values, drawn at another time: a
same-time-step race in the testbench, e.g. a process woken at a clock edge
that reads what another process at that edge updates). The earliest
difference is usually the cause, the later ones its consequences.

    rand_trace_diff.py <run A>/odve_rand_trace.txt <run B>/odve_rand_trace.txt [-n N]

Exit 0 when every stream has the same values at the same times, 1 otherwise.
"""
import argparse
import collections
import sys


def load(path):
    streams = collections.OrderedDict()
    with open(path, errors="replace") as f:
        for ln in f:
            p = ln.split()
            if len(p) != 3:
                continue
            streams.setdefault(p[1], []).append((int(p[0]), int(p[2])))
    return streams


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("-n", type=int, default=10, help="differences to list (default 10, earliest first)")
    args = ap.parse_args()
    a, b = load(args.a), load(args.b)
    diffs = []
    for name in sorted(set(a) | set(b)):
        x, y = a.get(name, []), b.get(name, [])
        for i, (u, v) in enumerate(zip(x, y)):
            if u[1] != v[1]:
                diffs.append((min(u[0], v[0]), name, i, "value", u, v))
                break
            if u[0] != v[0]:
                diffs.append((min(u[0], v[0]), name, i, "time", u, v))
                break
        else:
            if len(x) != len(y):
                i = min(len(x), len(y))
                u = x[i] if i < len(x) else None
                v = y[i] if i < len(y) else None
                diffs.append(((u or v)[0], name, i, "count", u, v))
    print(f"rand_trace_diff: {len(set(a) | set(b))} streams, {len(diffs)} differ "
          f"({sum(len(s) for s in a.values())} / {sum(len(s) for s in b.values())} draws)")
    for t, name, i, kind, u, v in sorted(diffs)[:args.n]:
        fa = f"t={u[0]} v={u[1]}" if u else "no draw"
        fb = f"t={v[0]} v={v[1]}" if v else "no draw"
        print(f"  {kind:5} {name} draw {i}: A {fa} | B {fb}")
    return 1 if diffs else 0


if __name__ == "__main__":
    sys.exit(main())
