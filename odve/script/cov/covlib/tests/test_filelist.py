"""unittest for covlib.filelist."""
import os
import tempfile
import unittest

from covlib.filelist import read_filelist, expand, expand_includes


class TestFilelist(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.TemporaryDirectory()
        self.root = self.d.name
        os.makedirs(os.path.join(self.root, "sub"))
        self.w("sub/agent.f", "${ROOT}/intf/a_if.sv\n+incdir+${ROOT}/intf\n")
        self.w("sub/rel.f", "// relative to this filelist via -F\n-F agent.f\n")
        self.w("top.f", "\n".join([
            "-f ${ROOT}/sub/agent.f",
            "// a comment line",
            "+incdir+${ROOT}/uvm/src+${ROOT}/tb",
            "+define+FOO=1+BAR",
            "-L dut -sv -v ${ROOT}/lib.v -y ${ROOT}/libdir",
            "${ROOT}/tb/test_pkg.sv   // trailing comment",
            "${ROOT}/tb/top.sv",
            "${ROOT}/intf/a_if.sv",          # duplicate, must not repeat
            "-F sub/rel.f",
            "",
        ]))

    def tearDown(self):
        self.d.cleanup()

    def w(self, rel, text):
        with open(os.path.join(self.root, rel), "w") as f:
            f.write(text)

    def test_read(self):
        fl = read_filelist(os.path.join(self.root, "top.f"), env={"ROOT": self.root})
        r = self.root
        self.assertEqual(fl.files, [f"{r}/intf/a_if.sv", f"{r}/tb/test_pkg.sv", f"{r}/tb/top.sv"])
        self.assertEqual(fl.incdirs, [f"{r}/intf", f"{r}/uvm/src", f"{r}/tb"])
        self.assertEqual(fl.defines, ["FOO=1", "BAR"])

    def test_missing(self):
        with self.assertRaises(FileNotFoundError):
            read_filelist(os.path.join(self.root, "nope.f"), env={})

    def test_expand_includes(self):
        os.makedirs(os.path.join(self.root, "inc"))
        self.w("tb/pkg.sv" if os.path.isdir(os.path.join(self.root, "tb")) else "pkg.sv", "")
        self.w("pkg.sv", 'package p;\n  `include "a.svh"\n  `include "missing.svh"\nendpackage\n')
        self.w("inc/a.svh", '`include "b.svh"\n')
        self.w("inc/b.svh", '`include "a.svh"  // cycle\n')
        files = expand_includes([os.path.join(self.root, "pkg.sv")], [os.path.join(self.root, "inc")])
        self.assertEqual([os.path.basename(f) for f in files], ["pkg.sv", "a.svh", "b.svh"])

    def test_expand(self):
        self.assertEqual(expand("${A}/x/$B", {"A": "1", "B": "2"}), "1/x/2")
        self.assertEqual(expand("${NOPE}/x", {}), "${NOPE}/x")


if __name__ == "__main__":
    unittest.main()
