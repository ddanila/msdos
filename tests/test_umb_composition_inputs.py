"""Keep diagnostic faults and mismatched binaries out of VC comparisons."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from test_umb_subpage_composition import paired_inputs, sha, xms_summary


class PairedInputTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.record = dict.fromkeys(("common_xms_entry", "reclaim_bootstrap", "high_tables",
                                     "fine_umbs", "dos_high"), True)
        self.record.update(xms_handles=32, post_boot=dict.fromkeys(("ON", "OFF", "AUTO", "RAM"), {}))
        for name, key in (("MEMM/MEMM/EMM386.EXE", "trace_emm_sha256"),
                          ("HIMEM.SYS", "himem_sha256"),
                          ("src/DOS/MSDOS.SYS", "dos_sha256"),
                          ("src/CMD/COMMAND/COMMAND.COM", "command_sha256")):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(name.encode())
            self.record[key] = sha(path.read_bytes())

    def check(self):
        (self.root / "result.json").write_text(json.dumps(self.record))
        with patch("test_umb_subpage_composition.ROOT", self.root):
            return paired_inputs(self.root)

    def test_matching_completed_fixture(self):
        self.assertEqual(self.check(), (self.root / "MEMM/MEMM/EMM386.EXE", self.root / "HIMEM.SYS"))

    def test_xms_summary_preserves_cost_and_checks_accounting(self):
        self.assertEqual(xms_summary("  Extended (XMS)    7,208,960 410624 6798336\r\n"),
                         dict(total=7208960, used=410624, free=6798336))
        self.assertIsNone(xms_summary("no XMS row"))
        with self.assertRaises(ValueError):
            xms_summary("Extended (XMS) 10 3 8")

    def test_reject_missing_fine_mapping_and_incomplete_modes(self):
        self.record["fine_umbs"] = False
        with self.assertRaisesRegex(ValueError, "fine_umbs"):
            self.check()
        self.record["fine_umbs"] = True
        del self.record["post_boot"]["RAM"]
        with self.assertRaisesRegex(ValueError, "all four"):
            self.check()

    def test_reject_faults_and_mismatched_binary(self):
        self.record["umb_service_reply"] = "after"
        with self.assertRaisesRegex(ValueError, "fault/instrumentation"):
            self.check()
        self.record["umb_service_reply"] = None
        (self.root / "HIMEM.SYS").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "binary mismatch"):
            self.check()


if __name__ == "__main__":
    unittest.main()
