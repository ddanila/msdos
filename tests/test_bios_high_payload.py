#!/usr/bin/env python3
"""Check the isolated payload's linker-derived offset relocation model."""
from pathlib import Path
import tempfile
import unittest

from build_bios_high_payload import build, offset_fixups, rebase, boot_policy, prepare


class PayloadTests(unittest.TestCase):
    def test_complete_dispatch_owner_and_independent_origins(self):
        with tempfile.TemporaryDirectory(prefix="msdos-high-dispatch-test-") as scratch:
            directory = Path(scratch)
            base = build(directory / "base")
            report = build(directory / "dispatch", dispatch=True)
            self.assertEqual(report["bytes"] - base["bytes"], 478)
            self.assertEqual(report["low_table_bytes"], 173)
            self.assertEqual(report["table_bytes"], 346)
            self.assertEqual(len(report["runtime_slots"]), 24)
            self.assertEqual(len(report["offset_fixups"]) - len(base["offset_fixups"]), 6)
            self.assertEqual(report["verified_origins"], [0, 1, 16, 0x123, 0x4000])
            exports = report["exports"]
            self.assertEqual(exports["BIOS_DISPATCH_END"] - exports["BIOS_DISPATCH_START"], 122)
            self.assertEqual(exports["BIOS_DISPATCH_TABLES"] + report["table_bytes"], report["bytes"])
            payload = (directory / "dispatch/bios-high.bin").read_bytes()
            self.assertEqual(payload[exports["BIOS_DISPATCH_TABLES"]:], bytes(346))

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
            for keep in (False, True):
                for cpu in (False, True):
                    low = bytearray(0x10000)
                    for patch in report["boot_patches"].values():
                        original = bytes.fromhex(patch["low_original"])
                        enabled = keep if patch["policy"] == "keep_96tpi" else cpu
                        low[patch["low_offset"]:patch["low_offset"] + len(original)] = (
                            original if enabled else b"\x90" * len(original))
                    policies = boot_policy(low, report)
                    self.assertEqual(policies, {"keep_96tpi": keep, "cpu386": cpu})
                    expected = bytearray(rebase(payload, report["offset_fixups"], 0x123))
                    for patch in report["boot_patches"].values():
                        if not policies[patch["policy"]]:
                            expected[patch["offset"]:patch["offset"] + patch["size"]] = b"\x90" * patch["size"]
                    self.assertEqual(prepare(payload, report, 0x123, **policies), expected)
            with self.assertRaises(ValueError):
                boot_policy(b"", report)
            first = report["boot_patches"]["DISKIO_PATCH"]
            original = bytes.fromhex(first["low_original"])
            low[first["low_offset"]:first["low_offset"] + len(original)] = b"\x90" * len(original)
            with self.assertRaises(ValueError):
                boot_policy(low, report)  # one purged site among retained sites
            low[first["low_offset"]:first["low_offset"] + len(original)] = original
            low[first["low_offset"]] ^= 1
            with self.assertRaises(ValueError):
                boot_policy(low, report)
            with self.assertRaises(ValueError):
                prepare(payload + b"x", report, 0, keep_96tpi=True, cpu386=True)
            with self.assertRaises(ValueError):
                prepare(payload, report, 0, keep_96tpi=1, cpu386=True)

            # Demonstrate sensitivity to the wrong order: fixups overlap the
            # expanded 96-TPI instructions, so NOP-then-rebase is not equivalent.
            patched = prepare(payload, report, 0, keep_96tpi=False, cpu386=True)
            wrong = rebase(patched, report["offset_fixups"], 0x123)
            self.assertNotEqual(wrong, prepare(payload, report, 0x123, keep_96tpi=False, cpu386=True))

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
