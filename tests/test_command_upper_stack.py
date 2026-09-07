#!/usr/bin/env python3
"""Linked whole-stack retirement and its initialization ownership contracts."""
from pathlib import Path
import re
import tempfile
import unittest

from report_command_residency import parse_map
from test_command_high_resident_qemu import SOURCE, build


class UpperStackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="command-upper-stack-")
        cls.work = Path(cls.temporary.name)
        cls.binary = build(cls.work / "upper", True, upper_data=True)
        cls.segments, cls.symbols = parse_map(cls.binary.with_suffix(".MAP"))

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_complete_stack_is_in_existing_upper_owner(self):
        symbols = self.symbols
        start, end = symbols["shell_data_start"], symbols["shell_data_end"]
        self.assertEqual(start, self.segments["CODERES"].end)
        self.assertEqual(start, self.segments["DATARES"].start)
        self.assertEqual(symbols["rstack"] - start, 125)
        self.assertEqual(end, self.segments["DATARES"].end)
        self.assertEqual((start + 15) & ~15, 432)
        self.assertEqual(((end + 15) & ~15) - (start & ~15), 464)
        self.assertNotIn("shell_binding_lodcom_data", symbols)

    def test_live_stack_switch_precedes_release_and_rollback_free(self):
        listing = (self.work / "upper/INIT.LST").read_text(encoding="latin-1")
        body = listing.split("relocate_shell_data proc near", 1)[1].split("relocate_shell_data endp", 1)[0]
        publish = body.split("call shell_data_publish", 1)[1]
        self.assertLess(publish.index("mov ss,ax"), publish.index("mov ah,4ah"))
        rollback = body.split("shell_data_rollback:", 1)[1]
        self.assertLess(rollback.index("mov ss,ax"), rollback.index("mov ah,49h"))
        self.assertEqual(len(re.findall(r"(?m)^\w+ 8ED0\s+.*mov ss,ax", body)), 2)

    def test_final_environment_reads_do_not_use_upper_ss(self):
        listing = (self.work / "upper/COMMAND2.LST").read_text(encoding="latin-1")
        finalizer = listing.split("ENDINIT:", 1)[1].split("noreset:", 1)[0]
        for name in ("resetenv", "envsiz"):
            lines = [line for line in finalizer.splitlines() if name in line]
            self.assertEqual(len(lines), 1)
            self.assertNotRegex(lines[0], r"^\w+ 36")

    def test_default_binary_unchanged(self):
        normal = build(self.work / "normal", False)
        self.assertEqual(normal.read_bytes(), (SOURCE / "COMMAND.COM").read_bytes())


if __name__ == "__main__":
    unittest.main()
