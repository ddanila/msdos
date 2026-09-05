#!/usr/bin/env python3
"""Check both 8086 segment-materialization forms and all fifteen call sites."""

from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent


class DataSegmentTests(unittest.TestCase):
    def test_full_separate_data_module_assembles(self):
        # Syntax/range gate only: external low-owner binding and runtime
        # relocation are deliberately not supplied by this object-only build.
        with tempfile.TemporaryDirectory(prefix="msdos-bios-full-data-") as scratch:
            command = [str(ROOT / "bin/jwasm-masm"),
                       "-I. -I../INC -DBIOS_SERVICE_SEPARATE_DATA=1",
                       f"MSDISK.ASM,{Path(scratch) / 'MSDISK.OBJ'};"]
            built = subprocess.run(command, cwd=ROOT / "src/BIOS", capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)

    def test_separate_low_operand_execution_and_rejected_contracts(self):
        with tempfile.TemporaryDirectory(prefix="msdos-bios-operands-") as scratch:
            output = Path(scratch) / "operands.com"
            command = [str(ROOT / "bin/jwasm-bin"), f"-I{ROOT / 'src/BIOS'}", f"-Fo{output}"]
            source = str(ROOT / "tests/bios_low_operand_masm.asm")
            subprocess.run(command + [source], check=True, capture_output=True)
            executed = subprocess.run(
                [str(ROOT / "bin/dos-run"), str(output)], cwd=ROOT,
                capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(executed.returncode, 0, executed.stdout + executed.stderr)
            for invalid in ("BAD_BORROW", "BAD_STACK", "BAD_SEGMENT", "BAD_VALUE", "BAD_RESULT", "BAD_UNARY"):
                built = subprocess.run(command + [f"-D{invalid}=1", source], capture_output=True)
                self.assertNotEqual(built.returncode, 0, f"accepted unsafe {invalid} contract")

    def test_assembled_contract(self):
        with tempfile.TemporaryDirectory(prefix="msdos-bios-segment-") as scratch:
            for separate, expected in (
                (False, bytes.fromhex("0e 07 cb 34 12")),
                (True, bytes.fromhex("2e ff 36 07 00 07 cb 34 12")),
            ):
                output = Path(scratch) / f"{separate}.bin"
                command = [str(ROOT / "bin/jwasm-bin"), f"-I{ROOT / 'src/BIOS'}", f"-Fo{output}"]
                if separate:
                    command.append("-DBIOS_SERVICE_SEPARATE_DATA=1")
                command.append(str(ROOT / "tests/bios_data_segment_masm.asm"))
                subprocess.run(command, check=True, capture_output=True)
                # Both forms preserve FLAGS and all registers except intended
                # ES; the high form reads the explicit low-owner word at 0007h.
                self.assertEqual(output.read_bytes(), expected)

    def test_segment_materialization_sites(self):
        total = 0
        for name in ("MSDSKHIG.INC", "MSIOCTL.INC"):
            for line in (ROOT / "src/BIOS" / name).read_text().splitlines():
                code = line.split(";", 1)[0]
                self.assertFalse(re.search(r"\bPUSH\s+CS\b", code, re.I), name)
                if re.search(r"\bBIOS_PUSH_DATA_SEG\b", code):
                    total += 1
        self.assertEqual(total, 15, "review every added/removed data-segment consumer")

    def test_remaining_cs_operands_have_explicit_code_or_chain_ownership(self):
        expected = {
            "MSDSKHIG.INC": ["JMP CS:[NEXT2F_13]"],
            "MSIOCTL.INC": ["CMP AL, CS:[SI]", "CALL CS:[SI]"],
        }
        for name, allowed in expected.items():
            actual = []
            for line in (ROOT / "src/BIOS" / name).read_text().splitlines():
                code = " ".join(line.split(";", 1)[0].upper().split())
                if "CS:" in code and not code.startswith("ASSUME "):
                    actual.append(code)
            self.assertEqual(actual, allowed, "new raw CS operand requires ownership review")


if __name__ == "__main__":
    unittest.main()
