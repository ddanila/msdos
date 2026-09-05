#!/usr/bin/env python3
"""Focused parser tests for the emitted-listing control-flow inventory."""

import unittest

from report_bios_service_crossings import inventory, listing_rows


def row(address, encoding, source):
    return f"{address:04X} {encoding:<27}{source}"


class CrossingsTests(unittest.TestCase):
    def test_classification_and_module_bias(self):
        listing = "\n".join([
            row(0x20, "", "READ_SECTOR PROC NEAR"),
            row(0x20, "E80000r", "CALL LOW_HELPER"),
            row(0x23, "E80500", "CALL internal"),
            row(0x26, "2EFF1E", "CALL ORIG13"),
            row(0x2B, "CD13", "int 13h ; ROM call"),
            row(0x2D, "90", "internal: NOP"),
            row(0x2E, "E90000r", "JMP missing"),
            row(0x31, "CF", "IRET"),
            " " * 32 + "CALL INACTIVE_BRANCH",
            row(0x50, "E90000r", "JMP OUTSIDE_CANDIDATE"),
        ])
        start, end, count, crossings = inventory(listing, {
            "READ_SECTOR": 0x120, "DISK005S": 0x140, "LOW_HELPER": 0x40,
        })
        self.assertEqual((start, end, count), (0x120, 0x140, 7))
        self.assertEqual(crossings[("direct outside body", "CALL LOW_HELPER (0040h)")], [0x120])
        self.assertEqual(crossings[("indirect: unresolved", "CALL ORIG13")], [0x126])
        self.assertEqual(crossings[("interrupt boundary", "int 13h")], [0x12B])
        self.assertEqual(crossings[("direct: unresolved", "JMP missing")], [0x12E])
        self.assertEqual(len(crossings), 5)

    def test_include_marker_and_short_branch(self):
        # Included source marker is inside the fixed prefix, not the source.
        included = row(0x10, "EB00", "JMP SHORT target")
        included = included[:30] + "C " + included[32:]
        listing = "\n".join([
            row(0x10, "", "READ_SECTOR LABEL BYTE"), included,
            row(0x12, "C3", "target: RET"),
        ])
        labels, rows = listing_rows(listing)
        self.assertEqual(labels["TARGET"], 0x12)
        self.assertEqual(rows[0][2], "JMP SHORT target")
        self.assertFalse(inventory(listing, {"READ_SECTOR": 0x110, "DISK005S": 0x120})[3])


if __name__ == "__main__":
    unittest.main()
