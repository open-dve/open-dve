"""unittest for the post-simulation side: covlib.db, lcov, ucisxml, analyze, report."""
import json
import os
import tempfile
import unittest
import xml.etree.ElementTree as ET

from covlib import analyze, db, lcov, report, ucisxml

COVMAP = {
    "format": "odve-covmap 2", "model": "m", "hash": "h1", "n": 7,
    "groups": [
        {"name": "g", "file": "t.sv", "line": 3, "text": "covergroup g ... endgroup", "weight": 1, "unsupported": None,
         "points": [{"name": "p", "arg": "a", "base": 0, "at_least": 1, "iff": None,
                     "bins": ["b0", "b1"], "ignore": ["ig"], "illegal": []},
                    {"name": "q", "arg": "b", "base": 2, "at_least": 2, "iff": None,
                     "bins": ["c0"], "ignore": [], "illegal": ["bad"]}],
         "crosses": [{"name": "x", "base": 3, "points": ["p", "q"], "at_least": 1,
                      "bins": ["b0,c0", "b1,c0"], "kinds": [0, 1]}]},   # b1,c0 ignored
        {"name": "skipped_g", "file": "t.sv", "line": 30, "text": "", "weight": 1,
         "unsupported": "clocking event", "points": [], "crosses": []},
    ],
    "created": ["g"], "sampled": ["g"], "warnings": [],
}


def dump(path, test, counts, tag="final", hsh="h1", samples=10):
    with open(path, "w") as f:
        f.write(f"# odve-cov 1\n# model m hash {hsh}\n# test {test} covcnt 32 n 7\n# samples {samples}\n")
        for i, c in counts.items():
            f.write(f"{i} {c}\n")
        f.write(f"# end {tag}\n")


