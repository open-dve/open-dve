"""Reports from a merged database (doc/fcov-plan.md 6): cov.txt, a single-file
cov.html (summary, every group / point / cross with its bins and the tests
that hit them, the holes, per-test contribution, runs), cov.yaml in the
PyUCIS YAML form, and index.html tying functional and code coverage
together. Standard library only."""
import html
import os

from .analyze import holes, min_tests, per_test
from .db import pct, summarize

_CSS = """body{font:14px system-ui,sans-serif;margin:24px;max-width:1200px} table{border-collapse:collapse;margin:8px 0 16px}
td,th{border:1px solid #ccc;padding:3px 8px;text-align:left;vertical-align:top} .n{text-align:right}
.bar{display:inline-block;width:100px;height:10px;background:#d33;vertical-align:middle} .bar i{display:block;height:10px;background:#3a3}
tr.miss td{background:#fde8e8} tr.hit td.c{background:#e6f4e6} h2{margin-top:32px} h3{margin:16px 0 4px}
.warn{background:#fff3cd;padding:8px;border:1px solid #e0c060} .muted{color:#666} code{background:#f3f3f3;padding:0 3px}
nav a{margin-right:14px}"""


def bar(h, t):
    p = pct(h, t)
    return f"<span class='bar'><i style='width:{p:.0f}px'></i></span> {p:.1f}% ({h}/{t})"


# ------------------------------------------------------------------ text

def write_txt(db, path):
    s = summarize(db)
    with open(path, "w", encoding="utf-8") as f:
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


# ------------------------------------------------------------------ html

