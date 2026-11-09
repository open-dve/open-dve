"""Questions asked of a merged database (doc/fcov-plan.md 5.4): the holes,
what each test contributes, and the smallest set of tests that keeps the
current coverage."""


def holes(db):
    """Uncovered bins as (group, point, bin, count, at_least), flat order."""
    return [(b["group"], b["point"], b["bin"], b["count"], b["at_least"])
            for b in db["bins"] if not b["covered"]]


def per_test(db):
    """{test: {"bins": bins it hit, "unique": bins only it hit}}."""
    out = {}
    for b in db["bins"]:
        for t in b["tests"]:
            d = out.setdefault(t, {"bins": 0, "unique": 0})
            d["bins"] += 1
            if len(b["tests"]) == 1:
                d["unique"] += 1
    return out


def min_tests(db):
    """Greedy set cover: the tests to keep so that every bin any test hit is
    still hit. Returns the list in pick order (largest contribution first)
    and the tests that add nothing."""
    remaining = {b["idx"] for b in db["bins"] if b["tests"]}
    hits = {}
    for b in db["bins"]:
        for t in b["tests"]:
            hits.setdefault(t, set()).add(b["idx"])
    picked = []
    while remaining:
        best = max(hits, key=lambda t: (len(hits[t] & remaining), t))
        gain = hits[best] & remaining
        if not gain:
            break
        picked.append((best, len(gain)))
        remaining -= gain
    kept = {t for t, _ in picked}
    return picked, sorted(t for t in hits if t not in kept)


def text(db, what):
    """Human-readable answer for `what` in holes | tests | min."""
    lines = []
    if what == "holes":
        h = holes(db)
        lines.append(f"{len(h)} uncovered bin(s) of {db['n']}:")
        for g, p, b, c, al in h:
            need = f" ({c}/{al})" if al > 1 else ""
            lines.append(f"  {g}.{p}.{b}{need}")
    elif what == "tests":
        lines.append("test: bins hit / bins only this test hit")
        for t, d in sorted(per_test(db).items()):
            lines.append(f"  {t}: {d['bins']} / {d['unique']}")
    elif what == "min":
        picked, dropped = min_tests(db)
        lines.append(f"minimal test set keeping every hit bin ({len(picked)} of {len(picked) + len(dropped)} tests):")
        for t, gain in picked:
            lines.append(f"  keep {t}  (+{gain} bins)")
        for t in dropped:
            lines.append(f"  drop {t}  (adds no bin)")
    else:
        raise ValueError(what)
    return "\n".join(lines)
