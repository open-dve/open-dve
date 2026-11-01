"""Offline tests of release.py: wheel selection for cp312/linux-x86_64,
tools.lock expansion, manifest check of a synthetic bundle."""
import hashlib
import io
import os
import sys
import tarfile
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import release                                   # noqa: E402


class ReleaseTest(unittest.TestCase):
    def test_wheel_fit(self):
        fit = lambda fn: release.wheel_fit(fn, "cp312")   # noqa: E731
        self.assertEqual(fit("pyslang-12.1.0-cp311-abi3-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl"), (2, 27))
        self.assertEqual(fit("nanobind_backend-1.0.0-cp312-cp312-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl"), (2, 27))
        self.assertEqual(fit("pip-26.2.2-py3-none-any.whl"), (0, 0))
        self.assertEqual(fit("x-1.0-cp312-cp312-manylinux2014_x86_64.whl"), (2, 17))
        self.assertIsNone(fit("nanobind_backend-1.0.0-cp311-cp311-manylinux_2_28_x86_64.whl"))   # other minor
        self.assertIsNone(fit("x-1.0-cp313-abi3-manylinux_2_28_x86_64.whl"))                     # abi3 from a newer minor
        self.assertIsNone(fit("x-1.0-cp312-cp312-macosx_10_14_x86_64.whl"))
        self.assertIsNone(fit("x-1.0-cp312-cp312-manylinux_2_28_aarch64.whl"))
        self.assertIsNone(fit("x-1.0.tar.gz"))

    def test_lock_expansion(self):
        lock = release.read_lock()
        self.assertEqual(lock["PY_TAG"], "cp312")
        self.assertTrue(lock["CTAGS_URL"].endswith(f"uctags-{lock['CTAGS_VER']}-linux-x86_64.release.tar.xz"))
        self.assertIn(lock["CTAGS_TAG"], lock["CTAGS_URL"])
        self.assertEqual(lock["RELEASE_URL"], f"https://github.com/{lock['RELEASE_REPO']}/releases/download/{lock['RELEASE_TAG']}/{lock['RELEASE_ASSET']}")
        self.assertEqual(len(lock["CTAGS_SHA"]), 64)
        self.assertEqual([n for n, _ in release.read_requirements()], ["pyslang", "nanobind-backend"])

    def test_check_manifest(self):
        files = {"VERSION": b"version=t\npython=cp312\n", "README.txt": b"hi\n", "wheels/a-1-py3-none-any.whl": b"PK", "tools/uctags-t.tar.xz": b"xz"}
        man = "".join(f"{hashlib.sha256(d).hexdigest()}  {n}\n" for n, d in files.items())
        with tempfile.TemporaryDirectory() as td:
            for bad in (False, True):
                path = os.path.join(td, "b.tar.gz")
                with tarfile.open(path, "w:gz") as tf:
                    for n, d in list(files.items()) + [("MANIFEST.sha256", man.encode())]:
                        if bad and n == "README.txt":
                            d = b"changed\n"
                        ti = tarfile.TarInfo(f"odve-index-tools-t/{n}")
                        ti.size = len(d)
                        tf.addfile(ti, io.BytesIO(d))
                out = io.StringIO()
                sys.stdout, old = out, sys.stdout
                try:
                    rc = release.check(path)
                finally:
                    sys.stdout = old
                self.assertEqual(rc, 1 if bad else 0, out.getvalue())
                self.assertIn("MISMATCH: README.txt" if bad else "all verified", out.getvalue())


if __name__ == "__main__":
    unittest.main()
