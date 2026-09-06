#!/usr/bin/env python3
"""Inventory explicit CS operands before redesigning the duplicated DOS prefix.

Source-level leads only: not an assembler, liveness proof, or relocation verifier.
Conditional branches and macro bodies are deliberately included. Indexed CS
operands without a linked symbol are retained for manual review, not dropped.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re

from report_dos_bios_residency import parse_map, require

IDENT = re.compile(r"[A-Za-z_?$@][A-Za-z0-9_?$@]*")
CS = re.compile(r"\bcs\s*:\s*(\[[^\]]*\]|[^,\s]+)", re.I)


def references(source: str, symbols: dict[str, int], low_end: int) -> list[dict]:
    linked = {name.upper(): (name, address) for name, address in symbols.items()}
    rows = []
    for number, raw in enumerate(source.splitlines(), 1):
        # Semicolon comments and ASSUME are not executable memory operands.
        line = raw.split(";", 1)[0].strip()
        if not line or re.match(r"assume\b", line, re.I):
            continue
        for match in CS.finditer(line):
            operand = match.group(1)
            hits = sorted({linked[token.upper()] for token in IDENT.findall(operand)
                           if token.upper() in linked}, key=lambda item: (item[1], item[0]))
            prefix = [(name, address) for name, address in hits if 0x10 <= address < low_end]
            if prefix or not hits:
                rows.append(dict(line=number, instruction=line, operand=operand,
                                 kind="prefix-symbol" if prefix else "unresolved",
                                 symbols=[dict(name=name, offset=address) for name, address in prefix]))
    return rows


def inventory(map_path: Path, source_dir: Path) -> dict:
    _, symbols = parse_map(map_path)
    low_end = require(symbols, "DOS_LOW_GATE_END")
    high_end = require(symbols, "SYSBUF")
    if not 0x10 < low_end < high_end <= 0xFFF0:
        raise ValueError("invalid copied-prefix/HMA boundaries")
    paths = sorted(path for path in source_dir.iterdir()
                   if path.is_file() and path.suffix.upper() in {".ASM", ".INC"})
    if not paths:
        raise ValueError("no DOS assembly sources found")
    rows, hashes = [], {}
    for path in paths:
        data = path.read_bytes()
        hashes[path.name] = hashlib.sha256(data).hexdigest()
        rows.extend(dict(file=path.name, **row)
                    for row in references(data.decode("latin-1"), symbols, low_end))
    return dict(map_sha256=hashlib.sha256(map_path.read_bytes()).hexdigest(),
                source_sha256=hashes, copied_prefix_bytes=low_end - 0x10,
                low_end=low_end, high_end=high_end, references=rows,
                limitation="Explicit CS source operands only; no reachability, effective-address, "
                "macro-expansion, indirect-pointer, or low/high authority proof. "
                "Map/source identity requires a fresh build; hashes alone do not prove it.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("map", type=Path)
    parser.add_argument("--source-dir", type=Path, default=Path("src/DOS"))
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    result = inventory(args.map, args.source_dir)
    if args.json:
        print(json.dumps(result, indent=2))
        return
    rows = result["references"]
    grouped = {}
    for row in rows:
        for symbol in row["symbols"]:
            key = (symbol["offset"], symbol["name"])
            grouped.setdefault(key, []).append(f"{row['file']}:{row['line']}")
    print("# DOS copied-prefix reference audit\n")
    print(f"Copied prefix: {result['copied_prefix_bytes']:,} HMA bytes. "
          "**No bytes are certified reclaimable by this report.**\n")
    print(result["limitation"] + "\n")
    print("| Linked offset | Symbol | Explicit CS operand sites |")
    print("| --- | --- | --- |")
    for (offset, name), sites in sorted(grouped.items()):
        print(f"| `{offset:04X}h` | `{name}` | {', '.join(sites)} |")
    unresolved = [row for row in rows if row["kind"] == "unresolved"]
    print(f"\n{len(grouped)} prefix symbols; {len(unresolved)} unresolved CS operands. "
          "Use --json for instructions, unresolved sites and input hashes. "
          "An absent symbol is not evidence of an unused high copy.")


if __name__ == "__main__":
    main()