def write_html(db, path, code=None):
    """The functional-coverage report. `code` is the summary write_html of
    covlib.lcov returned, or None."""
    e = html.escape
    s = summarize(db)
    out = [f"<!doctype html><meta charset='utf-8'><title>{e(db['model'])} coverage</title><style>{_CSS}</style>",
           f"<h1>{e(db['model'])}: functional coverage {bar(db['covered'], db['n'])}</h1>",
           "<nav><a href='#groups'>groups</a><a href='#holes'>holes</a><a href='#tests'>tests</a>"
           "<a href='#runs'>runs</a>" + ("<a href='code/index.html'>code coverage</a>" if code else "") + "</nav>",
           f"<p class='muted'>model hash {e(db['hash'])}; a bin is covered when its hits reach its at_least.</p>"]
    if db.get("skipped"):
        out.append(f"<p class='warn'>Skipped covergroups (outside the supported subset - <b>no coverage collected</b> for them): "
                   f"{e(', '.join(db['skipped']))}. See the scan warnings / covmap.json.</p>")

    # summary table
    out.append("<h2 id='groups'>Groups</h2><table><tr><th>group</th><th>point / cross</th><th>coverage</th></tr>")
    for g, pts in s.items():
        gh = sum(d["hit"] for d in pts.values())
        gt = sum(d["total"] for d in pts.values())
        out.append(f"<tr><td><b><a href='#g-{e(g)}'>{e(g)}</a></b></td><td></td><td>{bar(gh, gt)}</td></tr>")
        for p, d in pts.items():
            out.append(f"<tr><td></td><td><a href='#p-{e(g)}-{e(p)}'>{e(p)}</a>{' <span class=muted>(cross)</span>' if d['cross'] else ''}</td>"
                       f"<td>{bar(d['hit'], d['total'])}</td></tr>")
    out.append("</table>")

    # per group detail, with source
    ginfo = {g["name"]: g for g in db["map"]["groups"]}
    for g, pts in s.items():
        meta = ginfo.get(g, {})
        out.append(f"<h2 id='g-{e(g)}'>{e(g)} <span class='muted'>{e(os.path.basename(meta.get('file', '')))}:{meta.get('line', '')}</span></h2>")
        if meta.get("text"):
            out.append(f"<details><summary>covergroup source</summary><pre>{e(meta['text'])}</pre></details>")
        for p, d in pts.items():
            out.append(f"<h3 id='p-{e(g)}-{e(p)}'>{'cross ' if d['cross'] else 'coverpoint '}{e(p)}: {bar(d['hit'], d['total'])}</h3>")
            out.append("<table><tr><th>bin</th><th>hits</th><th>at_least</th><th>tests</th></tr>")
            for b in d["bins"]:
                cls = "hit" if b["covered"] else "miss"
                out.append(f"<tr class='{cls}'><td>{e(b['bin'])}</td><td class='n c'>{b['count']}</td>"
                           f"<td class='n'>{b['at_least']}</td><td>{e(', '.join(b['tests'])) or '&mdash;'}</td></tr>")
            out.append("</table>")

    # holes
    h = holes(db)
    out.append(f"<h2 id='holes'>Holes: {len(h)} uncovered bin(s)</h2>")
    if h:
        out.append("<table><tr><th>group</th><th>point / cross</th><th>bin</th><th>hits / at_least</th></tr>")
        out += [f"<tr class='miss'><td>{e(g)}</td><td>{e(p)}</td><td>{e(b)}</td><td class='n'>{c} / {al}</td></tr>"
                for g, p, b, c, al in h]
        out.append("</table>")
    else:
        out.append("<p>none - every bin covered.</p>")

    # tests
    pt = per_test(db)
    picked, dropped = min_tests(db)
    out.append("<h2 id='tests'>Tests</h2><table><tr><th>test</th><th>bins hit</th><th>bins only this test hit</th></tr>")
    out += [f"<tr><td>{e(t)}</td><td class='n'>{v['bins']}</td><td class='n'>{v['unique']}</td></tr>"
            for t, v in sorted(pt.items())]
    out.append("</table>")
    if picked:
        out.append("<p>Smallest set keeping every hit bin (greedy): " +
                   ", ".join(f"<b>{e(t)}</b> (+{n})" for t, n in picked) +
                   (f"; adds nothing: {e(', '.join(dropped))}" if dropped else "") + ".</p>")

    # runs
    out.append("<h2 id='runs'>Runs</h2><table><tr><th>test</th><th>run</th><th>dump</th><th>samples</th><th>bins hit</th></tr>")
    for r in db["runs"]:
        kind = r["kind"] if r["kind"] == "final" else f"<b>{e(r['kind'])}</b> (killed before final)"
        out.append(f"<tr><td>{e(r['test'])}</td><td>{e(r['run'])}</td><td>{kind}</td>"
                   f"<td class='n'>{r['samples']}</td><td class='n'>{r['bins_hit']}</td></tr>")
    out.append("</table>")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out))


def write_index(path, db, code=None):
    e = html.escape
    parts = [f"<!doctype html><meta charset='utf-8'><title>{e(db['model'])} coverage</title><style>{_CSS}</style>",
             f"<h1>{e(db['model'])} coverage</h1>",
             f"<p><a href='cov.html'>Functional coverage</a>: {bar(db['covered'], db['n'])} bins"
             + (f" &nbsp;<span class='warn'>{len(db['skipped'])} covergroup(s) skipped</span>" if db.get("skipped") else "") + "</p>"]
    if code:
        t = code["total"]
        parts.append(f"<p><a href='code/index.html'>Code coverage</a>: lines {bar(t['lh'], t['lf'])}, "
                     f"branches {bar(t['bh'], t['bf'])}, {len(code['files'])} file(s)</p>")
    else:
        parts.append("<p class='muted'>Code coverage: not collected (CCOV=1 on Verilator writes coverage.dat per run; "
                     "ModelSim Starter has no code coverage licence).</p>")
    parts.append(f"<p class='muted'>runs: {e(', '.join(r['test'] for r in db['runs']))}; also: cov.txt, cov.json, cov.yaml, cov.xml (UCIS)</p>")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(parts))


# ----------------------------------------------------------- pyucis yaml

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
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
