#!/usr/bin/env python3
"""Inventory emitted MSDISK control-flow crossings; not a relocation proof.

Uses our assembler listing and linker map, never foreign binaries or sources.
Indirect targets, external entry points, and data ownership still need review.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
from pathlib import Path
import re
import subprocess
import tempfile

from report_dos_bios_residency import parse_map


ROOT = Path(__file__).resolve().parent.parent
NAME = r"[A-Za-z_?$@][\w?$@]*"


def listing_rows(listing: str) -> tuple[dict[str, int], list[tuple[int, str, str]]]:
    """JWasm's address/encoding fields occupy the first 32 columns.

    Only addressed, emitted instruction rows count. Unassembled conditional
    branches and macro definitions have no address and are excluded.
    """
    labels: dict[str, int] = {}
    rows = []
    for line in listing.splitlines():
        match = re.match(r"^([0-9A-F]{4,8}) ", line)
        if not match:
            continue
        address = int(match[1], 16)
        source = line[32:].split(";", 1)[0].strip()
        label = re.match(rf"^({NAME})(?::|\s+(?:PROC|LABEL)\b)", source, re.I)
        if label:
            labels[label[1].upper()] = address
            if ":" in label[0]:
                source = source[label.end():].strip()
        encoding = line[match.end():32].strip().split()
        if encoding and re.fullmatch(r"[0-9A-F]{2,}(?:[or])?", encoding[0]):
            rows.append((address, encoding[0], source))
    return labels, rows


def inventory(listing: str, symbols: dict[str, int]):
    labels, rows = listing_rows(listing)
    symbols = {name.upper(): value for name, value in symbols.items()}
    start, end = symbols["READ_SECTOR"], symbols["DISK005S"]
    base = start - labels["READ_SECTOR"]
    targets = dict(symbols)
    targets.update({name: base + value for name, value in labels.items()})
    result: dict[tuple[str, str], list[int]] = defaultdict(list)
    instruction_count = 0
    for address, encoding, source in rows:
        address += base
        if not start <= address < end:
            continue
        instruction_count += 1
        match = re.match(r"^(CALL|J\w+|LOOP\w*|INT|IRET)\b\s*(.*)", source, re.I)
        if not match:
            continue
        operation, operand = match[1].upper(), match[2].strip()
        if operation in ("INT", "IRET"):
            result[("interrupt boundary", source)].append(address)
            continue
        if re.match(r"^(?:(?:26|2E|36|3E))*FF", encoding):
            result[("indirect: unresolved", source)].append(address)
            continue
        operand = re.sub(r"^(?:SHORT|NEAR PTR|FAR PTR)\s+", "", operand, flags=re.I)
        if re.fullmatch(NAME, operand) and operand.upper() in targets:
            target = targets[operand.upper()]
            if not start <= target < end:
                result[("direct outside body", f"{operation} {operand} ({target:04X}h)")].append(address)
        else:
            result[("direct: unresolved", source)].append(address)
    if not instruction_count:
        raise ValueError("no emitted service rows found")
    return start, end, instruction_count, result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--listing", type=Path, help="existing JWasm MSDISK listing")
    args = parser.parse_args()
    _, symbols = parse_map(ROOT / "src/BIOS/msBIO.map")
    if args.listing:
        listing = args.listing.read_text(encoding="latin-1")
    else:
        with tempfile.TemporaryDirectory(prefix="msdos-bios-crossings-") as scratch:
            temporary = Path(scratch)
            listing_path = temporary / "MSDISK.lst"
            built = subprocess.run(
                [str(ROOT / "bin/jwasm-masm"),
                 f"-I. -I../INC -Fl{listing_path}",
                 f"MSDISK.ASM,{temporary / 'MSDISK.OBJ'};"],
                cwd=ROOT / "src/BIOS", capture_output=True, text=True,
            )
            if built.returncode:
                raise RuntimeError(built.stdout + built.stderr)
            # Anchor against the linked module, not just an arbitrary listing.
            if (temporary / "MSDISK.OBJ").read_bytes() != (ROOT / "src/BIOS/MSDISK.OBJ").read_bytes():
                raise ValueError("MSDISK object differs from fresh listing build; rebuild BIOS first")
            listing = listing_path.read_text(encoding="latin-1")
    start, end, count, result = inventory(listing, symbols)
    print("# BIOS high-service control-flow inventory\n")
    print(f"Candidate `{start:04X}h..{end:04X}h`: {end-start:,} bytes; {count} emitted rows reviewed.\n")
    print("| Class | Operation/target | Sites (linked offsets) |")
    print("| --- | --- | --- |")
    for (kind, target), sites in sorted(result.items()):
        print(f"| {kind} | `{target}` | " + ", ".join(f"`{site:04X}h`" for site in sites) + " |")
    print("\nThis inventories outbound symbolic control flow in the emitted MSDISK")
    print("body, including MSIOCTL.INC. It does not prove data relocation, identify")
    print("all incoming references or pointer tables, or resolve indirect targets.")
    print("Boot-time PURGE_96TPI can remove calls from this linked inventory;")
    print("the selected runtime layout must be checked separately before rebasing.")
    print("A low ROM-return gate is required before any high continuation can rely")
    print("on A20. Counts are audit coverage, not conventional-memory savings.")


if __name__ == "__main__":
    main()
