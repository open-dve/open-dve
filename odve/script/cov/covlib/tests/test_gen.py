"""unittest for covlib.gen."""
import json
import os
import tempfile
import textwrap
import unittest

from covlib import gen
from covlib.cgparse import parse_file
from covlib.model import Model


def model_from(sv, created=None):
    text = "`ifdef ODVE_COV_NATIVE\n" + textwrap.dedent(sv) + "\n`endif\n"
    groups, _, _ = parse_file("t.sv", text)
    m = Model(groups=groups)
    m.created = created if created is not None else [g.name for g in groups]
    m.sampled = list(m.created)
    return m


SV = """
    covergroup apb_cg with function sample(int len, bit dir);
      cp_len: coverpoint len { bins one = {1}; bins some = {[2:4], 6}; bins big[] = {8, 16};
                               bins up = (1 => 2); wildcard bins w = {8'b1???_0000};
                               bins rest = default;
                               ignore_bins zero = {0}; illegal_bins bad = {[256:$]}; }
      cp_dir: coverpoint dir iff (len);
      x_len_dir: cross cp_len, cp_dir { ignore_bins ig = binsof(cp_len.one) && binsof(cp_dir.auto[1]);
                                        illegal_bins il = binsof(cp_len.rest); }
    endgroup
"""


class TestLayout(unittest.TestCase):
    def setUp(self):
        self.m = model_from(SV)
        self.g = self.m.groups[0]
        self.assertIsNone(self.g.unsupported, self.g.unsupported)
        self.lay, self.n = gen.layout(self.m)

    def test_bases_and_total(self):
        lay = self.lay[self.g.name]
        # cp_len coverage bins: one some big[8] big[16] up w rest = 7; cp_dir 2; cross 14
        self.assertEqual(lay["points"], [0, 7])
        self.assertEqual(lay["crosses"][0][0], 9)
        self.assertEqual(self.n, 23)

    def test_cross_kinds(self):
        names_kinds = self.lay[self.g.name]["crosses"][0][1]
        d = dict(names_kinds)
        self.assertEqual(d["one,auto[1]"], gen.X_IGNORE)
        self.assertEqual(d["one,auto[0]"], gen.X_BIN)
        self.assertEqual(d["rest,auto[0]"], gen.X_ILLEGAL)
        self.assertEqual(d["rest,auto[1]"], gen.X_ILLEGAL)

    def test_point_tables(self):
        rows, trs = gen.point_tables(self.g.point("cp_len"))
        # (lo, hi, kind, bidx): one=0 some=1 (two rows) big[8]=2 big[16]=3 up=4 w=5 rest=6
        self.assertIn((1, 1, gen.K_BIN, 0), rows)
        self.assertIn((2, 4, gen.K_BIN, 1), rows)
        self.assertIn((6, 6, gen.K_BIN, 1), rows)
        self.assertIn((16, 16, gen.K_BIN, 3), rows)
        wild = [r for r in rows if r[2] == gen.K_BIN_WILD][0]
        self.assertEqual(wild[0], 0b10000000)
        self.assertEqual(wild[1] & 0xFF, 0b10001111)
        self.assertEqual(wild[3], 5)
        self.assertIn((0, 0, gen.K_DEFAULT, 6), rows)
        self.assertIn((0, 0, gen.K_IGNORE, -1), rows)
        self.assertIn((256, 2 ** 31 - 1, gen.K_ILLEGAL, -1), rows)
        self.assertEqual(trs, [([1, 2], 4)])


class TestEmit(unittest.TestCase):
    def test_generate_files(self):
        m = model_from(SV + """
            covergroup weird @(posedge clk);
              cp: coverpoint x;
            endgroup
        """, created=["apb_cg", "weird", "ghost"])
        with tempfile.TemporaryDirectory() as d:
            summary, warnings = gen.generate(m, d, "apb")
            self.assertEqual(summary["groups"], ["apb_cg"])
            self.assertEqual(sorted(summary["stubs"]), ["ghost", "weird"])
            self.assertTrue(any("ghost" in w and "stub" in w for w in warnings))
            self.assertTrue(any("weird" in w and "skipped" in w for w in warnings))
            svh = open(os.path.join(d, "odve_cov_gen.svh")).read()
            self.assertIn("`define ODVE_COV_N     23", svh)
            self.assertIn('`define ODVE_COV_MODEL "apb"', svh)
            cls = open(os.path.join(d, "odve_cov_gen_classes.svh")).read()
            self.assertIn("class odve_cov_apb_cg extends odve_cov_group;", cls)
            self.assertIn("function void sample(longint len, longint dir,", cls)
            self.assertIn("longint a3 = NA", cls)
            self.assertIn("check_spare(a3, 3);", cls)
            self.assertIn("if (!((len != 0))) begin", cls.replace("if ((len != 0)) begin", "if (!((len != 0))) begin"))  # iff emitted
            self.assertIn("find_trans(len, p0_hist", cls)
            self.assertIn("p0_hist   = new[2];", cls)
            self.assertIn("xi = (b0) * 2 + b1;", cls)
            self.assertIn("class odve_cov_weird extends odve_cov_group;", cls)
            self.assertIn("class odve_cov_ghost extends odve_cov_group;", cls)
            self.assertIn("STUB", cls)
            cm = json.load(open(os.path.join(d, "covmap.json")))
            self.assertEqual(cm["n"], 23)
            self.assertEqual(cm["hash"], summary["hash"])
            apb = cm["groups"][0]
            self.assertEqual(apb["points"][0]["bins"][:2], ["one", "some"])
            self.assertEqual(apb["points"][0]["ignore"], ["zero"])
            self.assertEqual(apb["crosses"][0]["kinds"].count(gen.X_ILLEGAL), 2)
            self.assertIsNotNone(cm["groups"][1]["unsupported"])

    def test_hash_changes_with_model(self):
        a = gen.model_hash(model_from(SV), "apb")
        b = gen.model_hash(model_from(SV.replace("{1}", "{2}")), "apb")
        self.assertNotEqual(a, b)
        self.assertEqual(a, gen.model_hash(model_from(SV), "apb"))

    def test_sv_long(self):
        self.assertEqual(gen.sv_long(-5), "-5")
        self.assertEqual(gen.sv_long(2 ** 64 - 1), "64'hFFFFFFFFFFFFFFFF")
        self.assertEqual(gen.sv_long(7), "7")


if __name__ == "__main__":
    unittest.main()
