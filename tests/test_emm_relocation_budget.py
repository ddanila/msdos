#!/usr/bin/env python3
"""Check the linked model of EMM386's reserved XMS relocation tail."""

import unittest

from report_emm386_residency import Segment, Symbol, relocation_budget


class RelocationBudgetTest(unittest.TestCase):
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
