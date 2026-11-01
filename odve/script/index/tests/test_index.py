"""Unit tests of the code index on a synthetic repository: a tiny agent in
the scaffold layout (fl.f, interface, DUT, package with classes and
type_id::create calls, a top). The tag layer runs when a Universal Ctags
is available, the semantic layer when pyslang is importable; both are
skipped, not failed, otherwise - the queries must still answer.

    cd odve/script/index && python3 -m unittest discover -s tests
    (or <root>/.odve-index/venv/bin/python -m unittest ... for the semantic tests)
"""
import json
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from idxlib import repo, build, queries          # noqa: E402
from idxlib.db import connect                    # noqa: E402
import mcp_stdlib                                # noqa: E402

AGENT = "comp/agents/foo"
FILES = {
    f"{AGENT}/intf/foo_if.sv": "interface foo_if (input logic clk);\n    logic req;\n    logic ack;\nendinterface\n",
    f"{AGENT}/src/foo_pkg.sv": """package foo_pkg;
    class foo_cfg;
        int unsigned nregs = 4;
        function new(); endfunction
    endclass
    class foo_base;
        function new(); endfunction
    endclass
    class foo_registry #(type T = foo_base);      // the shape of uvm_component_registry
        static function T create(string name, foo_base parent = null);
            T obj = new();
            return obj;
        endfunction
    endclass
    class foo_mon extends foo_base;
        typedef foo_registry #(foo_mon) type_id;
        foo_cfg cfg;
        function void build();
            cfg = new();
            if (cfg.nregs > 2) $display("big");
        endfunction
    endclass
    class foo_env extends foo_base;
        typedef foo_registry #(foo_env) type_id;
        foo_mon mon;
        function void build_phase();
            mon = foo_mon::type_id::create("mon", this);
        endfunction
    endclass
endpackage
""",
    f"{AGENT}/vrf/dut/dut.sv": "module dut #(parameter int N = 2) (input logic clk, input logic req, output logic ack);\n    always_ff @(posedge clk) ack <= req;\nendmodule\n",
    f"{AGENT}/vrf/tb/top.sv": """`include "foo_defs.svh"
module top;
    logic clk = 0;
    foo_if foo_if (.clk(clk));
    dut #(.N(`FOO_N)) dut_i (.clk(clk), .req(foo_if.req), .ack(foo_if.ack));
    initial begin foo_pkg::foo_cfg c = new(); $display(c.nregs); end
endmodule
""",
    f"{AGENT}/vrf/tb/foo_defs.svh": "`define FOO_N 3\n",
    f"{AGENT}/list/agent.f": "+incdir+${ODVE_FOO}/src\n${ODVE_FOO}/intf/foo_if.sv\n${ODVE_FOO}/src/foo_pkg.sv\n",
    f"{AGENT}/vrf/list/fl_dut.f": "${ODVE_FOO}/vrf/dut/dut.sv\n",
    f"{AGENT}/vrf/list/fl_tb.f": "+incdir+${ODVE_FOO}/vrf/tb\n-f ${ODVE_FOO}/list/agent.f\n${ODVE_FOO}/vrf/tb/top.sv\n",
    f"{AGENT}/vrf/list/fl.f": "// flat\n-f ${ODVE_FOO}/vrf/list/fl_dut.f\n-f ${ODVE_FOO}/vrf/list/fl_tb.f\n",
    f"{AGENT}/vrf/work/common/Makefile": "TOP = top\n",
    f"{AGENT}/vrf/work/run/sourceme": "#!/bin/bash\nexport ODVE_FOO=$(readlink -f ../../..)\n",
    "unlisted/old.sv": "module old_thing; endmodule\n",
}


class IndexTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = tempfile.mkdtemp(prefix="odve-index-test-")
        for p, text in FILES.items():
            ap = os.path.join(cls.root, p)
            os.makedirs(os.path.dirname(ap), exist_ok=True)
            with open(ap, "w") as f:
                f.write(text)
        os.makedirs(os.path.join(cls.root, ".odve-index"))
        if not repo.find_ctags(cls.root):           # borrow the ctags of the repo these tests live in
            own = repo.find_ctags(repo.find_root(HERE))
            if own:
                os.environ["ODVE_CTAGS"] = own
        cls.ctags = repo.find_ctags(cls.root)
        cls.pyslang = repo.have_pyslang()
        cls.res = build.build(cls.root)
        cls.con = connect(cls.root)

    @classmethod
    def tearDownClass(cls):
        cls.con.close()
        shutil.rmtree(cls.root, ignore_errors=True)

    # ------------------------------------------------------------ units & lists
    def test_unit_discovered_with_env_and_top(self):
        self.assertEqual(self.res["units"], ["foo"])
        u = self.con.execute("SELECT * FROM units WHERE name = 'foo'").fetchone()
        self.assertEqual(u["top"], "top")
        self.assertEqual(u["filelist"], f"{AGENT}/vrf/list/fl.f")
        env = json.loads(self.con.execute("SELECT env FROM filelists WHERE path = ?", (u["filelist"],)).fetchone()["env"])
        self.assertTrue(env["ODVE_FOO"].endswith(AGENT))

    def test_fl_resolve_follows_nesting_incdirs_and_includes(self):
        r = queries.fl_resolve(self.con, self.root, "fl.f")
        self.assertEqual(r["files"], [f"{AGENT}/vrf/dut/dut.sv", f"{AGENT}/intf/foo_if.sv", f"{AGENT}/src/foo_pkg.sv", f"{AGENT}/vrf/tb/top.sv"])
        self.assertIn(f"{AGENT}/vrf/tb", r["incdirs"])
        self.assertIn(f"{AGENT}/list/agent.f", r["nested"])
        self.assertIn(f"{AGENT}/vrf/tb/foo_defs.svh", r["included"])

    def test_fl_of_file_and_unlisted(self):
        r = queries.fl_of_file(self.con, self.root, f"{AGENT}/src/foo_pkg.sv")
        self.assertTrue(r["listed"])
        self.assertIn("foo", r["filelists"][0]["units"])
        self.assertFalse(queries.fl_of_file(self.con, self.root, "unlisted/old.sv")["listed"])

    # ------------------------------------------------------------ tags
    def test_tags_find_definitions(self):
        if not self.ctags:
            self.skipTest("no Universal Ctags")
        r = queries.sym_find(self.con, self.root, "old_thing")
        self.assertEqual(r["matches"][0]["file"], "unlisted/old.sv")
        self.assertFalse(r["matches"][0]["semantic"])
        outline = queries.sym_outline(self.con, self.root, "unlisted/old.sv")
        self.assertEqual(outline["symbols"][0]["name"], "old_thing")

    # ------------------------------------------------------------ semantics
    def test_semantic_definitions_refs_hierarchy_tb(self):
        if not self.pyslang:
            self.skipTest("no pyslang")
        u = self.con.execute("SELECT status FROM units WHERE name = 'foo'").fetchone()
        self.assertEqual(u["status"], "ok", queries.diag(self.con, self.root, "foo")["diags"])
        d = queries.sym_def(self.con, self.root, "foo_cfg")["definition"]
        self.assertEqual((d["file"], d["line"], d["kind"]), (f"{AGENT}/src/foo_pkg.sv", 2, "class"))
        refs = queries.sym_refs(self.con, self.root, "nregs")["symbols"][0]
        self.assertEqual(refs["n_refs"], 2)                         # cfg.nregs in foo_mon, c.nregs in top
        self.assertIn(f"{AGENT}/vrf/tb/top.sv", refs["refs"])
        tree = queries.hier_tree(self.con, self.root)["tree"][0]
        self.assertEqual(tree["path"], "top")
        self.assertEqual({c["def"] for c in tree["children"]}, {"foo_if", "dut"})
        dut = [c for c in tree["children"] if c["def"] == "dut"][0]
        self.assertIn("N=", dut["params"])
        inst = queries.hier_instance(self.con, self.root, "top.dut_i")["instances"][0]
        self.assertIn("req(foo_if.req)", inst["conns"])
        tb = queries.tb_tree(self.con, self.root, root_class="foo_env")["roots"][0]
        self.assertEqual(tb["children"][0]["creates"], "foo_mon")
        self.assertEqual(tb["children"][0]["name"], "mon")
        self.assertEqual(tb["children"][0]["in"], "build_phase")
        ci = queries.class_info(self.con, self.root, "foo_mon")
        self.assertEqual(ci["base_chain"], ["foo_base"])
        self.assertEqual([m["name"] for m in ci["methods"]], ["build"])
        self.assertEqual(queries.sym_members(self.con, self.root, "foo_cfg")["owners"][0]["members"][0]["name"], "nregs")
        deps = queries.file_deps(self.con, self.root, f"{AGENT}/vrf/tb/top.sv")
        self.assertEqual(deps["includes"][0]["included"], f"{AGENT}/vrf/tb/foo_defs.svh")

    # ------------------------------------------------------------ update & stale
    def test_update_marks_stale_then_refreshes(self):
        p = f"{AGENT}/src/foo_pkg.sv"
        ap = os.path.join(self.root, p)
        with open(ap, "a") as f:
            f.write("// touched\n")
        self.assertEqual(queries.sym_def(self.con, self.root, "foo_cfg")["stale"], [p])
        r = build.update(self.root, [ap], elab="sync" if self.pyslang else "none")
        self.assertEqual(r["dirty_units"], ["foo"])
        self.assertEqual(queries.sym_def(self.con, self.root, "foo_cfg")["stale"], [])
        if self.pyslang:
            self.assertEqual(r["elab"][0]["status"], "ok")

    def test_code_at(self):
        r = queries.code_at(self.con, self.root, f"{AGENT}/vrf/dut/dut.sv", 2, context=0)
        self.assertIn("always_ff", r["text"])

    # ------------------------------------------------------------ MCP transport
    def test_mcp_stdlib_roundtrip(self):
        srv = mcp_stdlib.MCPServer("t", "hi")

        @srv.tool()
        def echo(name: str, n: int = 1, tags: list[str] | None = None) -> str:
            """Echo."""
            return json.dumps({"name": name, "n": n, "tags": tags})
        init = json.loads(srv.handle_line('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'))
        self.assertEqual(init["result"]["serverInfo"]["name"], "t")
        self.assertIsNone(srv.handle_line('{"jsonrpc":"2.0","method":"notifications/initialized"}'))
        lst = json.loads(srv.handle_line('{"jsonrpc":"2.0","id":2,"method":"tools/list"}'))["result"]["tools"][0]
        self.assertEqual(lst["inputSchema"]["required"], ["name"])
        self.assertEqual(lst["inputSchema"]["properties"]["tags"], {"type": "array", "items": {"type": "string"}})
        call = json.loads(srv.handle_line('{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":{"name":"x","tags":["a"]}}}'))
        self.assertEqual(json.loads(call["result"]["content"][0]["text"]), {"name": "x", "n": 1, "tags": ["a"]})
        err = json.loads(srv.handle_line('{"jsonrpc":"2.0","id":4,"method":"nope"}'))
        self.assertEqual(err["error"]["code"], -32601)


if __name__ == "__main__":
    unittest.main()
