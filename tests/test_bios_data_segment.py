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
            "MSDSKHIG.INC": [],
            "MSIOCTL.INC": ["CMP AL, CS:[SI]", "CALL CS:[SI]"],
        }
        for name, allowed in expected.items():
            actual = []
            for line in (ROOT / "src/BIOS" / name).read_text().splitlines():
                code = " ".join(line.split(";", 1)[0].upper().split())
                if "CS:" in code and not code.startswith("ASSUME "):
                    actual.append(code)
            self.assertEqual(actual, allowed, "new raw CS operand requires ownership review")

    def test_direct_rom_calls_use_low_return_gates(self):
        counts = {"BIOS_ROM_INT13": 0, "BIOS_ROM_INT1A": 0, "BIOS_ROM_ORIG13": 0}
        for name in ("MSDSKHIG.INC", "MSIOCTL.INC"):
            for line in (ROOT / "src/BIOS" / name).read_text().splitlines():
                code = line.split(";", 1)[0].strip().upper()
                self.assertFalse(re.match(r"INT\s+(?:13|1A)H\b", code), name)
                self.assertFalse(re.match(r"CALL\s+ORIG13\b", code), name)
                if code in counts:
                    counts[code] += 1
        self.assertEqual(counts, {"BIOS_ROM_INT13": 8, "BIOS_ROM_INT1A": 1,
                                  "BIOS_ROM_ORIG13": 8})

    def test_service_body_named_storage_is_only_code_dispatch(self):
        # Structure fields describe stack frames; they allocate no body bytes.
        # New named storage otherwise needs an explicit ownership decision.
        for name, allowed in (("MSDSKHIG.INC", []),
                              ("MSIOCTL.INC", ["IOREADJUMPTABLE", "IOWRITEJUMPTABLE"])):
            fields = False
            actual = []
            for line in (ROOT / "src/BIOS" / name).read_text().splitlines():
                code = line.split(";", 1)[0].strip().upper()
                if re.match(r"\w+\s+STRUC\b", code):
                    fields = True
                elif re.match(r"\w+\s+ENDS\b", code):
                    fields = False
                elif not fields:
                    declaration = re.match(r"(\w+)\s+(?:DB|DW|DD)\b", code)
                    if declaration:
                        actual.append(declaration[1])
            self.assertEqual(actual, allowed, "new service-body storage needs ownership review")

    def test_tail_chains_use_low_vector_gate(self):
        code = [(line.split(";", 1)[0].strip().upper()) for line in
                (ROOT / "src/BIOS/MSDSKHIG.INC").read_text().splitlines()]
        chains = [line for line in code if line.startswith("BIOS_CHAIN_VECTOR ")]
        self.assertEqual(chains, ["BIOS_CHAIN_VECTOR ORIG13,BIOS_SERVICE_ORIG13_OFFSET",
                                  "BIOS_CHAIN_VECTOR NEXT2F_13,BIOS_SERVICE_NEXT2F_OFFSET"])
        self.assertFalse(any(re.match(r"JMP\s+(?:ORIG13|CS:\[NEXT2F_13\])", line)
                             for line in code))


if __name__ == "__main__":
    unittest.main()
