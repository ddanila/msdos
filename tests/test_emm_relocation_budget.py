#!/usr/bin/env python3
"""Check the linked model of EMM386's reserved XMS relocation tail."""

import unittest

from report_emm386_residency import (
    Segment, Symbol, dynamic_table_sizes, high_data_capacity, relocation_budget,
)


class RelocationBudgetTest(unittest.TestCase):
    def test_default_and_maximum_table_objects(self):
        default = sum(size for size, _ in dynamic_table_sizes(64, 7, 64, 6, 0, 1))
        maximum = sum(size for size, _ in dynamic_table_sizes(255, 254, 2048, 52, 20, 16))
        self.assertEqual(default, 1904)
        self.assertEqual(maximum, 48383)
        self.assertEqual(high_data_capacity(default, 16989),
                         {"request": 1907, "shortfall": 0, "extra_pages": 0})
        self.assertEqual(high_data_capacity(maximum, 16989),
                         {"request": 48386, "shortfall": 31397, "extra_pages": 8})

    def test_capacity_rounding_and_rejection(self):
        self.assertEqual(high_data_capacity(4093, 4096)["extra_pages"], 0)
        self.assertEqual(high_data_capacity(4094, 4096)["extra_pages"], 1)
        self.assertEqual(high_data_capacity(4093, 0)["extra_pages"], 1)
        self.assertEqual(high_data_capacity(4094, 0)["extra_pages"], 2)
        for payload, unused in ((0, 0), (65533, 0), (1, -1)):
            with self.assertRaises(ValueError):
                high_data_capacity(payload, unused)

    def test_context_padding_is_charged_for_every_register_set(self):
        sizes = dict((name, size) for size, name in dynamic_table_sizes(2, 3, 0, 5, 0, 1))
        self.assertEqual(sizes["normal plus alternate register sets"], 4 * 13)

    def budget(self, page_span=0x9430, text_paras=0x48b):
        segments = [Segment("PAGESEG", 0x1000, 0, 0),
                    Segment("LAST", 0x1000 + page_span // 16, 0, 0),
                    Segment("_TEXT", 0x40, 8, 0),
                    Segment("VDATA", 0x40 + text_paras, 12, 0)]
        symbols = [Symbol(segments[1].paragraph, page_span % 16, "LAST_start", "test")]
        return relocation_budget(segments, symbols)

    def test_reference_linked_span(self):
        self.assertEqual(self.budget(), {
            "reserved": 77824, "page_request": 42032,
            "text_request": 18627, "unused": 17165})

    def test_larger_text_consumes_slack_without_new_reservation(self):
        budget = self.budget(text_paras=0x496)
        self.assertEqual(budget["reserved"], 77824)
        self.assertEqual(budget["text_request"], 18803)
        self.assertEqual(budget["unused"], 16989)

    def test_word_overflow_is_not_reported_as_capacity(self):
        for kwargs in ({"page_span": 0xf000}, {"text_paras": 0x1000},
                       {"page_span": 0}, {"text_paras": 0}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                self.budget(**kwargs)

    def test_paragraph_offsets_follow_actual_loader_formula(self):
        # The text copy uses segment bases, not linked offsets. Its extra
        # paragraph already covers the nonzero combined-segment offsets.
        self.assertEqual(self.budget(text_paras=64)["text_request"], 1043)
        self.assertEqual(self.budget(page_span=4096)["page_request"], 8192)
        self.assertEqual(self.budget(page_span=4097)["page_request"], 8193)


if __name__ == "__main__":
    unittest.main()
