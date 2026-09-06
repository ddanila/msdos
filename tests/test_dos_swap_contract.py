#!/usr/bin/env python3
"""Guard the public SDA extent and its overlapping internal stack storage."""
import unittest

from report_dos_bios_residency import swap_contract


class SwapContractTests(unittest.TestCase):
    def symbols(self, shift=0):
        return {name: value + shift for name, value in {
            "SWAP_START": 0x330, "Swap_Always": 0x34A,
            "RENAMEDMA": 0x69E, "AuxStack": 0x81E,
            "DskStack": 0x99E, "IOStack": 0xB1E,
            "SWAP_END": 0xB2A, "MSDAT001E": 0xB2B,
        }.items()}

    def test_normal_and_shifted(self):
        for shift in (0, 0x100):
            with self.subTest(shift=shift):
                result = swap_contract(self.symbols(shift))
                self.assertEqual(result["total"], 2042)
                self.assertEqual(result["always"], 26)
                self.assertEqual(result["indos"], 2016)
                self.assertEqual(result["stacks"], 1152)
                self.assertEqual(result["start"], 0x330 + shift)

    def test_odd_extent_uses_reserved_byte(self):
        symbols = self.symbols()
        symbols["SWAP_END"] += 1
        symbols["MSDAT001E"] += 1
        self.assertEqual(swap_contract(symbols)["total"], 2044)
        symbols["MSDAT001E"] -= 1
        with self.assertRaises(ValueError):
            swap_contract(symbols)

    def test_missing_boundary(self):
        symbols = self.symbols()
        del symbols["RENAMEDMA"]
        with self.assertRaisesRegex(ValueError, "missing"):
            swap_contract(symbols)

    def test_stack_overlap_or_size_change(self):
        for value in (0x69E, 0x81F):
            symbols = self.symbols()
            symbols["AuxStack"] = value
            with self.assertRaises(ValueError):
                swap_contract(symbols)

    def test_flag_collision(self):
        symbols = self.symbols(0x8000)
        symbols["SWAP_START"] = 0
        with self.assertRaisesRegex(ValueError, "flag bit"):
            swap_contract(symbols)


if __name__ == "__main__":
    unittest.main()
