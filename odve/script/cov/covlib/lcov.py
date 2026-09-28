"""Code coverage from lcov `.info` files (what `verilator_coverage
--write-info` writes): parse, merge and render as HTML - no genhtml, no
Perl. Only the records the tool produces are handled: SF (source file),
DA (line, hits), BRDA (line, block, branch, hits), end_of_record."""
import html
import os
import re

from .db import pct


def parse_info(path, into=None):
    """{file: {"lines": {line: hits}, "branches": {(line, block, name): hits}}},
    summed into `into` when given (merging runs)."""
    data = {} if into is None else into
    cur = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if line.startswith("SF:"):
                cur = data.setdefault(line[3:], {"lines": {}, "branches": {}})
            elif line.startswith("DA:") and cur is not None:
                ln, hits = line[3:].split(",")[:2]
                cur["lines"][int(ln)] = cur["lines"].get(int(ln), 0) + int(hits)
            elif line.startswith("BRDA:") and cur is not None:
                parts = line[5:].split(",")
                ln, block, hits = int(parts[0]), parts[1], parts[-1]
                name = ",".join(parts[2:-1])
                key = (ln, block, name)
                cur["branches"][key] = cur["branches"].get(key, 0) + (0 if hits == "-" else int(hits))
            elif line == "end_of_record":
                cur = None
    return data


def merge_infos(paths):
    data = {}
    for p in paths:
        parse_info(p, data)
    return data


def summary(data, exclude=None):
    """{file: {"lh", "lf", "bh", "bf"}} (lines/branches hit and found), files
    matching `exclude` (regex) left out."""
    rx = re.compile(exclude) if exclude else None
    out = {}
    for f, d in sorted(data.items()):
        if rx and rx.search(f):
            continue
        out[f] = {"lh": sum(1 for h in d["lines"].values() if h > 0), "lf": len(d["lines"]),
                  "bh": sum(1 for h in d["branches"].values() if h > 0), "bf": len(d["branches"])}
    return out


def totals(summ):
    t = {"lh": 0, "lf": 0, "bh": 0, "bf": 0}
    for d in summ.values():
        for k in t:
            t[k] += d[k]
    return t


_CSS = """body{font:14px system-ui,sans-serif;margin:24px} table{border-collapse:collapse}
td,th{border:1px solid #ccc;padding:3px 8px;text-align:left} .n{text-align:right}
.bar{display:inline-block;height:10px;background:#d33} .bar i{display:block;height:10px;background:#3a3}
pre{font:12px/1.4 ui-monospace,monospace;margin:0} .src td{border:none;padding:0 8px;white-space:pre}
.hit{background:#e6f4e6} .miss{background:#fde8e8} .ln{color:#888;text-align:right;user-select:none}
.br{color:#a60;font-size:11px}"""


def _bar(h, t):
    p = pct(h, t)
    return f"<span class='bar' style='width:100px'><i style='width:{p:.0f}px'></i></span> {p:.1f}% ({h}/{t})"


def write_html(data, out_dir, exclude=None, title="code coverage"):
    """index.html + one page per file into out_dir. Returns the summary."""
    os.makedirs(out_dir, exist_ok=True)
    summ = summary(data, exclude)
    tot = totals(summ)
    e = html.escape
    rows = []
    for i, (f, d) in enumerate(summ.items()):
        page = f"file{i}.html"
        rows.append(f"<tr><td><a href='{page}'>{e(f)}</a></td><td>{_bar(d['lh'], d['lf'])}</td>"
                    f"<td>{_bar(d['bh'], d['bf'])}</td></tr>")
        _write_file_page(os.path.join(out_dir, page), f, data[f], d)
    with open(os.path.join(out_dir, "index.html"), "w", encoding="utf-8") as fh:
        fh.write(f"<!doctype html><meta charset='utf-8'><title>{e(title)}</title><style>{_CSS}</style>"
                 f"<h1>{e(title)}</h1><p>lines {_bar(tot['lh'], tot['lf'])} &nbsp; branches {_bar(tot['bh'], tot['bf'])}</p>"
                 f"<table><tr><th>file</th><th>lines</th><th>branches</th></tr>{''.join(rows)}</table>"
                 + (f"<p>excluded: <code>{e(exclude)}</code></p>" if exclude else ""))
    return {"files": summ, "total": tot}


def _write_file_page(path, src, d, s):
    e = html.escape
    try:
        with open(src, encoding="utf-8", errors="replace") as f:
            lines = f.read().split("\n")
    except OSError:
        lines = None
    br_by_line = {}
    for (ln, _blk, name), hits in d["branches"].items():
        br_by_line.setdefault(ln, []).append((name, hits))
    rows = []
    if lines is None:
        rows.append("<tr><td colspan=3>source not readable here; line hits only</td></tr>")
        for ln in sorted(d["lines"]):
            cls = "hit" if d["lines"][ln] > 0 else "miss"
            rows.append(f"<tr class='{cls}'><td class='ln'>{ln}</td><td class='n'>{d['lines'][ln]}</td><td></td></tr>")
    else:
        for i, text in enumerate(lines, 1):
            hits = d["lines"].get(i)
            cls = "" if hits is None else ("hit" if hits > 0 else "miss")
            brs = "".join(f"<div class='br'>{'✓' if h > 0 else '✗'} {e(n)}</div>" for n, h in br_by_line.get(i, []))
            rows.append(f"<tr class='{cls}'><td class='ln'>{i}</td><td class='n'>{'' if hits is None else hits}</td>"
                        f"<td>{e(text)}{brs}</td></tr>")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(f"<!doctype html><meta charset='utf-8'><title>{e(src)}</title><style>{_CSS}</style>"
                 f"<p><a href='index.html'>&larr; index</a></p><h2>{e(src)}</h2>"
                 f"<p>lines {_bar(s['lh'], s['lf'])} &nbsp; branches {_bar(s['bh'], s['bf'])}</p>"
                 f"<table class='src'>{''.join(rows)}</table>")
