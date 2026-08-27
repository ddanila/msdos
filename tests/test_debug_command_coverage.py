#!/usr/bin/env python3
"""Validate DEBUG's source-dispatched command-language coverage."""

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tests/debug_command_coverage.json"


def debug_commands(text):
    table = text.split("COMTAB\tDW", 1)[1].split("\n\nQUIT:", 1)[0]
    rows = re.findall(r"(?:^|\n)\s*(?:COMTAB\s+)?DW\s+(\w+)\s*;\s*([A-Z])", "COMTAB\tDW" + table)
    commands = {letter for handler, letter in rows if handler.upper() != "PERR"}
    # The shipped clone build has SYSVER=0, selecting DEBEMS for X.
    if "X" not in commands or "DEBEMS" not in table:
        raise AssertionError("DEBUG X/DEBEMS build selection is missing or stale")
    return commands


def ems_subcommands(text):
    dispatch = text.split("DEBEMS:", 1)[1].split("XM_EMS_ALLOC", 1)[0]
    return set(re.findall(r'cmp\s+al,"([A-Z])"', dispatch, re.IGNORECASE))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    if manifest.get("schema") != 1:
        raise AssertionError("unsupported DEBUG coverage schema")

    derived = {
        "commands": debug_commands((ROOT / "MS-DOS/v4.0/src/CMD/DEBUG/DEBUG.ASM").read_text(encoding="latin-1")),
        "ems_subcommands": ems_subcommands((ROOT / "MS-DOS/v4.0/src/CMD/DEBUG/DEBEMS.ASM").read_text(encoding="latin-1")),
    }
    ci_corpus = (ROOT / "Makefile").read_text() + (ROOT / ".github/workflows/ci.yml").read_text()
    incomplete = []
    for section, source_entries in derived.items():
        declared = set(manifest[section])
        if source_entries != declared:
            raise AssertionError(
                f"DEBUG {section} mismatch; missing={sorted(source_entries-declared)}, "
                f"stale={sorted(declared-source_entries)}"
            )
        for name, item in manifest[section].items():
            if item.get("level") != "contract":
                incomplete.append(f"{section}:{name}")
            if not item.get("note") or not item.get("evidence"):
                raise AssertionError(f"DEBUG {section} {name}: incomplete traceability record")
            for relative in item["evidence"]:
                if not (ROOT / relative).is_file():
                    raise AssertionError(f"DEBUG {section} {name}: missing evidence {relative}")
            if not any(relative.endswith(".sh") and relative in ci_corpus for relative in item["evidence"]):
                raise AssertionError(f"DEBUG {section} {name}: evidence is not wired into CI")

    print(f"DEBUG interactive commands: {len(derived['commands'])}")
    print(f"  EMS subcommands: {len(derived['ems_subcommands'])}")
    print(f"  contract tested: {sum(len(values) for values in derived.values())}")
    print(f"  uncovered: {len(incomplete)}")
    if args.require_complete and incomplete:
        raise SystemExit("DEBUG command coverage incomplete")


if __name__ == "__main__":
    main()
