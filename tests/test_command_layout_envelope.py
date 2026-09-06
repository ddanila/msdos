#!/usr/bin/env python3
"""Check the optimistic whole-code relocation bound, not relocation safety."""
import unittest

from report_command_residency import code_only_envelope


class EnvelopeTest(unittest.TestCase):
    def test_current_partition(self):
        self.assertEqual(code_only_envelope(0xA93, 0xE30), (1184, 2448))

    def test_no_code_has_no_release(self):
        self.assertEqual(code_only_envelope(0x100, 0x321), (816, 0))

    def test_rounding_is_applied_to_both_allocations(self):
        self.assertEqual(code_only_envelope(0x111, 0x122), (288, 16))

    def test_psp_is_never_reclaimed(self):
        self.assertEqual(code_only_envelope(0x321, 0x321), (256, 560))

    def test_invalid_order(self):
        for end, limit in ((0xFF, 0x300), (0x301, 0x300)):
            with self.assertRaises(ValueError):
                code_only_envelope(end, limit)

    def test_stable_low_entries_are_not_reclaimed(self):
        self.assertEqual(code_only_envelope(0xB0B, 0xEA8, 0x12B), (1232, 2528))


if __name__ == "__main__":
    unittest.main()
