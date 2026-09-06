#!/usr/bin/env python3
"""The boot staging bound must cover DOSINIT beyond the old 40 KiB limit."""

import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "dos_copy_size", Path(__file__).resolve().parents[1] / "tools/gen_dos_copy_size.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CopySizeTests(unittest.TestCase):
    def test_exact_even(self):
        self.assertEqual(module.copy_size(0xA180), 0xA180)

    def test_odd_tail(self):
        self.assertEqual(module.copy_size(0xA183), 0xA184)

    def test_old_limit_is_not_a_ceiling(self):
        self.assertEqual(module.copy_size(0xA001), 0xA002)

    def test_bounds(self):
        self.assertEqual(module.copy_size(1), 2)
        self.assertEqual(module.copy_size(0xFFF0), 0xFFF0)
        for size in (0, -1, 0xFFF1, 0x10000):
            with self.assertRaises(ValueError):
                module.copy_size(size)


if __name__ == "__main__":
    unittest.main()
