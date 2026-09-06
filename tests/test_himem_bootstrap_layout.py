import unittest
from unittest.mock import Mock, patch

from report_himem_residency import (
    BOOTSTRAP_PROCEDURES, PERMANENT_PROCEDURES, check_bootstrap_layout, paired_front_ownership,
    parse_symbols, transplant_counterfactual,
)


class BootstrapLayoutTests(unittest.TestCase):
    def test_dword_sequence_symbol_is_discoverable(self):
        path = Mock()
        path.read_text.return_value = "\n".join((
            "umb_remote_sequence . . DWord 00001234h _TEXT",
            "umb_remote_recovered . . Word 00001238h _TEXT",
            "umb_remote_packet . . Byte[24] 0000123Ah _TEXT",
        ))
        symbols, _ = parse_symbols(path)
        self.assertEqual(symbols["umb_remote_sequence"][0], 0x1234)
        self.assertEqual(symbols["umb_remote_recovered"][0], 0x1238)
        self.assertEqual(symbols["umb_remote_packet"], (0x123a, 24))

    def setUp(self):
        self.numbers = dict(HIMEM_PERMANENT_BYTES=2048, HIMEM_BOOTSTRAP_CODE_BYTES=1024,
                            HIMEM_HANDLES_OFFSET=3072)
        self.procedures = {name: 2048 + i * 16 for i, name in enumerate(BOOTSTRAP_PROCEDURES)}
        self.procedures.update({name: 16 + i * 16 for i, name in enumerate(PERMANENT_PROCEDURES)})

    def test_capacities_and_rounding(self):
        for count in (1, 8, 32, 127, 128):
            result = check_bootstrap_layout(self.numbers, self.procedures, count)
            self.assertEqual(result["retained_bootstrap_bytes"], ((1024 + count * 5 + 15) // 16) * 16)
            self.assertEqual(result["linked_boot_end"], 2048 + result["retained_bootstrap_bytes"])
            self.assertEqual(result["released_bytes"], 0)

    def test_wrong_boundaries(self):
        for key, value in (("HIMEM_PERMANENT_BYTES", 2049), ("HIMEM_HANDLES_OFFSET", 3071),
                           ("HIMEM_BOOTSTRAP_CODE_BYTES", 0)):
            with self.assertRaises(ValueError):
                check_bootstrap_layout(dict(self.numbers, **{key: value}), self.procedures, 32)
        for count in (0, 129):
            with self.assertRaises(ValueError):
                check_bootstrap_layout(self.numbers, self.procedures, count)

    def test_wrong_or_missing_procedure(self):
        for name, offset in ((BOOTSTRAP_PROCEDURES[0], 2047), (PERMANENT_PROCEDURES[0], 2048)):
            with self.assertRaises(ValueError):
                check_bootstrap_layout(self.numbers, dict(self.procedures, **{name: offset}), 32)
        with self.assertRaises(KeyError):
            check_bootstrap_layout(self.numbers, {}, 32)

    def test_staging_interface_remains_permanent(self):
        procedures = dict(self.procedures, private_bootstrap_stage=512, xms_stage_forward=768)
        check_bootstrap_layout(self.numbers, procedures, 32)
        for name in ("private_bootstrap_stage", "xms_stage_forward"):
            with self.assertRaises(ValueError):
                check_bootstrap_layout(self.numbers, dict(procedures, **{name: 2048}), 32)
        del procedures["xms_stage_forward"]
        with self.assertRaises(KeyError):
            check_bootstrap_layout(self.numbers, procedures, 32)


class PairedFrontTests(unittest.TestCase):
    def test_transplant_scenario_retains_transport_and_unknown_gate_costs(self):
        for staged in (False, True):
            for handoff in (False, True):
                report = self.report(staged=staged, handoff=handoff)
                scenario = report["transplant_counterfactual"]
                self.assertEqual(scenario["removed_linked_bytes"] + scenario["retained_linked_bytes"],
                                 report["layout"]["permanent_bytes"])
                self.assertIsNone(scenario["replacement_gate_bytes"])
                self.assertIsNone(scenario["final_low_bytes"])
                self.assertNotIn("High allocator transport", scenario["removed_groups"])
                self.assertNotIn("UMB handoff transport and publication state", scenario["removed_groups"])
                self.assertNotIn("Front alignment", scenario["removed_groups"])
                self.assertIn("Private UMB registration", scenario["removed_groups"])
                self.assertEqual("Bootstrap staging transaction" in scenario["removed_groups"], staged)

    def test_transplant_scenario_rejects_missing_and_duplicate_owners(self):
        rows = self.report()["front"]
        with self.assertRaises(ValueError):
            transplant_counterfactual(rows + [rows[0]])
        with self.assertRaises(ValueError):
            transplant_counterfactual([r for r in rows if r["owner"] != "UMB records"])

    def report(self, *, staged=True, handoff=False, bad=None, alignment=10):
        names = ["strategy", "multiplex_handler", "private_register", "int15_handler",
                 "xms_control", "xms_hma_request", "xms_global_enable", "private_bootstrap_layout"]
        if staged:
            names += ["private_bootstrap_stage", "xms_stage_forward"]
        names += ["xms_remote_owned", "xms_owner_handle", "xms_move", "xms_umb_request",
                  "resolve_move_address", "copy_move_blocks", "kb_to_physical"]
        if handoff:
            names += ["umb_remote_state"]
        addresses = {name: (i + 1) * 16 for i, name in enumerate(names)}
        if bad:
            addresses[bad] = 1
        path = Mock()
        path.read_text.return_value = "\n".join(
            f"{name} . . P Near {offset:04X} _TEXT" for name, offset in addresses.items())
        records = (len(names) + 1) * 16
        symbols = dict(umb_count=(records, 1), umb_blocks=(records + 2, 128))
        end = records + 130 + alignment
        with patch("report_himem_residency.parse_symbols", return_value=(symbols, {})), \
             patch("report_himem_residency.bootstrap_layout", return_value=dict(permanent_bytes=end)):
            return paired_front_ownership(path, 32)

    def test_complete_partition_with_and_without_staging(self):
        for staged in (False, True):
            report = self.report(staged=staged)
            rows = report["front"]
            self.assertEqual(sum(row["bytes"] for row in rows), report["layout"]["permanent_bytes"])
            self.assertEqual(rows[0]["start"], 0)
            self.assertTrue(all(a["end"] == b["start"] for a, b in zip(rows, rows[1:])))
            self.assertEqual(any(row["owner"] == "Bootstrap staging transaction" for row in rows), staged)
            self.assertIsNone(report["projected_release_bytes"])
            self.assertIsNone(report["projected_low_bytes"])

    def test_reordered_boundary_rejected(self):
        with self.assertRaises(ValueError):
            self.report(bad="xms_umb_request")

    def test_handoff_is_not_charged_to_address_helper(self):
        rows = self.report(handoff=True)["front"]
        by_name = {row["owner"]: row for row in rows}
        self.assertEqual(by_name["Physical address helper"]["bytes"], 16)
        self.assertEqual(by_name["UMB handoff transport and publication state"]["bytes"], 16)
        self.assertIn("not a live mirror", by_name["UMB records"]["contract"])
        self.assertEqual(sum(row["bytes"] for row in rows), rows[-1]["end"])
        with self.assertRaises(ValueError):
            self.report(handoff=True, bad="umb_remote_state")

    def test_zero_alignment_and_overrun(self):
        self.assertEqual(self.report(alignment=0)["front"][-1]["bytes"], 0)
        with self.assertRaises(ValueError):
            self.report(alignment=-1)


if __name__ == "__main__":
    unittest.main()
