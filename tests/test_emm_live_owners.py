#!/usr/bin/env python3
"""Synthetic bounds and ownership failures for the runtime XMS census."""
import struct
import unittest
from pathlib import Path

from capture_emm_live_owners import descriptor, verify_owners
from report_emm386_residency import Segment, Symbol, relocation_budget


class LiveOwnerTest(unittest.TestCase):
    def test_selector_contract_matches_production_build(self):
        root = Path(__file__).resolve().parents[1]
        source = (root / "src/MEMM/MEMM/VDMSEL.INC").read_text(encoding="latin-1")
        production = source.split("; The active LDT is explicitly null", 1)[1].split("endif", 1)[0]
        for name, value in (("TSS_GSEL", "020"), ("VDMC_GSEL", "038"),
                            ("VDMD_GSEL", "040"), ("VDMS_GSEL", "048")):
            self.assertRegex(production, rf"{name}\s+equ\s+{value}h")
        self.assertRegex(source, r"IDTD_GSEL\s+equ\s+010h")
        self.assertIn("-DNoBugMode", (root / "mk/memm.mk").read_text())

    def fixture(self):
        segments = [Segment(name, paragraph, 0, size) for name, paragraph, size in (
            ("_DATA", 0x20, 396), ("_TEXT", 0x44, 0), ("VDATA", 0x4d0, 49152),
            ("PAGESEG", 0x10d1, 28672), ("IDT", 0x17d1, 960),
            ("TSS", 0x180d, 8297), ("LAST", 0x1a14, 0))]
        symbols = [Symbol(paragraph, offset, name, "fixture") for name, paragraph, offset in (
            ("LAST_start", 0x1a14, 0), ("Page_Area", 0x10d1, 0),
            ("_total_pages", 0x20, 0x96), ("_save_map", 0x20, 0x98),
            ("_emm_brk", 0x20, 0x9a))]
        symbols.extend(Symbol(0x20, offset, name, "fixture") for name, offset in (
            ("_handle_table_size", 0xe0), ("_altreg_count", 0xe1),
            ("_physical_page_count", 0xe2), ("_physical_page_exception_count", 0xe3),
            ("DMA_PAGE_COUNT", 0xe4)))
        ram = bytearray(4 * 1024 * 1024)
        budget = relocation_budget(segments, symbols)
        struct.pack_into("<BHH", ram, 0x1000, 1, 64, 1024 + budget["reserved"] // 1024)
        struct.pack_into("<HHH", ram, 0x2296, 64, 0x400, 0x400 + 1904)
        ram[0x22e0:0x22e5] = bytes((64, 7, 6, 0, 1))
        tail = 0x210000
        page = (tail + 4096) & ~4095
        code = (tail + budget["page_request"] + 3) & ~3
        original_page = ((0x200 + 0x10d1) * 16 + 4095) & ~4095
        for selector, base, size, access in (
            (0x10, page + (0x200 + 0x17d1) * 16 - original_page, 960, 0x92),
            (0x20, page + (0x200 + 0x180d) * 16 - original_page, 8297, 0x8b),
            (0x38, code, 65536, 0x9a), (0x40, 0x2200, 65536, 0x93),
            (0x48, 0x2d70, 512, 0x92)):
            ram[0x3000 + selector:0x3008 + selector] = struct.pack(
                "<HHBBBB", size - 1, base & 0xffff, base >> 16, access, 0, 0)
        return ram, (0x3000, page, 0x200, 0x100, segments, symbols, 0)

    def test_complete_live_layout(self):
        ram, args = self.fixture()
        result = verify_owners(ram, *args)
        self.assertEqual(result["low_tables"]["size"], 1904)
        self.assertEqual(result["unused_end"] - result["unused_start"], result["budget"]["unused"])

    def test_rejects_wrong_lock_copy_and_low_table_boundaries(self):
        for offset, value in ((0x1000, 0), (0x303a, 0), (0x3042, 1),
                              (0x229b, 0xff), (0x3025, 0), (0x22e2, 28)):
            ram, args = self.fixture()
            ram[offset] = value
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                verify_owners(ram, *args)

    def test_rejects_wrong_cr3_and_tail_size(self):
        ram, args = self.fixture()
        with self.assertRaises(ValueError):
            verify_owners(ram, args[0], args[1] + 4096, *args[2:])
        ram[0x1003] += 1
        with self.assertRaises(ValueError):
            verify_owners(ram, *args)

    def test_descriptor_granularity_and_length(self):
        self.assertEqual(descriptor(bytes.fromhex("ffff34125692cf78")),
                         {"base": 0x78561234, "size": 0x100000000, "access": 0x92})
        with self.assertRaises(ValueError):
            descriptor(b"short")


if __name__ == "__main__":
    unittest.main()
