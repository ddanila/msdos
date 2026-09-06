#!/usr/bin/env python3
"""Run the shared request decoder against real device frames and separate CS."""
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DispatchTests(unittest.TestCase):
    def run_case(self, flags, expected):
        with tempfile.TemporaryDirectory(prefix="msdos-dispatch-") as name:
            work = Path(name)
            built = subprocess.run([str(ROOT / "bin/jwasm-masm"),
                            f"-I{ROOT / 'src/BIOS'} {flags}",
                            f"{ROOT / 'tests/bios_dispatch_masm.asm'},{work / 'probe.obj'};"],
                           capture_output=True)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            linker = runpy.run_path(str(ROOT / "bin/wlink"))["wlink_bin"]()
            subprocess.run([linker, "format", "dos", "option", "quiet",
                            "option", "packcode=1", "option", "packdata=1",
                            "option", "nofarcalls", "option", "map=probe.map",
                            "name", "probe.exe", "file", "probe.obj"],
                           cwd=work, check=True, capture_output=True)
            result = subprocess.run([str(ROOT / "bin/dos-run"), str(work / "probe.exe")],
                                    capture_output=True, timeout=10)
            self.assertEqual(result.returncode, expected, result.stdout + result.stderr)

    def test_normal_owner(self):
        self.run_case("", 0)

    def test_separate_code_owner(self):
        self.run_case("-DSEPARATE_TEST", 0)

    def test_stale_table_rejected(self):
        self.run_case("-DSEPARATE_TEST -DSTALE_TABLE", 4)

    def test_wrong_error_entry_rejected(self):
        self.run_case("-DSEPARATE_TEST -DWRONG_ERROR_ENTRY", 11)


if __name__ == "__main__":
    unittest.main()
