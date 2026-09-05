#!/usr/bin/env python3
"""Check both 8086 segment-materialization forms and all fifteen call sites."""

from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent


class DataSegmentTests(unittest.TestCase):
    def test_assembled_contract(self):
        with tempfile.TemporaryDirectory(prefix="msdos-bios-segment-") as scratch:
            for separate, expected in (
                (False, bytes.fromhex("0e 07 cb 34 12")),
                (True, bytes.fromhex("2e ff 36 07 00 07 cb 34 12")),
            ):
                output = Path(scratch) / f"{separate}.bin"
                command = [str(ROOT / "bin/jwasm-bin"), f"-I{ROOT / 'src/BIOS'}", f"-Fo{output}"]
                if separate:
                    command.append("-DBIOS_SERVICE_SEPARATE_DATA=1")
                command.append(str(ROOT / "tests/bios_data_segment_masm.asm"))
                subprocess.run(command, check=True, capture_output=True)
                # Both forms preserve FLAGS and all registers except intended
                # ES; the high form reads the explicit low-owner word at 0007h.
                self.assertEqual(output.read_bytes(), expected)

    def test_segment_materialization_sites(self):
        total = 0
        for name in ("MSDSKHIG.INC", "MSIOCTL.INC"):
            for line in (ROOT / "src/BIOS" / name).read_text().splitlines():
                code = line.split(";", 1)[0]
                self.assertFalse(re.search(r"\bPUSH\s+CS\b", code, re.I), name)
                if re.search(r"\bBIOS_PUSH_DATA_SEG\b", code):
                    total += 1
        self.assertEqual(total, 15, "review every added/removed data-segment consumer")


if __name__ == "__main__":
    unittest.main()
