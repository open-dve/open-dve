"""unittest for covlib.cgparse (run: python3 -m unittest discover -s script/cov)."""
import textwrap
import unittest

from covlib import cgparse
from covlib.cgparse import Unsupported, find_native_blocks, parse_file, parse_number


def groups_of(sv):
    """Parse a snippet as if it were inside an ODVE_COV_NATIVE block."""
    text = "`ifdef ODVE_COV_NATIVE\n" + textwrap.dedent(sv) + "\n`endif\n"
    groups, created, sampled = parse_file("t.sv", text)
    return groups


APB = """
    covergroup apb_cg with function sample(int len, bit dir);
      cp_len: coverpoint len { bins one = {1}; bins some = {[2:4]}; bins big[] = {8, 16};
                               ignore_bins zero = {0}; illegal_bins bad = {[256:$]};
                               option.at_least = 2; }
      cp_dir: coverpoint dir;
      x_len_dir: cross cp_len, cp_dir { ignore_bins no_big_rd = binsof(cp_len.big[8]) && binsof(cp_dir.auto[0]); }
    endgroup
"""


class TestBlocks(unittest.TestCase):
    def test_find_blocks_and_else(self):
        text = "a\n`ifdef ODVE_COV_NATIVE\nX\n`ifdef FOO\nY\n`endif\nZ\n`else\nW\n`endif\nb\n"
        blocks = find_native_blocks(text)
        self.assertEqual(len(blocks), 1)
        first, body = blocks[0]
        self.assertEqual(first, 3)
        self.assertEqual(body.split("\n"), ["X", "`ifdef FOO", "Y", "`endif", "Z"])

    def test_macro_uses(self):
        text = "`odve_cov_create(apb_cg)\n`odve_cov_sample(apb_cg, a, b)\n`odve_cov_sample( other , x)"
        created, sampled = cgparse.find_macro_uses(text)
        self.assertEqual(created, ["apb_cg"])
        self.assertEqual(sampled, ["apb_cg", "other"])

    def test_comments_keep_lines(self):
        text = "a // c\nb /* x\ny */ c\n\"s//t\"\n"
        clean = cgparse.strip_comments(text)
        self.assertEqual(clean.count("\n"), text.count("\n"))
        self.assertIn('"s//t"', clean)
        self.assertNotIn("x", clean.split("\n")[1])


class TestNumbers(unittest.TestCase):
    def test_plain_and_based(self):
        self.assertEqual(parse_number("12_3"), (123, None))
        self.assertEqual(parse_number("8'hFF"), (255, None))
        self.assertEqual(parse_number("'d10"), (10, None))
        self.assertEqual(parse_number("3'b101"), (5, None))

    def test_wildcard(self):
        v, mask = parse_number("4'b01??")
        self.assertEqual(v, 0b0100)
        self.assertEqual(mask & 0xF, 0b1100)
        self.assertEqual(mask >> 4, (1 << 60) - 1)   # bits above the literal must be 0

    def test_decimal_wildcard_unsupported(self):
        with self.assertRaises(Unsupported):
            parse_number("4'd?")


class TestApb(unittest.TestCase):
    def setUp(self):
        self.g = groups_of(APB)[0]

    def test_group(self):
        g = self.g
        self.assertIsNone(g.unsupported, g.unsupported)
        self.assertEqual(g.name, "apb_cg")
        self.assertEqual([(a.name, a.width, a.signed) for a in g.args], [("len", 32, True), ("dir", 1, False)])
        self.assertIn("covergroup apb_cg", g.text)
        self.assertTrue(g.text.rstrip().endswith("endgroup"))

    def test_points(self):
        p = self.g.point("cp_len")
        self.assertEqual([b.name for b in p.coverage_bins], ["one", "some", "big[8]", "big[16]"])
        self.assertEqual([b.name for b in p.bins if b.kind == "ignore"], ["zero"])
        bad = [b for b in p.bins if b.kind == "illegal"][0]
        self.assertEqual(bad.ranges, [(256, 2 ** 31 - 1)])
        self.assertEqual(p.at_least, 2)
        d = self.g.point("cp_dir")
        self.assertEqual([b.name for b in d.bins], ["auto[0]", "auto[1]"])

    def test_cross(self):
        x = self.g.crosses[0]
        self.assertEqual(x.name, "x_len_dir")
        self.assertEqual(x.points, ["cp_len", "cp_dir"])
        self.assertEqual(x.filters[0].kind, "ignore")
        self.assertEqual(x.filters[0].expr,
                         ("and", ("binsof", "cp_len", "big[8]"), ("binsof", "cp_dir", "auto[0]")))


