#!/usr/bin/env python3
"""Check explicit BIOS low/high data, helper, and device-entry contracts."""

from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from report_bios_service_crossings import listing_rows


ROOT = Path(__file__).resolve().parent.parent


class DataSegmentTests(unittest.TestCase):
    def test_low_call_activation_preserves_cold_boot(self):
        with tempfile.TemporaryDirectory(prefix="msdos-bios-activation-") as scratch:
            output = Path(scratch) / "activation.com"
            subprocess.run([str(ROOT / "bin/jwasm-bin"), f"-I{ROOT / 'src/BIOS'}",
                            f"-Fo{output}", str(ROOT / "tests/bios_activation_masm.asm")],
                           check=True, capture_output=True)
            result = subprocess.run([str(ROOT / "bin/dos-run"), str(output)],
                                    cwd=ROOT, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_interrupt_entries_assemble_with_device_entries(self):
        with tempfile.TemporaryDirectory(prefix="msdos-bios-interrupt-") as scratch:
            listing = Path(scratch) / "interrupt.lst"
            built = subprocess.run([str(ROOT / "bin/jwasm-masm"),
                                    "-I. -I../INC -DBIOS_SERVICE_DEVICE_ENTRIES=1 -DBIOS_SERVICE_LOW_CALLS=1 "
                                    f"-DBIOS_SERVICE_INTERRUPT_ENTRIES=1 -Fl{listing}",
                                    f"MSBIO1.ASM,{Path(scratch) / 'interrupt.obj'};"],
                                   cwd=ROOT / "src/BIOS", capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            labels, rows = listing_rows(listing.read_text(encoding="latin-1"))
            first, last = labels["BIOS_LOW_INT2F13"], labels["BIOS_LOW_BLOCK13"]
            self.assertEqual(last - first, 41)
            for address, _, code in rows:
                if first <= address < last:
                    self.assertFalse(re.match(r"CALL\b", code, re.I),
                                     "multiplex filter must not recurse into A20 restoration")
            self.assertEqual(labels["BIOS_INTERRUPT_ENTRIES_END"] - last, 12)

    def test_device_tail_entries_and_unpublished_table(self):
        with tempfile.TemporaryDirectory(prefix="msdos-bios-device-") as scratch:
            scratch = Path(scratch)
            listing = scratch / "device.lst"
            built = subprocess.run([str(ROOT / "bin/jwasm-masm"),
                                    f"-I. -I../INC -DBIOS_SERVICE_DEVICE_ENTRIES=1 -Fl{listing}",
                                    f"MSBIO1.ASM,{scratch / 'device.obj'};"],
                                   cwd=ROOT / "src/BIOS", capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            labels, _ = listing_rows(listing.read_text(encoding="latin-1"))
            self.assertEqual(labels["BIOS_DEVICE_ENTRIES_END"] -
                             labels["BIOS_DEVICE_ENTRIES_START"], 84)
            # Until an installer commits, compiling the feature must leave all
            # original command targets in place, including the purge patch area.
            table = re.search(r"^DSKTBL\b.*?^CONTBL\b",
                              (ROOT / "src/BIOS/DEVTABLE.INC").read_text(), re.M | re.S)[0]
            targets = re.findall(r"^\s*DW\s+([\w$]+)", table, re.M | re.I)
            entries = re.findall(r"^BIOS_DEVICE_ENTRY (\d+),([^,]+),([^,]+),([^\s]+)$",
                                 (ROOT / "src/BIOS/HIGHDEV.INC").read_text(), re.M)
            self.assertEqual([int(row[0]) for row in entries], [4, 8, 9, 15, 19, 23, 24])
            for command, stub, slot, target in entries:
                self.assertEqual(targets[int(command)], target)
            output = scratch / "device.com"
            subprocess.run([str(ROOT / "bin/jwasm-bin"), f"-I{ROOT / 'src/BIOS'}",
                            f"-Fo{output}", str(ROOT / "tests/bios_device_entry_masm.asm")],
                           check=True, capture_output=True)
            result = subprocess.run([str(ROOT / "bin/dos-run"), str(output)],
                                    cwd=ROOT, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_low_prefix_high_calls_assemble(self):
        with tempfile.TemporaryDirectory(prefix="msdos-bios-low-calls-") as scratch:
            built = subprocess.run([str(ROOT / "bin/jwasm-masm"),
                                    "-I. -I../INC -DBIOS_SERVICE_LOW_CALLS=1",
                                    f"MSDISK.ASM,{Path(scratch) / 'low.obj'};"],
                                   cwd=ROOT / "src/BIOS", capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        calls = []
        for line in (ROOT / "src/BIOS/MSDISK.ASM").read_text().splitlines():
            code = line.split(";", 1)[0].strip().upper()
            if code.startswith("BIOS_CALL_HIGH "):
                calls.append(code.split()[1].split(",")[0])
        self.assertEqual(sorted(calls), ["MAPERROR", "MAPERROR", "READ_SECTOR",
                                        "READ_SECTOR", "SETDRIVE", "SETDRIVE"])

    def test_isolated_body_has_no_direct_external_branches(self):
        with tempfile.TemporaryDirectory(prefix="msdos-bios-isolated-") as scratch:
            listing = Path(scratch) / "high.lst"
            built = subprocess.run([str(ROOT / "bin/jwasm-masm"),
                                    f"-I. -I../INC -DBIOS_SERVICE_ISOLATED=1 -Fl{listing}",
                                    f"MSDISK.ASM,{Path(scratch) / 'high.obj'};"],
                                   cwd=ROOT / "src/BIOS", capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            labels, rows = listing_rows(listing.read_text(encoding="latin-1"))
            self.assertEqual(labels["BIOS_SERVICE_START"], 0)
            for _, encoding, code in rows:
                if re.match(r"^(?:(?:26|2E|36|3E))*FF", encoding):
                    continue  # imported gates and explicitly owned dispatch tables
                branch = re.match(r"(?:CALL|J\w+|LOOP\w*)\s+(?:SHORT\s+)?([\w$]+)$", code, re.I)
                if branch:
                    self.assertIn(branch[1].upper(), labels, code)
                    self.assertLess(labels[branch[1].upper()], labels["BIOS_SERVICE_END"], code)

    def test_completion_preserves_original_device_frame(self):
        with tempfile.TemporaryDirectory(prefix="msdos-bios-completion-") as scratch:
            output = Path(scratch) / "complete.com"
            subprocess.run([str(ROOT / "bin/jwasm-bin"), f"-I{ROOT / 'src/BIOS'}",
                            f"-Fo{output}", str(ROOT / "tests/bios_completion_masm.asm")],
                           check=True, capture_output=True)
            result = subprocess.run([str(ROOT / "bin/dos-run"), str(output)],
                                    cwd=ROOT, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_full_separate_data_module_assembles(self):
        # Syntax/range gate only: external low-owner binding and runtime
        # relocation are deliberately not supplied by this object-only build.
        with tempfile.TemporaryDirectory(prefix="msdos-bios-full-data-") as scratch:
            listing = Path(scratch) / "MSDISK.lst"
            command = [str(ROOT / "bin/jwasm-masm"),
                       f"-I. -I../INC -DBIOS_SERVICE_SEPARATE_DATA=1 -Fl{listing}",
                       f"MSDISK.ASM,{Path(scratch) / 'MSDISK.OBJ'};"]
            built = subprocess.run(command, cwd=ROOT / "src/BIOS", capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            labels, rows = listing_rows(listing.read_text(encoding="latin-1"))
            for address, _, code in rows:
                if labels["BIOS_SERVICE_START"] <= address < labels["BIOS_SERVICE_END"]:
                    self.assertFalse(re.match(r"CALL\s+(CHECKIO|CHECKLATCHIO)\b", code, re.I),
                                     "high body retains a non-local low-helper call")

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

    def test_ordinary_low_calls_exclude_nonlocal_exits(self):
        ordinary = []
        for name in ("MSDSKHIG.INC", "MSIOCTL.INC"):
            for line in (ROOT / "src/BIOS" / name).read_text().splitlines():
                code = line.split(";", 1)[0].strip().upper()
                if code.startswith("BIOS_CALL_LOW "):
                    ordinary.append(code.split()[1].split(",")[0])
        self.assertEqual(sorted(ordinary), ["BIOS_CHECKIO_RESULT", "BIOS_CHECKLATCH_RESULT",
                                           "GETBP", "HASCHANGE", "MOV_MEDIA_IDS",
                                           "SET_CHANGED_DL", "SET_CHANGED_DL", "SWPDSK"])

    def test_result_helpers_return_mapped_errors_without_unwinding(self):
        with tempfile.TemporaryDirectory(prefix="msdos-bios-check-result-") as scratch:
            output = Path(scratch) / "check.com"
            subprocess.run(["nasm", "-f", "bin", f"-I{ROOT / 'src/BIOS'}/",
                            str(ROOT / "tests/bios_check_result_probe.asm"), "-o", str(output)],
                           check=True, capture_output=True)
            result = subprocess.run([str(ROOT / "bin/dos-run"), str(output)],
                                    cwd=ROOT, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            built = subprocess.run([str(ROOT / "bin/jwasm-masm"),
                                    "-I. -I../INC -DBIOS_SERVICE_RESULT_HELPERS=1 -DBIOS_SERVICE_LOW_CALLS=1",
                                    f"MSBIO2.ASM,{Path(scratch) / 'MSBIO2.OBJ'};"],
                                   cwd=ROOT / "src/BIOS", capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)


if __name__ == "__main__":
    unittest.main()
