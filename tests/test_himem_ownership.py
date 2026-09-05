#!/usr/bin/env python3
"""Check that the HIMEM service inventory is an exhaustive ordered partition."""
from pathlib import Path
import tempfile
import unittest

from report_himem_residency import bios_descriptor_span, fixed_ownership


class OwnershipTest(unittest.TestCase):
    def test_bios_descriptor_data_is_not_code(self):
        source = "\n".join((
            "move_gdt . . . L Near 100h _TEXT",
            "move_source_desc . . . L Near 110h _TEXT",
            "move_dest_desc . . . L Near 118h _TEXT",
            "validate_handle . . . P Near 0130 _TEXT 0010 Public",
        ))
        with tempfile.TemporaryDirectory() as temporary:
            listing = Path(temporary) / "himem.lst"
            listing.write_text(source)
            self.assertEqual(bios_descriptor_span(listing), (256, 304))
            for old, new in (("118h", "120h"), ("0130", "0132")):
                listing.write_text(source.replace(old, new))
                with self.assertRaises(ValueError):
                    bios_descriptor_span(listing)

    def test_partition_and_reversed_boundary(self):
        names = ("xms_control", "xms_hma_request", "xms_query_free", "xms_move",
                 "xms_umb_request", "resolve_move_address", "validate_handle")
        with tempfile.TemporaryDirectory() as temporary:
            listing = Path(temporary) / "himem.lst"
            listing.write_text("\n".join(
                f"{name} . . . P Near {offset:04X} _TEXT 0010 Public"
                for name, offset in zip(names, range(16, 128, 16))))
            ranges = fixed_ownership(listing, 128)
            self.assertEqual(len(ranges), 8)
            self.assertEqual(sum(stop - start for _, start, stop in ranges), 128)
            self.assertEqual(ranges[0][1], 0)
            self.assertEqual(ranges[-1][2], 128)
            with self.assertRaises(ValueError):
                fixed_ownership(listing, 100)
            listing.write_text(listing.read_text().replace("xms_move", "missing_move"))
            with self.assertRaises(KeyError):
                fixed_ownership(listing, 128)


if __name__ == "__main__":
    unittest.main()
