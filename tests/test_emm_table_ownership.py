#!/usr/bin/env python3
"""Guard named roots whose runtime access has moved into EMMSUP services."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1] / "src/MEMM"
ROOT_NAMES = re.compile(r"\b_?(?:handle_table|save_map|Handle_Name_Table)\b", re.I)
OWNERS = {"EMM/EMMSUP.ASM", "EMM/EMMDATA.ASM",
          "MEMM/EMMINIT.ASM", "MEMM/INITTAB.ASM"}


def direct_roots(source, suffix):
    if suffix == ".C":
        source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    else:
        source = re.sub(r";[^\n]*", "", source)
    return ROOT_NAMES.findall(source)


class OwnershipTest(unittest.TestCase):
    def test_only_owner_and_initializers_use_roots(self):
        violations = []
        for path in ROOT.rglob("*"):
            if path.suffix not in {".ASM", ".C"}:
                continue
            relative = path.relative_to(ROOT).as_posix()
            if relative not in OWNERS and direct_roots(path.read_text(encoding="latin-1"), path.suffix):
                violations.append(relative)
        self.assertEqual(violations, [])

    def test_detects_direct_access_but_not_comments_or_counts(self):
        self.assertTrue(direct_roots("mov bx,[_handle_table]", ".ASM"))
        self.assertTrue(direct_roots("save_map[h].window[0] = 0;", ".C"))
        self.assertFalse(direct_roots("; _handle_table\nmov al,[_handle_table_size]", ".ASM"))
        self.assertFalse(direct_roots("/* save_map */ HandleCount(h);", ".C"))


if __name__ == "__main__":
    unittest.main()
