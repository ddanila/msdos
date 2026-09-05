#!/usr/bin/env python3
"""Check the isolated payload's linker-derived offset relocation model."""
from pathlib import Path
import tempfile
import unittest

from build_bios_high_payload import build, offset_fixups, rebase


class PayloadTests(unittest.TestCase):
    def test_linked_body_and_independent_origins(self):
        with tempfile.TemporaryDirectory(prefix="msdos-high-payload-test-") as scratch:
            report = build(Path(scratch))
            self.assertFalse(report["installed"])
            self.assertTrue(report["runtime_bindings_required"])
            self.assertEqual(report["bytes"] - report["service_bytes"], 60)
            self.assertEqual(len(report["runtime_slots"]), 20)
            self.assertGreater(len(report["offset_fixups"]), 0)
            self.assertEqual(report["verified_origins"], [0, 1, 16, 0x123, 0x4000])
            payload = (Path(scratch) / "bios-high.bin").read_bytes()
            for slot in report["runtime_slots"].values():
                self.assertGreaterEqual(slot["offset"], report["service_bytes"])
                self.assertEqual(payload[slot["offset"]:slot["offset"] + slot["size"]],
                                 bytes(slot["size"]))

    def test_word_carry_and_adjacent_fixups(self):
        base = bytes.fromhex("ff001234")
        shifted = bytes.fromhex("00011334")
        self.assertEqual(offset_fixups(base, shifted), [0, 2])
        self.assertEqual(rebase(base, [0, 2], 1), shifted)

    def test_non_offset_changes_rejected(self):
        for before, after in ((b"a", b"b"), (b"ab", b"ad"), (b"a", b"ab")):
            with self.assertRaises(ValueError):
                offset_fixups(before, after)

    def test_bad_rebases_rejected(self):
        for data, offsets, origin in ((b"abcd", [1, 2], 0),
                                      (b"ab", [1], 0),
                                      (b"\xff\xff", [0], 1),
                                      (b"ab", [], 0xffff),
                                      (b"ab", [], -1)):
            with self.assertRaises(ValueError):
                rebase(data, offsets, origin)


if __name__ == "__main__":
    unittest.main()
