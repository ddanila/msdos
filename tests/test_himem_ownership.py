#!/usr/bin/env python3
"""Check that the HIMEM service inventory is an exhaustive ordered partition."""
from pathlib import Path
import tempfile
import unittest

from report_himem_residency import fixed_ownership


class OwnershipTest(unittest.TestCase):
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
