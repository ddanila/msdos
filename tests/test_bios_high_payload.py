#!/usr/bin/env python3
"""Check the isolated payload's linker-derived offset relocation model."""
from pathlib import Path
import tempfile
import unittest

from build_bios_high_payload import build, offset_fixups, rebase, boot_policy, prepare


class PayloadTests(unittest.TestCase):
    def test_packed_headers_preserve_chain_and_fixed_vdisk_anchor(self):
        from build_bios_low_image import build as build_low
        from report_dos_bios_residency import bios_core_partition, parse_map
        import struct
        with tempfile.TemporaryDirectory(prefix="msdos-packed-headers-test-") as scratch:
            directory = Path(scratch)
            low = build_low(directory, tail_body=True, dispatch=True, characters=True,
                            retire_characters=True, pack_headers=True)
            symbols = low["symbols"]
            binary = (directory / "MSBIO.BIN").read_bytes()
            self.assertEqual(symbols["VDISK_AREA"], 0x100)
            self.assertLess(symbols["CONHEADER"], symbols["OLD13"])
            self.assertLess(symbols["NUMBER_OF_SEC"], 0x100)
            self.assertGreaterEqual(symbols["DSKTBL"], symbols["END$"])
            names = ("CONHEADER", "AUXDEV2", "PRNDEV2", "TIMDEV", "DSKDEV", "COM1DEV",
                     "LPT1DEV", "LPT2DEV", "LPT3DEV", "COM2DEV", "COM3DEV", "COM4DEV")
            for index, name in enumerate(names):
                address = symbols[name]
                self.assertLess(address, symbols["OLD13"])
                target = symbols[names[index + 1]] if index + 1 < len(names) else 0xffff
                self.assertEqual(struct.unpack_from("<HH", binary, address), (target, 0x70))
            _, linked = parse_map(directory / "msBIO.map")
            rows = bios_core_partition(linked)
            self.assertEqual(sum(end-start for _, start, end, _ in rows),
                             symbols["BIOS_IOCTL_LOW_START"] - symbols["BIO001S"])

    def test_character_retirement_keeps_low_state_and_clock_hook(self):
        from build_bios_low_image import build as build_low
        from build_bios_activation_fixture import write_fixture
        from report_dos_bios_residency import character_partition, parse_map
        with tempfile.TemporaryDirectory(prefix="msdos-char-retirement-test-") as scratch:
            directory = Path(scratch)
            low = build_low(directory, tail_body=True, dispatch=True, characters=True,
                            retire_characters=True)
            high = build(directory / "high", directory, dispatch=True, characters=True)
            write_fixture(directory, low, high)
            symbols = low["symbols"]
            _, linked_symbols = parse_map(directory / "msBIO.map")
            rows = character_partition(linked_symbols)
            self.assertEqual(len(rows), 4)
            self.assertTrue(all(start >= symbols["END$"] for _, start, _, _ in rows))
            for name in ("CBREAK", "TIME_TO_TICKS", "HAVECMOSCLOCK", "BINTOBCD", "DAYCNTTODAY"):
                self.assertLess(symbols[name], symbols["END$"])
            for name in ("CON$READ", "AUX$READ", "PRN$WRIT", "TIM$WRIT", "BIOS_CLOCK_BODY_TICKS"):
                self.assertGreaterEqual(symbols[name], symbols["END$"])
                self.assertLess(symbols[name], symbols["BIOS_SERVICE_START"])
            self.assertIn(f"OLD_SERVICE_START equ {symbols['CON$READ']}",
                          (directory / "activation-defs.inc").read_text())
            binding = (directory / "activation-bind-low.inc").read_text()
            self.assertIn(f"add ax,{high['exports']['TIME_TO_TICKS']}", binding)
            self.assertIn(f"mov [es:{symbols['BIOS_HIGH_TIME_TO_TICKS']}],ax", binding)

    def test_complete_character_owner_links_without_low_completion_aliases(self):
        from build_bios_low_image import build as build_low
        from build_bios_activation_fixture import CHARACTER_TARGETS
        with tempfile.TemporaryDirectory(prefix="msdos-high-characters-test-") as scratch:
            directory = Path(scratch)
            build_low(directory, dispatch=True)
            base = build(directory / "base", directory, dispatch=True)
            report = build(directory / "characters", directory, dispatch=True, characters=True)
            self.assertEqual(report["bytes"] - base["bytes"], 960)
            self.assertEqual(len(report["runtime_slots"]), 32)
            self.assertEqual(report["verified_origins"], [0, 1, 16, 0x123, 0x4000])
            for name in (*CHARACTER_TARGETS, "RDEXIT", "BIOS_CHAR_EXIT", "BIOS_CHAR_GETDX"):
                self.assertIn(name, report["exports"])
                self.assertNotIn(name, report["low_bindings"])
            self.assertIn("HAVECMOSCLOCK", report["low_bindings"])
            self.assertIn("BINTOBCD", report["low_bindings"])
            payload = (directory / "characters/bios-high.bin").read_bytes()
            for entry, slot in (("BIOS_CHAR_BINTOBCD", "BINTOBCD"),
                                ("BIOS_CHAR_DAYCNTTODAY", "DAYCNTTODAY")):
                offset = report["exports"][entry]
                # FF /6 direct PUSH through DS, not an inferred CS override.
                self.assertEqual(payload[offset:offset + 4], b"\xff\x36" + report["low_bindings"][slot].to_bytes(2, "little"))

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
