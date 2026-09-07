#!/usr/bin/env python3
"""Check the shared boot/cache/shell HMA budget, including overflow rejection."""

import unittest

from report_dos_bios_residency import hma_layout, whole_owner_inventory


class HmaBudgetTests(unittest.TestCase):
    def whole_inventory(self, **overrides):
        args = dict(bios_low=5152, command_data_start=0xB10,
                    command_symbols=dict(RES_CODE_END=0xA93, resmsgend=0xD42,
                                         resident_catalog_start=0xE30),
                    hma_tail=9577)
        args.update(overrides)
        return list(whole_owner_inventory(**args).values())

    def test_whole_bios_shell_inventory(self):
        self.assertEqual(self.whole_inventory(), [5152, 2451, 800, 1174])

    def test_retired_shell_counts_retained_entries_stack_and_state_once(self):
        symbols = dict(RES_CODE_END=0x1480, resmsgend=0x45A,
                       resident_catalog_start=0x540, shell_high_active=0x16B)
        self.assertEqual(self.whole_inventory(bios_low=3232, command_data_start=0x220,
                                              command_symbols=symbols, hma_tail=4422),
                         [3232, 288, 800, 102])
        with self.assertRaises(ValueError):
            self.whole_inventory(command_symbols=symbols, command_data_start=0x220,
                                 hma_tail=-1)

    def test_retired_shell_shared_budget(self):
        rows = hma_layout(0x9D60, 7988, 7744, 5078)
        self.assertEqual(rows[-2][1:], (0xEEAA, 0xFFF0))
        self.assertEqual(rows[-2][2] - rows[-2][1], 4422)

    def test_pipeline_state_shared_budget_and_low_inventory(self):
        rows = hma_layout(0x9D60, 7988, 7744, 5207)
        self.assertEqual(rows[-2][1:], (0xEF2B, 0xFFF0))
        symbols = dict(RES_CODE_END=0x1484, resmsgend=0x3DD,
                       resident_catalog_start=0x4C3, shell_high_active=0x16B)
        self.assertEqual(self.whole_inventory(bios_low=3232, command_data_start=0x220,
                                              command_symbols=symbols, hma_tail=4293),
                         [3232, 288, 675, 98])

    def test_pipeline_redirection_costs_only_high_storage(self):
        before = hma_layout(0x9D60, 7988, 7744, 5207)
        after = hma_layout(0x9D60, 7988, 7744, 5288)
        self.assertEqual(after[-2][1:], (0xEF7C, 0xFFF0))
        self.assertEqual(after[-2][1] - before[-2][1], 81)

    def test_cold_notice_is_not_live_shell_state_or_hma_storage(self):
        symbols = dict(RES_CODE_END=0x1476, resmsgend=0x3D5,
                       resident_catalog_start=0x464, shell_high_active=0x16B)
        self.assertEqual(self.whole_inventory(bios_low=3232, command_data_start=0x220,
                                              command_symbols=symbols, hma_tail=4212),
                         [3232, 288, 580, 112])
        rows = hma_layout(0x9D60, 7988, 7744, 5288)
        self.assertEqual(rows[-2][1:], (0xEF7C, 0xFFF0))

    def test_formatter_retirement_charges_low_reply_and_high_bindings(self):
        symbols = dict(RES_CODE_END=0x14CC, resmsgend=0x333,
                       resident_catalog_start=0x36D, shell_high_active=0x16B)
        self.assertEqual(self.whole_inventory(bios_low=3232, command_data_start=0x220,
                                              command_symbols=symbols, hma_tail=3879),
                         [3232, 288, 333, 26])
        rows = hma_layout(0x9D60, 7988, 7744, 5621)
        self.assertEqual(rows[-2][1:], (0xF0C9, 0xFFF0))
        self.assertEqual(((0x464+15)&~15)-((0x36D+15)&~15), 256)

    def test_whole_inventory_excludes_shell_stack_and_psp(self):
        # Growing only the excluded stack shifts the data and break together.
        symbols = dict(RES_CODE_END=0xA93, resmsgend=0xD52,
                       resident_catalog_start=0xE40)
        self.assertEqual(self.whole_inventory(command_data_start=0xB20,
                                              command_symbols=symbols),
                         self.whole_inventory())

    def test_whole_inventory_retains_formatter_state(self):
        # Moving the boundary between mutable shell and formatter state must
        # not make either disappear from the combined inventory.
        symbols = dict(RES_CODE_END=0xA93, resmsgend=0xD32,
                       resident_catalog_start=0xE30)
        self.assertEqual(self.whole_inventory(command_symbols=symbols),
                         self.whole_inventory())

    def test_whole_inventory_reports_shortage_not_zero_or_savings(self):
        self.assertEqual(self.whole_inventory(hma_tail=8402)[-1], -1)
        self.assertEqual(self.whole_inventory(hma_tail=8403)[-1], 0)
        self.assertEqual(self.whole_inventory(bios_low=5168)[-1], 1158)

    def test_whole_inventory_rejects_missing_or_reversed_owners(self):
        base = dict(RES_CODE_END=0xA93, resmsgend=0xD42,
                    resident_catalog_start=0xE30)
        for name in base:
            symbols = base.copy()
            del symbols[name]
            with self.subTest(missing=name), self.assertRaises(ValueError):
                self.whole_inventory(command_symbols=symbols)
        for kwargs in (dict(command_data_start=0xA92),
                       dict(command_data_start=0xD43), dict(bios_low=0),
                       dict(hma_tail=-1), dict(hma_tail=0xFFE1),
                       dict(command_symbols=dict(base, RES_CODE_END=0xFF)),
                       dict(command_symbols=dict(base, resident_catalog_start=0xD41))):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                self.whole_inventory(**kwargs)

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
