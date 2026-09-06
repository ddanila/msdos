#!/usr/bin/env python3
"""Guard the mixed BIOS data budget and its fixed/public layout contracts."""
import unittest

from report_dos_bios_residency import bios_core_partition


class CorePartitionTests(unittest.TestCase):
    def symbols(self):
        return dict(BIO001S=3, DSKTBL=3, OLD13=0xB0, NUMBER_OF_SEC=0xC2,
                    VDISK_AREA=0x100, CONHEADER=0x16E, NEXT2F_13=0x248,
                    ACCESSCOUNT=0x250, ERRIN=0x26F, ERROUT=0x278, NUMERR=9,
                    DISKSECTOR=0x284, FDRIVE1=0x48A, FDRIVE2=0x4EE,
                    FDRIVE3=0x552, FDRIVE4=0x5B6, SM92=0x614,
                    BIOS_IOCTL_LOW_START=0x62A)

    def test_exact_complete_partition(self):
        rows = bios_core_partition(self.symbols())
        self.assertEqual([end - start for _, start, end, _ in rows],
                         [173, 19, 61, 108, 2, 218, 8, 31, 18, 3, 512, 400, 22])
        self.assertEqual(sum(end - start for _, start, end, _ in rows), 1575)
        self.assertTrue(all(a[2] == b[1] for a, b in zip(rows, rows[1:])))

    def test_table_shrinking_does_not_move_fixed_tail(self):
        symbols = self.symbols()
        symbols["OLD13"] -= 16
        symbols["NUMBER_OF_SEC"] -= 16
        rows = bios_core_partition(symbols)
        self.assertEqual(rows[2][2] - rows[2][1], 77)
        self.assertEqual(sum(end - start for _, start, end, _ in rows), 1575)

    def test_repacked_tail_is_not_a_fixed_absolute_layout(self):
        symbols = self.symbols()
        for key in ("DISKSECTOR", "FDRIVE1", "FDRIVE2", "FDRIVE3",
                    "FDRIVE4", "SM92", "BIOS_IOCTL_LOW_START"):
            symbols[key] += 4
        rows = bios_core_partition(symbols)
        self.assertEqual(rows[10][2] - rows[10][1], 512)
        self.assertEqual(rows[11][2] - rows[11][1], 400)

    def test_missing_symbol(self):
        symbols = self.symbols()
        del symbols["FDRIVE3"]
        with self.assertRaisesRegex(ValueError, "missing"):
            bios_core_partition(symbols)

    def test_changed_fixed_or_public_layout_rejected(self):
        for name in ("VDISK_AREA", "CONHEADER", "FDRIVE1", "FDRIVE2",
                     "FDRIVE3", "FDRIVE4", "SM92", "DSKTBL", "NUMERR"):
            with self.subTest(name=name):
                symbols = self.symbols()
                symbols[name] += 1
                with self.assertRaises(ValueError):
                    bios_core_partition(symbols)

    def test_reversed_interval_rejected(self):
        symbols = self.symbols()
        symbols["NUMBER_OF_SEC"] = 0x101
        with self.assertRaisesRegex(ValueError, "reversed"):
            bios_core_partition(symbols)


if __name__ == "__main__":
    unittest.main()
