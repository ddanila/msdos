#!/usr/bin/env python3
"""Inventory emitted disk or character-group crossings; not a relocation proof.

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
    symbols = {name.upper(): value for name, value in symbols.items()}
    start, end = symbols["BIOS_SERVICE_START"], symbols["BIOS_SERVICE_END"]
    if not start == symbols["READ_SECTOR"] < end <= symbols["DISK005S"]:
        raise ValueError("BIOS service boundaries do not match the selected module range")
    return inventory_window(listing, symbols, start, end, "READ_SECTOR")


def inventory_window(listing, symbols, start, end, anchor, owners=()):
    """Distinguish cross-module calls within one proposed high service owner."""
    labels, rows = listing_rows(listing)
    symbols = {name.upper(): value for name, value in symbols.items()}
    if not start < end or symbols[anchor.upper()] != start:
        raise ValueError("invalid module window/anchor")
    base = start - labels[anchor.upper()]
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
                kind = "direct within group" if any(first <= target < last for first, last in owners) else "direct outside body"
                result[(kind, f"{operation} {operand} ({target:04X}h)")].append(address)
        else:
            result[("direct: unresolved", source)].append(address)
    if not instruction_count:
        raise ValueError("no emitted service rows found")
    return start, end, instruction_count, result


def character_inventory(symbols):
    """Build all four exact normal objects; retain state/interrupt gaps outside."""
    symbols = {name.upper(): value for name, value in symbols.items()}
    specs = (("MSCON", "CON$READ", "CBREAK"),
             ("MSAUX", "AUX$READ", "PRN$WRIT"),
             ("MSLPT", "PRN$WRIT", "HAVECMOSCLOCK"),
             ("MSCLOCK", "TIM$WRIT", "SET_ID_FLAG"))
    owners = [(symbols[first], symbols[last]) for _, first, last in specs]
    if any(first >= last for first, last in owners) or any(a[1] > b[0] for a, b in zip(owners, owners[1:])):
        raise ValueError("invalid character-group layout")
    print("# Complete character/clock service crossing inventory\n")
    print(f"Four service bodies: {sum(last-first for first, last in owners)} linked bytes. "
          "CMOS conversion helpers, low state, gateways and alignment are excluded.\n")
    with tempfile.TemporaryDirectory(prefix="msdos-character-crossings-") as scratch:
        for (module, anchor, _), (start, end) in zip(specs, owners):
            path = Path(scratch)
            listing = path / f"{module}.lst"
            obj = path / f"{module}.OBJ"
            subprocess.run([str(ROOT / "bin/jwasm-masm"), f"-I. -I../INC -Fl{listing}",
                            f"{module}.ASM,{obj};"], cwd=ROOT / "src/BIOS",
                           capture_output=True, text=True, check=True)
            if obj.read_bytes() != (ROOT / f"src/BIOS/{module}.OBJ").read_bytes():
                raise ValueError(f"{module} differs from linked object; rebuild BIOS first")
            _, _, count, result = inventory_window(listing.read_text(encoding="latin-1"),
                                                   symbols, start, end, anchor, owners)
            print(f"## {module}: {end-start} bytes, {count} emitted rows\n")
            print("| Class | Operation/target | Linked sites |\n| --- | --- | --- |")
            for (kind, target), sites in sorted(result.items()):
                print(f"| {kind} | `{target}` | " + ", ".join(f"`{site:04X}h`" for site in sites) + " |")
            print()
    print("This is outbound control-flow evidence, not a relocation proof. "
          "Within-group near calls need no low transition if the group shares one segment. "
          "Indirect calls, incoming entries, mutable data and firmware/A20 returns still require binding. "
          "Omitted low state and interrupt entries remain charged; no saving is certified.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--listing", type=Path, help="existing JWasm MSDISK listing")
    parser.add_argument("--characters", action="store_true", help="audit the complete console/serial/printer/clock group")
    args = parser.parse_args()
    _, symbols = parse_map(ROOT / "src/BIOS/msBIO.map")
    if args.characters:
        if args.listing:
            parser.error("--characters builds its own four matched listings")
        character_inventory(symbols)
        return
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
