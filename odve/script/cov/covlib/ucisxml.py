"""UCIS XML interchange writer (Accellera UCIS 1.0) for a merged database.

Mirrors the element structure pyucis produces, so the file opens in the same
readers: one instanceCoverages per covergroup, a cgInstance with its
coverpoints (coverpointBin/range/contents) and crosses (crossBin/index/
contents), one historyNode per test run. Standard library only."""
import datetime
import os
import xml.etree.ElementTree as ET
from xml.dom import minidom

from .db import summarize


def _sub(parent, tag, **attrs):
    e = ET.SubElement(parent, tag)
    for k, v in attrs.items():
        e.set(k, str(v))
    return e


def build(db, written_by="odve covgen"):
    now = datetime.datetime.now().replace(microsecond=0).isoformat()
    root = ET.Element("UCIS")
    root.set("xmlns:ucis", "http://www.w3.org/2001/XMLSchema-instance")
    root.set("writtenBy", written_by)
    root.set("writtenTime", now)
    root.set("ucisVersion", "1.0")

    files = {}
    for g in db["map"]["groups"]:
        f = g.get("file") or "__null__file__"
        if f not in files:
            files[f] = len(files) + 1
            _sub(root, "sourceFiles", fileName=f, id=files[f])
    if not files:
        files["__null__file__"] = 1
        _sub(root, "sourceFiles", fileName="__null__file__", id=1)

    for i, run in enumerate(db["runs"]):
        _sub(root, "historyNodes", historyNodeId=i, logicalName=run["test"], physicalName=run["dump"],
             kind="test", testStatus="true", simtime="0", timeunit="0", runCwd=os.path.dirname(run["dump"]),
             cpuTime="0", seed="0", cmd="", args="", date=now, userName="", toolCategory="unknown",
             ucisVersion="1.0", vendorId="odve", vendorTool="covgen", vendorToolVersion="1")

    s = summarize(db)
    ginfo = {g["name"]: g for g in db["map"]["groups"]}
    for gi, (gname, pts) in enumerate(s.items()):
        g = ginfo[gname]
        fid = files.get(g.get("file") or "__null__file__", 1)
        inst = _sub(root, "instanceCoverages", name=gname, key=gi, instanceId=gi, moduleName=gname)
        _sub(inst, "id", file=fid, line=g.get("line", 1) or 1, inlineCount=1)
        cgc = _sub(inst, "covergroupCoverage")
        cgi = _sub(cgc, "cgInstance", name=f"{gname}_i", key=0)
        _sub(cgi, "options", weight=g.get("weight", 1), goal=100, at_least=1, per_instance="true",
             merge_instances="true")
        cgid = _sub(cgi, "cgId", cgName=gname, moduleName=gname)
        _sub(cgid, "cginstSourceId", file=fid, line=g.get("line", 1) or 1, inlineCount=1)
        _sub(cgid, "cgSourceId", file=fid, line=g.get("line", 1) or 1, inlineCount=1)
        pmeta = {p["name"]: p for p in g.get("points", [])}
        xmeta = {x["name"]: x for x in g.get("crosses", [])}
        for pi, (pname, d) in enumerate((n, d) for n, d in pts.items() if not d["cross"]):
            cp = _sub(cgi, "coverpoint", name=pname, key=pi)
            _sub(cp, "options", weight=1, goal=100, at_least=d["bins"][0]["at_least"], auto_bin_max=64,
                 detect_overlap="false")
            for bi, b in enumerate(d["bins"]):
                cb = _sub(cp, "coverpointBin", name=b["bin"], type="bins", key=bi)
                _sub(cb, "range", **{"from": -1, "to": -1})
                _sub(cb[-1], "contents", coverageCount=b["count"])
            meta = pmeta.get(pname, {})
            for kind, names in (("ignore", meta.get("ignore", [])), ("illegal", meta.get("illegal", []))):
                for name in names:
                    cb = _sub(cp, "coverpointBin", name=name, type=kind, key=len(cp) - 1)
                    _sub(cb, "range", **{"from": -1, "to": -1})
                    _sub(cb[-1], "contents", coverageCount=0)
        for xi, (xname, d) in enumerate((n, d) for n, d in pts.items() if d["cross"]):
            cr = _sub(cgi, "cross", name=xname, key=xi)
            _sub(cr, "options", weight=1, goal=100, at_least=d["bins"][0]["at_least"])
            members = xmeta.get(xname, {}).get("points", [])
            ce = _sub(cr, "crossExpr")
            ce.text = ", ".join(members)
            for bi, b in enumerate(d["bins"]):
                xb = _sub(cr, "crossBin", name=b["bin"], key=bi, type="default")
                for part in b["bin"].split(","):
                    ix = _sub(xb, "index")
                    ix.text = part
                _sub(xb, "contents", coverageCount=b["count"])
    return root


def write(db, path):
    root = build(db)
    pretty = minidom.parseString(ET.tostring(root, encoding="unicode")).toprettyxml(indent="  ")
    with open(path, "w", encoding="utf-8") as f:
        f.write(pretty)
