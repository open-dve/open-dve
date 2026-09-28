"""Run dumps -> merged coverage database (doc/fcov-plan.md 4.2, 4.3, 5.4).

A run's dump is `cov.dump` (written at `final`) or, when the run was killed
before that, the newest complete checkpoint `cov.dump.0/1`. merge() sums the
counts over runs, keeps which tests hit which bin, and judges "covered" with
each bin's at_least. The result (`odve-covdb 2`) is plain JSON-able dicts."""
import os

# cross bin kinds, as covlib.gen writes them into covmap.json
X_BIN, X_IGNORE, X_ILLEGAL = 0, 1, 2


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
                if kind == X_BIN:
                    table[x["base"] + i] = {"group": g["name"], "point": x["name"], "bin": b,
                                            "cross": True, "at_least": x["at_least"]}
    return table


def merge(covmap, dump_args):
    """Merge the dumps named by `dump_args` (run dirs or files) against the
    covmap. Returns (db, messages, ok): messages are one line per dump,
    ok is False when any dump was skipped."""
    table = bin_table(covmap)
    counts = {i: 0 for i in table}
    tests_per_bin = {i: set() for i in table}
    runs, messages, ok = [], [], True
    for arg in dump_args:
        path, parsed, kind = resolve_dump(arg)
        if parsed is None:
            messages.append(f"{arg}: {kind} - skipped")
            ok = False
            continue
        hdr, cnts, _ = parsed
        if hdr.get("hash") != covmap["hash"]:
            messages.append(f"{path}: model hash {hdr.get('hash')} != map {covmap['hash']} - skipped "
                            "(dump made with another version of the covergroups)")
            ok = False
            continue
        run = os.path.basename(os.path.dirname(os.path.abspath(path)))
        test = hdr.get("test") or run
        hits = 0
        for idx, c in cnts.items():
            if idx in table:
                counts[idx] += c
                tests_per_bin[idx].add(test)
                hits += 1
        runs.append({"test": test, "run": run, "dump": path, "kind": kind,
                     "samples": int(hdr.get("samples", 0)), "bins_hit": hits})
        messages.append(f"{path}: {kind}, test {test}, {hits} bins hit")

    bins = []
    for idx in sorted(table):
        b = dict(table[idx])
        b.update({"idx": idx, "count": counts[idx], "tests": sorted(tests_per_bin[idx]),
                  "covered": counts[idx] >= b["at_least"]})
        bins.append(b)
    covered = sum(1 for b in bins if b["covered"])
    db = {"format": "odve-covdb 2", "model": covmap["model"], "hash": covmap["hash"],
          "n": len(bins), "covered": covered, "runs": runs, "bins": bins,
          "skipped": [g["name"] for g in covmap["groups"] if g.get("unsupported")], "map": covmap}
    return db, messages, ok


def pct(hit, total):
    return 100.0 * hit / total if total else 0.0


def summarize(db):
    """{group: {point-or-cross: {"cross", "total", "hit", "bins": [...]}}} in
    the flat order of the bins."""
    out = {}
    for b in db["bins"]:
        g = out.setdefault(b["group"], {})
        p = g.setdefault(b["point"], {"cross": b["cross"], "total": 0, "hit": 0, "bins": []})
        p["total"] += 1
        p["hit"] += 1 if b["covered"] else 0
        p["bins"].append(b)
    return out