class TestDb(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.TemporaryDirectory()
        self.root = self.d.name

    def tearDown(self):
        self.d.cleanup()

    def run_dir(self, name):
        p = os.path.join(self.root, name)
        os.makedirs(p, exist_ok=True)
        return p

    def test_bin_table_excludes_ignored_cross(self):
        t = db.bin_table(COVMAP)
        self.assertEqual(sorted(t), [0, 1, 2, 3])
        self.assertTrue(t[3]["cross"])

    def test_merge_attribution_at_least_and_checkpoint(self):
        a = self.run_dir("t_a")
        dump(os.path.join(a, "cov.dump"), "test_a", {0: 1, 2: 1})
        b = self.run_dir("t_b")                       # killed: only checkpoints, newest wins
        dump(os.path.join(b, "cov.dump.0"), "test_b", {0: 1}, tag="4")
        dump(os.path.join(b, "cov.dump.1"), "test_b", {0: 1, 2: 1, 3: 1}, tag="5")
        c = self.run_dir("t_c")                       # truncated final, complete checkpoint
        with open(os.path.join(c, "cov.dump"), "w") as f:
            f.write("# odve-cov 1\n0 1\n")
        dump(os.path.join(c, "cov.dump.0"), "test_c", {1: 1}, tag="1")
        stale = self.run_dir("t_stale")
        dump(os.path.join(stale, "cov.dump"), "old", {0: 9}, hsh="h0")
        database, msgs, ok = db.merge(COVMAP, [a, b, c, stale, os.path.join(self.root, "nope")])
        self.assertFalse(ok)
        by = {x["idx"]: x for x in database["bins"]}
        self.assertEqual(by[0]["count"], 2)                # a + b's newest checkpoint; c has no bin 0
        self.assertEqual(by[0]["tests"], ["test_a", "test_b"])
        self.assertEqual(by[1]["tests"], ["test_c"])
        self.assertEqual(by[2]["count"], 2)
        self.assertTrue(by[2]["covered"])                  # at_least 2 reached
        self.assertEqual(by[3]["count"], 1)
        kinds = {r["run"]: r["kind"] for r in database["runs"]}
        self.assertEqual(kinds["t_b"], "checkpoint 5")
        self.assertEqual(kinds["t_c"], "checkpoint 1")
        self.assertNotIn("t_stale", kinds)
        self.assertTrue(any("hash" in m for m in msgs))
        self.assertEqual(database["skipped"], ["skipped_g"])
        self.assertEqual((database["covered"], database["n"]), (4, 4))
        self.database = database

    def test_reports_and_exports(self):
        a = self.run_dir("r1")
        dump(os.path.join(a, "cov.dump"), "t1", {0: 1, 2: 1})
        b = self.run_dir("r2")
        dump(os.path.join(b, "cov.dump"), "t2", {0: 1, 3: 1})
        database, _, _ = db.merge(COVMAP, [a, b])
        txt = os.path.join(self.root, "cov.txt")
        report.write_txt(database, txt)
        t = open(txt).read()
        self.assertIn("-- b1", t)                          # hole marked
        self.assertIn("skipped covergroups", t)
        html = os.path.join(self.root, "cov.html")
        report.write_html(database, html)
        h = open(html).read()
        self.assertIn("Holes: 2 uncovered", h)             # b1 and c0 (1 < at_least 2)
        self.assertIn("covergroup g ... endgroup", h)
        report.write_index(os.path.join(self.root, "index.html"), database)
        xml = os.path.join(self.root, "cov.xml")
        ucisxml.write(database, xml)
        root = ET.parse(xml).getroot()
        self.assertEqual(root.tag, "UCIS")
        self.assertEqual(len(root.findall("historyNodes")), 2)
        bins = {b.get("name"): b.find("range/contents").get("coverageCount")
                for b in root.iter("coverpointBin") if b.get("type") == "bins"}
        self.assertEqual(bins["b0"], "2")
        self.assertEqual(bins["c0"], "1")
        self.assertEqual([x.get("name") for x in root.iter("crossBin")], ["b0,c0"])
        yaml = os.path.join(self.root, "cov.yaml")
        report.write_pyucis_yaml(database, yaml)
        self.assertIn("coverpoints: [p, q]", open(yaml).read())

    def test_analyze(self):
        a = self.run_dir("r1")
        dump(os.path.join(a, "cov.dump"), "t1", {0: 1, 1: 1})
        b = self.run_dir("r2")
        dump(os.path.join(b, "cov.dump"), "t2", {0: 1})
        c = self.run_dir("r3")
        dump(os.path.join(c, "cov.dump"), "t3", {3: 1})
        database, _, _ = db.merge(COVMAP, [a, b, c])
        self.assertEqual([h[2] for h in analyze.holes(database)], ["c0"])
        pt = analyze.per_test(database)
        self.assertEqual(pt["t1"], {"bins": 2, "unique": 1})
        self.assertEqual(pt["t2"], {"bins": 1, "unique": 0})
        picked, dropped = analyze.min_tests(database)
        self.assertEqual([p[0] for p in picked], ["t1", "t3"])
        self.assertEqual(dropped, ["t2"])
        self.assertIn("drop t2", analyze.text(database, "min"))


class TestLcov(unittest.TestCase):
    def test_parse_merge_render(self):
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, "dut.sv")
            with open(src, "w") as f:
                f.write("module dut;\n  logic a;\n  always a = ~a;\nendmodule\n")
            info1 = os.path.join(d, "a.info")
            with open(info1, "w") as f:
                f.write(f"TN:x\nSF:{src}\nDA:2,1\nDA:3,0\nBRDA:3,0,if,0\nBRDA:3,0,else,1\nend_of_record\n"
                        f"SF:/x/uvm/uvm_pkg.sv\nDA:1,5\nend_of_record\n")
            info2 = os.path.join(d, "b.info")
            with open(info2, "w") as f:
                f.write(f"TN:y\nSF:{src}\nDA:2,2\nDA:3,4\nBRDA:3,0,if,2\nBRDA:3,0,else,-\nend_of_record\n")
            data = lcov.merge_infos([info1, info2])
            self.assertEqual(data[src]["lines"], {2: 3, 3: 4})
            self.assertEqual(data[src]["branches"][(3, "0", "if")], 2)
            self.assertEqual(data[src]["branches"][(3, "0", "else")], 1)
            summ = lcov.summary(data, exclude="/uvm/")
            self.assertEqual(list(summ), [src])
            self.assertEqual(summ[src], {"lh": 2, "lf": 2, "bh": 2, "bf": 2})
            out = os.path.join(d, "code")
            res = lcov.write_html(data, out, exclude="/uvm/")
            self.assertEqual(res["total"]["lf"], 2)
            self.assertTrue(os.path.isfile(os.path.join(out, "index.html")))
            page = open(os.path.join(out, "file0.html")).read()
            self.assertIn("always a = ~a;", page)
            self.assertIn("class='hit'", page)


if __name__ == "__main__":
    unittest.main()
