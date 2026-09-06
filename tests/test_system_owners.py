#!/usr/bin/env python3
"""Check owner accounting, including deliberate incomplete/oversized records."""

import unittest
from capture_system_owners import decode_rows

CAPTURE = (
    "MCB 0312 0008 022C \n"
    "SUB 0313 0044 0314 00A2 \n"
    "SUB 03B6 0044 03B7 00F3 \n"
    "SUB 04AA 0042 04AB 0020 \n"
    "SUB 04CB 0053 04CC 0073 \n"
    "MCB 053F 0540 00E3 \n"
)


class OwnerTests(unittest.TestCase):
    def test_complete_system_accounting(self):
        rows = decode_rows(CAPTURE)
        self.assertEqual(sum(row[3] * 16 for row in rows["SUB"]), 8832)
        self.assertEqual(8832 + len(rows["SUB"]) * 16, rows["MCB"][0][2] * 16)

    def test_missing_allocation_rejected(self):
        with self.assertRaises(ValueError):
            decode_rows(CAPTURE.replace("SUB 04CB 0053 04CC 0073 \n", ""))

    def test_oversized_allocation_rejected(self):
        with self.assertRaises(ValueError):
            decode_rows(CAPTURE.replace("04CC 0073", "04CC 0074"))

    def test_unknown_tail_preserved(self):
        rows = decode_rows(CAPTURE.replace("SUB 04CB 0053 04CC 0073", "UNCLASSIFIED 04CB 053F"))
        self.assertEqual(rows["UNCLASSIFIED"], [[0x4CB, 0x53F]])

    def test_bad_chain_rejected(self):
        with self.assertRaises(ValueError):
            decode_rows(CAPTURE.replace("MCB 053F", "MCB 0540"))

    def test_malformed_row_rejected(self):
        with self.assertRaises(ValueError):
            decode_rows(CAPTURE.replace("SUB 04CB", "SUB nope"))


if __name__ == "__main__":
    unittest.main()
