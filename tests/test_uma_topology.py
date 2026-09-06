#!/usr/bin/env python3
"""ROM evidence cannot by itself qualify a page as available UMB."""

import unittest
from capture_uma_topology import BASE, END, page_inventory, rom_inventory


class ROMInventoryTest(unittest.TestCase):
    def test_complete_snapshot_required(self):
        with self.assertRaises(ValueError):
            rom_inventory(bytes(4096))

    def test_empty_pages_are_unproven(self):
        data = b"\xff" * (END - BASE)
        self.assertEqual(rom_inventory(data), [])
        pages = page_inventory(data, [])
        self.assertEqual(len(pages), 48)
        self.assertTrue(all(p["eligibility"] == "unproven" for p in pages))

    def test_rom_boundary_does_not_exclude_following_4k_page(self):
        data = bytearray(END - BASE)
        offset, length = 0x8000, 0x3000
        data[offset:offset + 3] = b"\x55\xaa\x18"
        data[offset + length - 1] = -sum(data[offset:offset + length]) & 255
        roms = rom_inventory(data)
        self.assertEqual(roms, [dict(start=0xC8000, end=0xCB000, length=length, checksum_valid=True)])
        pages = {p["start"]: p for p in page_inventory(data, roms)}
        self.assertEqual(pages[0xCA000]["eligibility"], "ROM-header overlap")
        self.assertEqual(pages[0xCB000]["eligibility"], "unproven")

    def test_bad_checksum_or_length_does_not_make_header_safe(self):
        for length in (0, 1, 255):
            data = bytearray(END - BASE)
            data[-2048:-2045] = bytes((0x55, 0xAA, length))
            data[-2045] = 1
            roms = rom_inventory(data)
            self.assertFalse(roms[0]["checksum_valid"])
            self.assertEqual(page_inventory(data, roms)[-1]["eligibility"], "ROM-header overlap")


if __name__ == "__main__":
    unittest.main()
