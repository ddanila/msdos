"""Linked-owner checks reject a stale caller or an incorrectly unwound stack."""
from pathlib import Path
import shutil
import tempfile
import unittest

from build_emm_mode_guard import ROOT, check_error_owner
from report_emm386_residency import parse_map


class ErrorOwnerTests(unittest.TestCase):
    def setUp(self):
        self.source = ROOT / "src/MEMM/MEMM"
        if not (self.source / "EMM386.EXE").exists():
            self.skipTest("run make memm before linked-owner tests")

    def test_complete_owner(self):
        check_error_owner(self.source)

    def mutate(self, target, change):
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp)
            shutil.copyfile(self.source / "EMM386.MAP", work / "EMM386.MAP")
            data = bytearray((self.source / "EMM386.EXE").read_bytes())
            _, symbols = parse_map(work / "EMM386.MAP")
            symbol = next(symbol for symbol in symbols if symbol.name == target)
            offset = int.from_bytes(data[8:10], "little") * 16 + symbol.paragraph * 16 + symbol.offset
            change(data, offset)
            (work / "EMM386.EXE").write_bytes(data)
            with self.assertRaises(AssertionError):
                check_error_owner(work)

    def test_double_pop_bx_rejected(self):
        self.mutate("ErrResumeLoadall", lambda data, at: data.__setitem__(at + 1, 0x5b))

    def test_stale_mode_switch_return_rejected(self):
        def stale(data, at):
            self.assertEqual(data[at + 0x22], 0x68)
            data[at + 0x23:at + 0x25] = b"\xff\xff"
        self.mutate("ErrHndlr", stale)


if __name__ == "__main__":
    unittest.main()
