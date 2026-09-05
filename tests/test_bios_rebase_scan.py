#!/usr/bin/env python3
"""Reject malformed evidence and preserve unaligned numeric candidates."""
import struct
import unittest

from report_bios_rebase_scan import matches, owner, records


def fixture():
    return b"".join(tag.encode() + struct.pack("<HHH", 0x70, 0x10, 3) + b"abc"
                    for tag in "HLBDIC")


class ScanTests(unittest.TestCase):
    def test_complete_regions(self):
        self.assertEqual(list(records(fixture())), list("HLBDIC"))
        self.assertEqual(records(fixture())["H"], (0x70, 0x10, b"abc"))

    def test_every_truncation_rejected(self):
        data = fixture()
        for end in range(len(data)):
            with self.subTest(end=end), self.assertRaises(ValueError):
                records(data[:end])

    def test_wrong_order_empty_and_trailing_rejected(self):
        data = fixture()
        for bad in (b"L" + data[1:], data + b"x", data[:5] + b"\0\0" + data[7:]):
            with self.assertRaises(ValueError):
                records(bad)

    def test_unaligned_candidates_and_previous_word(self):
        self.assertEqual(list(matches(0x10, b"\x75\x04\0\x75\x04", 0x475)),
                         [(0x10, None), (0x13, 4)])
        self.assertEqual(list(matches(0, b"\x75", 0x475)), [])

    def test_nearest_export_is_not_pointer_proof(self):
        self.assertEqual(owner({"table": 0x10, "code": 0x20}, 0x13), "table+0003h")
        self.assertEqual(owner({"table": 0x10}, 0), "unattributed")


if __name__ == "__main__":
    unittest.main()
