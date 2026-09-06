#!/usr/bin/env python3
"""Check owner accounting, including deliberate incomplete/oversized records."""

import unittest
from capture_system_owners import decode_rows
from report_dos_bios_residency import composed_ledger

CAPTURE = (
    "MCB 0312 0008 022C \n"
    "SUB 0313 0044 0314 00A2 \n"
    "SUB 03B6 0044 03B7 00F3 \n"
    "SUB 04AA 0042 04AB 0020 \n"
    "SUB 04CB 0053 04CC 0073 \n"
    "MCB 053F 0540 00E3 \n"
)


class OwnerTests(unittest.TestCase):
    def composed(self):
        return dict(vc_rows=[dict(name=name, segment=segment, size=1)
                             for name, segment in (("DOS 6.22", 112),
                                                   ("COMMAND", 1227), ("VC.COM", 1476))],
                    first_free=2271, ceiling=40896, largest=617984,
                    components={"HIMEM": 2592, "EMM386": 2016})

    def test_composed_boundary_ledger(self):
        owners = composed_ledger(self.composed(), 5152, 5632)
        self.assertEqual(owners["COMMAND owner span"], 3984)
        self.assertEqual(owners["VC to free"], 12720)
        self.assertEqual(sum(owners.values()), (2271 - 112) * 16)

    def test_composed_rejects_stale_managers_or_maps(self):
        snapshot = self.composed()
        snapshot["components"]["EMM386"] = 3888
        for data, bios, dos in ((snapshot, 5152, 5632),
                                (self.composed(), 8160, 5632),
                                (self.composed(), 5152, 4992)):
            with self.assertRaisesRegex(ValueError, "unaccounted"):
                composed_ledger(data, bios, dos)

    def test_pre_table_control_reconciles_without_double_counting(self):
        snapshot = self.composed()
        snapshot["components"]["EMM386"] = 3888
        for row in snapshot["vc_rows"][1:]:
            row["segment"] += 117
        snapshot["first_free"] += 117
        snapshot["largest"] -= 1872
        before = composed_ledger(snapshot, 5152, 5632)
        after = composed_ledger(self.composed(), 5152, 5632)
        self.assertEqual(sum(before.values()) - sum(after.values()), 1872)
        for owner in before.keys() - {"EMM386"}:
            self.assertEqual(before[owner], after[owner])

    def test_composed_rejects_missing_duplicate_and_unordered_owners(self):
        for change in (lambda rows: rows.pop(),
                       lambda rows: rows.append(rows[-1]),
                       lambda rows: rows[1].update(segment=1500)):
            snapshot = self.composed()
            change(snapshot["vc_rows"])
            with self.assertRaises(ValueError):
                composed_ledger(snapshot, 5152, 5632)

    def test_composed_rejects_wrong_free_extent(self):
        snapshot = self.composed()
        snapshot["largest"] += 16
        with self.assertRaisesRegex(ValueError, "largest block"):
            composed_ledger(snapshot, 5152, 5632)

    def test_composed_rejects_negative_owner(self):
        snapshot = self.composed()
        snapshot["components"]["HIMEM"] = -1
        with self.assertRaisesRegex(ValueError, "invalid low owner"):
            composed_ledger(snapshot, 5152, 5632)

    def test_complete_system_accounting(self):
        rows = decode_rows(CAPTURE)
        self.assertEqual(sum(row[3] * 16 for row in rows["SUB"]), 8832)
        self.assertEqual(8832 + len(rows["SUB"]) * 16, rows["MCB"][0][2] * 16)

    def test_missing_allocation_rejected(self):
        with self.assertRaises(ValueError):
            decode_rows(CAPTURE.replace("SUB 04CB 0053 04CC 0073 \n", ""))

    def test_oversized_allocation_rejected(self):
        with self.assertRaises(ValueError):
            decode_rows(CAPTURE.replace("04CC 0073", "04CC 0074"))

    def test_unknown_tail_preserved(self):
        rows = decode_rows(CAPTURE.replace("SUB 04CB 0053 04CC 0073", "UNCLASSIFIED 04CB 053F"))
        self.assertEqual(rows["UNCLASSIFIED"], [[0x4CB, 0x53F]])

    def test_bad_chain_rejected(self):
        with self.assertRaises(ValueError):
            decode_rows(CAPTURE.replace("MCB 053F", "MCB 0540"))

    def test_malformed_row_rejected(self):
        with self.assertRaises(ValueError):
            decode_rows(CAPTURE.replace("SUB 04CB", "SUB nope"))


if __name__ == "__main__":
    unittest.main()
