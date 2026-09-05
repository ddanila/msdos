#!/usr/bin/env python3
"""Regression tests for the paired conventional-memory report."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "vc_memory_comparison", ROOT / "tests" / "capture_vc_memory_comparison.py"
)
comparison = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(comparison)


class ComparisonReportTest(unittest.TestCase):
    def test_rejected_config_cannot_earn_memory_credit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            serial, screen = root / "serial", root / "screen"
            for destination in (serial, screen):
                for error in ("Error in CONFIG.SYS line 6", "Bad command or parameters - Z"):
                    serial.write_text("")
                    screen.write_text("")
                    destination.write_text(error + "\n")
                    with self.assertRaisesRegex(ValueError, "boot rejected configuration"):
                        comparison.parse_capture(serial, screen)

    def test_vc_block_count_is_separate_from_mem_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            serial = root / "serial.log"
            screen = root / "screen.log"
            serial.write_text(
                "MEMORY_CEILING INT12=027F BDA=027F EBDA=9FC0\n"
                "  0478:0000  SYSTEM  22288  System\n"
                "  1586:0000  FREE  566144  Free\n"
                "PARITY_MEM_END\n",
                encoding="latin-1",
            )
            screen.write_text(
                "║ 0070 2 39,984 DOS 6.22 ║\n"
                "║ 0A35 3 6,320 COMMAND ║\n"
                "║ 0BC9 2 12,784 VC.COM ║\n"
                "║ 0EE4 2 594,512 free memory ║\n"
                "║ 9FC0 1 181,248 system ║\n",
                encoding="utf-8",
            )

            parsed = comparison.parse_capture(serial, screen)
            self.assertEqual(parsed["largest"], 594512)
            self.assertEqual(parsed["vc_rows"][1]["blocks"], 3)

            report = comparison.report(parsed, parsed, "config", "vc")
            self.assertIn("| 0A35h | 3 | 6,320 | COMMAND |", report)
            self.assertIn("captured while `MEM` was resident", report)
            self.assertIn("different process snapshot", report)
            self.assertIn("| System start to COMMAND | 40,016 | 40,016 | +0 |", report)
            self.assertIn("span differences reconcile exactly to the 0-byte gap", report)


if __name__ == "__main__":
    unittest.main()
