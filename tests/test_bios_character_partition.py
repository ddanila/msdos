#!/usr/bin/env python3
"""Check BIOS character ownership without equating inventory with savings."""
import unittest

from report_dos_bios_residency import character_partition


class CharacterPartitionTests(unittest.TestCase):
    def symbols(self, shift=0):
        return {name: value + shift for name, value in {
            "CON$READ": 0x82A, "CBREAK": 0x8FB, "INTRET": 0x901,
            "AUX$READ": 0x902, "PRN$WRIT": 0x998,
            "HaveCMOSClock": 0xA60, "TIM$WRIT": 0xA73,
            "Set_ID_Flag": 0xB6E, "Fat_12_ID": 0xB6F,
        }.items()}

    def test_normal_and_shifted_owners(self):
        for shift in (0, 0x190):
            with self.subTest(shift=shift):
                rows = character_partition(self.symbols(shift))
                self.assertEqual([end - start for _, start, end, _ in rows],
                                 [209, 7, 150, 200, 19, 251, 1])
                self.assertEqual(sum(end - start for _, start, end, role in rows
                                     if role == "service candidate"), 810)
                self.assertTrue(all(a[2] == b[1] for a, b in zip(rows, rows[1:])))

    def test_missing_boundary_rejected(self):
        symbols = self.symbols()
        del symbols["Set_ID_Flag"]
        with self.assertRaisesRegex(ValueError, "missing"):
            character_partition(symbols)

    def test_reversed_body_rejected(self):
        symbols = self.symbols()
        symbols["TIM$WRIT"] = symbols["Set_ID_Flag"] + 1
        with self.assertRaisesRegex(ValueError, "ordered"):
            character_partition(symbols)

    def test_changed_interrupt_or_disk_boundary_rejected(self):
        for name in ("INTRET", "Fat_12_ID"):
            with self.subTest(name=name):
                symbols = self.symbols()
                symbols[name] += 1
                with self.assertRaises(ValueError):
                    character_partition(symbols)


if __name__ == "__main__":
    unittest.main()