class TestConstructs(unittest.TestCase):
    def one(self, body, args="int a, bit [3:0] b"):
        g = groups_of(f"covergroup g with function sample({args});\n{body}\nendgroup")[0]
        self.assertIsNone(g.unsupported, g.unsupported)
        return g

    def test_transition_and_default_and_wildcard(self):
        g = self.one("""
            cp: coverpoint a { bins up = (1 => 2 => 3); bins hops[] = (0 => 1, 5 => 6);
                               bins rest = default; }
            cw: coverpoint b { wildcard bins w = {4'b01??}; bins other = default; }""")
        cp = g.point("cp")
        self.assertEqual(cp.bins[0].trans, [[1, 2, 3]])
        self.assertEqual([b.name for b in cp.bins[1:3]], ["hops[0]", "hops[1]"])
        self.assertTrue(cp.bins[3].default)
        w = g.point("cw").bins[0]
        self.assertEqual(w.wild[0][0], 4)

    def test_auto_bins_wide_type(self):
        g = self.one("cp: coverpoint a;")
        bins = g.point("cp").bins
        self.assertEqual(len(bins), 64)
        self.assertEqual(bins[0].ranges, [(-2 ** 31, -2 ** 31 + 2 ** 26 - 1)])
        self.assertEqual(bins[-1].ranges[0][1], 2 ** 31 - 1)

    def test_array_range_and_dollar(self):
        g = self.one("cp: coverpoint b { bins v[] = {[1:3], 9}; bins top = {[10:$]}; }")
        bins = g.point("cp").bins
        self.assertEqual([b.name for b in bins], ["v[1]", "v[2]", "v[3]", "v[9]", "top"])
        self.assertEqual(bins[-1].ranges, [(10, 15)])

    def test_iff_and_group_options(self):
        g = self.one("option.at_least = 3; type_option.weight = 2;\ncp: coverpoint a iff (!b) { bins z = {0}; }")
        self.assertEqual(g.at_least, 3)
        self.assertEqual(g.weight, 2)
        self.assertEqual(g.point("cp").iff, ("b", True))

    def test_cross_filter_precedence(self):
        g = self.one("""
            ca: coverpoint a { bins l = {[0:9]}; bins h = {[10:$]}; }
            cb: coverpoint b;
            x: cross ca, cb { illegal_bins il = binsof(ca.h) || !binsof(cb) && binsof(ca.l); }""")
        e = g.crosses[0].filters[0].expr
        self.assertEqual(e[0], "or")
        self.assertEqual(e[2][0], "and")


class TestUnsupported(unittest.TestCase):
    def bad(self, body, args="int a, bit b", expect=None):
        g = groups_of(f"covergroup g with function sample({args});\n{body}\nendgroup")[0]
        self.assertIsNotNone(g.unsupported, "expected unsupported")
        if expect:
            self.assertIn(expect, g.unsupported)
        return g

    def test_no_sample_function(self):
        g = groups_of("covergroup g @(posedge clk);\n cp: coverpoint a;\nendgroup")[0]
        self.assertIn("with function sample", g.unsupported)

    def test_expression_coverpoint(self):
        self.bad("cp: coverpoint a + 1 { bins z = {0}; }", expect="expression")

    def test_fixed_array_bins(self):
        self.bad("cp: coverpoint a { bins z[4] = {[0:15]}; }", expect="fixed-size")

    def test_with_clause(self):
        self.bad("cp: coverpoint a { bins z = {[0:9]} with (item % 2 == 0); }", expect="'with'")

    def test_intersect(self):
        self.bad("ca: coverpoint a { bins l = {0}; }\ncb: coverpoint b;\nx: cross ca, cb { ignore_bins i = binsof(ca) intersect {0}; }",
                 expect="intersect")

    def test_cross_bins(self):
        self.bad("ca: coverpoint a { bins l = {0}; }\ncb: coverpoint b;\nx: cross ca, cb { bins both = binsof(ca.l); }",
                 expect="bins inside a cross")

    def test_unknown_cross_member(self):
        self.bad("ca: coverpoint a { bins l = {0}; }\nx: cross ca, nope;", expect="not a coverpoint")

    def test_enum_arg(self):
        g = groups_of("covergroup g with function sample(kind_e k);\n cp: coverpoint k;\nendgroup")[0]
        self.assertIn("argument type", g.unsupported)

    def test_repetition(self):
        self.bad("cp: coverpoint a { bins r = (1 [*3]); }", expect="repetition")

    def test_second_group_still_parsed(self):
        groups = groups_of("covergroup bad @(posedge clk);\n cp: coverpoint a;\nendgroup\n" + APB)
        self.assertEqual([g.name for g in groups], ["bad", "apb_cg"])
        self.assertIsNotNone(groups[0].unsupported)
        self.assertIsNone(groups[1].unsupported)


if __name__ == "__main__":
    unittest.main()
