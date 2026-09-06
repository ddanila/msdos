#!/usr/bin/env python3
"""Keep source-level ownership leads conservative, without claiming liveness."""
import unittest

from report_dos_prefix_references import references


class PrefixReferencesTests(unittest.TestCase):
    def test_case_insensitive_linked_operands_and_displacements(self):
        rows = references("mov ax,CS:[state+2]\ncall dword ptr cs:Table[di]",
                          {"State": 0x20, "Table": 0x30}, 0x100)
        self.assertEqual([row["symbols"][0]["name"] for row in rows], ["State", "Table"])

    def test_comments_and_assumptions_are_not_accesses(self):
        self.assertEqual(references("; cs:[State]\nASSUME CS:DOSGROUP\nmov ax,1 ; cs:[State]",
                                    {"State": 0x20}, 0x100), [])

    def test_indexed_and_unlinked_operands_remain_unresolved(self):
        rows = references("mov ax,cs:[si]\nmov ax,cs:[private_local+bx]", {}, 0x100)
        self.assertEqual([row["kind"] for row in rows], ["unresolved", "unresolved"])

    def test_prefix_is_half_open_and_excludes_uncopied_start(self):
        source = "\n".join(f"mov ax,cs:[{name}]" for name in ["before", "first", "last", "after"])
        rows = references(source, dict(before=0xF, first=0x10, last=0xFF, after=0x100), 0x100)
        self.assertEqual([row["symbols"][0]["name"] for row in rows], ["first", "last"])

    def test_conditional_source_is_not_treated_as_linked_execution(self):
        rows = references("IFDEF OLD\nmov cs:[State],ax\nENDIF", {"State": 0x20}, 0x100)
        self.assertEqual(rows[0]["line"], 2)
        self.assertIn("instruction", rows[0])

    def test_no_reference_is_not_a_reclamation_proof(self):
        # PUSH CS / POP DS and derived far pointers are intentionally out of scope.
        self.assertEqual(references("push cs\npop ds\nmov ax,[State]", {"State": 0x20}, 0x100), [])


if __name__ == "__main__":
    unittest.main()
