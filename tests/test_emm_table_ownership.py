#!/usr/bin/env python3
"""Guard named roots whose runtime access has moved into EMMSUP services."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1] / "src/MEMM"
ROOT_NAMES = re.compile(r"\b_?(?:handle_table|save_map|Handle_Name_Table|mappable_pages|physical_page_exceptions)\b", re.I)
PAGE_ROOTS = re.compile(r"\b_?(?:emm_page|emm_free|pft386)\b", re.I)
C_DMA_ROOTS = re.compile(r"\b_?(?:DMA_Pages|mappable_pages)\b", re.I)
CURRENT_MAP_ROOT = re.compile(r"\bCurRegSet\b", re.I)
OWNERS = {"EMM/EMMSUP.ASM", "EMM/EMMDATA.ASM",
          "MEMM/EMMINIT.ASM", "MEMM/INITTAB.ASM"}
PAGE_OWNERS = OWNERS | {"MEMM/INITEPG.ASM", "MEMM/INIT.ASM"}


def direct_roots(source, suffix, roots=ROOT_NAMES):
    if suffix == ".C":
        source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
        source = re.sub(r'"(?:\\.|[^"\\])*"', "", source)
    else:
        source = re.sub(r";[^\n]*", "", source)
    return roots.findall(source)


class OwnershipTest(unittest.TestCase):
    def test_current_map_root_stays_with_owners(self):
        # EMMP still owns bulk snapshots/alternate-set switching; ELIMTRAP's
        # DMA query now delegates to the indexed owner and may not dereference it.
        allowed = OWNERS | {"EMM/EMMP.ASM"}
        violations = []
        for path in ROOT.rglob("*"):
            if path.suffix not in {".ASM", ".C"}:
                continue
            if (path.relative_to(ROOT).as_posix() not in allowed
                    and direct_roots(path.read_text(encoding="latin-1"), path.suffix,
                                     CURRENT_MAP_ROOT)):
                violations.append(path.relative_to(ROOT).as_posix())
        self.assertEqual(violations, [])

    def test_c_dma_consumers_do_not_retain_table_pointers(self):
        violations = [path.relative_to(ROOT).as_posix() for path in ROOT.rglob("*.C")
                      if direct_roots(path.read_text(encoding="latin-1"), ".C", C_DMA_ROOTS)]
        self.assertEqual(violations, [])
        self.assertTrue(direct_roots("DMA_Pages[k] = p;", ".C", C_DMA_ROOTS))

    def test_page_roots_stay_with_owner_or_initialization(self):
        violations = []
        for path in ROOT.rglob("*"):
            if path.suffix not in {".ASM", ".C"}:
                continue
            relative = path.relative_to(ROOT).as_posix()
            # Historical implementation is not linked; verify the active rule below.
            if relative in PAGE_OWNERS or relative == "MEMM/MAPDMA.ASM":
                continue
            if direct_roots(path.read_text(encoding="latin-1"), path.suffix, PAGE_ROOTS):
                violations.append(relative)
        self.assertEqual(violations, [])
        rules = (ROOT.parents[1] / "mk/memm.mk").read_text()
        self.assertIn("$(MEMM_DIR)/MAPDMA.OBJ: $(MEMM_DIR)/MAPDMA.C", rules)
        self.assertNotIn("MAPDMA.ASM", rules.upper())

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
        self.assertTrue(direct_roots("mov bx,[_mappable_pages]", ".ASM"))
        self.assertFalse(direct_roots("; _handle_table\nmov al,[_handle_table_size]", ".ASM"))
        self.assertFalse(direct_roots("/* save_map */ HandleCount(h);", ".C"))
        self.assertTrue(direct_roots("return pft386[i];", ".C", PAGE_ROOTS))
        self.assertTrue(direct_roots("mov ax,[_emm_free]", ".ASM", PAGE_ROOTS))
        self.assertFalse(direct_roots('FatalError("PFT386 entry");', ".C", PAGE_ROOTS))


if __name__ == "__main__":
    unittest.main()
