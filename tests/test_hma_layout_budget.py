#!/usr/bin/env python3
"""Check the shared boot/cache/shell HMA budget, including overflow rejection."""

import unittest

from report_dos_bios_residency import hma_layout


class HmaBudgetTests(unittest.TestCase):
    def test_joint_candidate_reserves_cache_and_both_service_owners(self):
        rows = hma_layout(0x9D10, 7988, 5220, 2447,
                          manager_bytes=1672, shell_service_bytes=2451)
        self.assertEqual(rows[2][1:], (0xB174, 0xB7FC))
        self.assertEqual(rows[3][2] - rows[3][1], 7988)
        self.assertEqual(rows[-3][1:], (0xE0BF, 0xEA52))
        self.assertEqual(rows[-2][2] - rows[-2][1], 5534)
        self.assertTrue(all(a[2] == b[1] for a, b in zip(rows, rows[1:])))

    def test_joint_services_cannot_silently_displace_larger_cache(self):
        # 29 buffers still use one hash bucket. Current placement fits;
        # the joint candidate must reject its new reservations, not shrink cache.
        cache = 29 * (512 + 20) + 8
        self.assertEqual(hma_layout(0x9D10, cache, 5220, 2447)[-2][2]
                         - hma_layout(0x9D10, cache, 5220, 2447)[-2][1], 2209)
        with self.assertRaises(ValueError):
            hma_layout(0x9D10, cache, 5220, 2447,
                       manager_bytes=1672, shell_service_bytes=2451)

    def test_negative_proposed_service_sizes(self):
        for kwargs in ({"manager_bytes": -1}, {"shell_service_bytes": -1}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                hma_layout(0x9D10, 7988, 5220, 2447, **kwargs)

    def test_contiguous_byte_granular_placement(self):
        rows = hma_layout(0x9900, 7988, 5220, 2447)
        self.assertTrue(all(a[2] == b[1] for a, b in zip(rows, rows[1:])))
        self.assertEqual(rows[3][2] - rows[3][1], 2447)
        self.assertEqual(sum(end - start for _, start, end in rows), 65520)

    def test_reservations_are_charged_once(self):
        base = hma_layout(0x9900, 7988)[-2]
        composed = hma_layout(0x9900, 7988, 5220, 2447)[-2]
        self.assertEqual((base[2] - base[1]) - (composed[2] - composed[1]), 7667)

    def test_exact_fit(self):
        self.assertEqual(hma_layout(0xFF00, 0xF0)[-2][1:], (0xFFF0, 0xFFF0))

    def test_pre_setver_development_budget(self):
        rows = hma_layout(0x9A80, 15 * (512 + 20) + 8, 5220, 2447)
        self.assertEqual(rows[-2][1:], (0xD7A7, 0xFFF0))
        self.assertEqual(rows[-2][2] - rows[-2][1], 10313)

    def test_retained_setver_development_budget(self):
        rows = hma_layout(0x9D10, 15 * (512 + 20) + 8, 5220, 2447)
        self.assertEqual(rows[-2][1:], (0xDA37, 0xFFF0))
        self.assertEqual(rows[-2][2] - rows[-2][1], 9657)

    def test_full_xms_entry_callback_budget(self):
        rows = hma_layout(0x9D60, 15 * (512 + 20) + 8, 5220, 2447)
        self.assertEqual(rows[-2][1:], (0xDA87, 0xFFF0))
        self.assertEqual(rows[-2][2] - rows[-2][1], 9577)

    def test_overflow_in_each_stage(self):
        for buffers, bios, command in ((0, 241, 0), (241, 0, 0), (0, 0, 241)):
            with self.subTest(buffers=buffers, bios=bios, command=command):
                with self.assertRaises(ValueError):
                    hma_layout(0xFF00, buffers, bios, command)

    def test_negative_allocations(self):
        for buffers, bios, command in ((-1, 0, 0), (0, -1, 0), (0, 0, -1)):
            with self.assertRaises(ValueError):
                hma_layout(0x1000, buffers, bios, command)

    def test_invalid_dos_boundary(self):
        for sysbuf in (0, 15, 0xFFF1, 0x10000):
            with self.assertRaises(ValueError):
                hma_layout(sysbuf, 0)


if __name__ == "__main__":
    unittest.main()
