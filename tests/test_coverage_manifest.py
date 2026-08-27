#!/usr/bin/env python3
"""Validate and summarize behavioral traceability against the live INT 21h table."""

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tests/int21_coverage.json"
VALID_LEVELS = {"observed", "contract"}


def dispatch_entries(source):
    text = source.read_text(encoding="latin-1")
    table = text.split("DISPATCH    LABEL WORD", 1)[1].split("VAL2", 1)[0]
    entries = []
    pattern = re.compile(
        r"^\s*short_addr\s+(\S+)\s*;\s*(\d+)\s+([0-9A-Fa-f]+)\b",
        re.MULTILINE | re.IGNORECASE,
    )
    for handler, decimal, hexadecimal in pattern.findall(table):
        index = int(decimal)
        value = int(hexadecimal, 16)
        if index != value:
            raise AssertionError(
                f"dispatch annotation disagrees: decimal {index}, hex {value:02X}"
            )
        entries.append((value, handler))
    return entries


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--require-complete",
        action="store_true",
        help="fail unless every dispatch entry has contract-level evidence or an exclusion",
    )
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text())
    if manifest.get("schema") != 1:
        raise AssertionError("unsupported coverage manifest schema")

    source = ROOT / manifest["dispatch_source"]
    entries = dispatch_entries(source)
    if [value for value, _ in entries] != list(range(0x6D)):
        raise AssertionError("INT 21h dispatch table is not the contiguous range 00h-6Ch")

    functions = manifest["functions"]
    excluded = manifest["excluded"]
    workflow_text = (ROOT / ".github/workflows/ci.yml").read_text()
    known = {f"{value:02X}" for value, _ in entries}
    declared = set(functions) | set(excluded)
    unknown = declared - known
    if unknown:
        raise AssertionError(f"manifest names unknown INT 21h calls: {sorted(unknown)}")

    for call, item in functions.items():
        if item["level"] not in VALID_LEVELS:
            raise AssertionError(f"INT 21h/{call}: invalid level {item['level']!r}")
        if not item.get("note"):
            raise AssertionError(f"INT 21h/{call}: missing coverage note")
        evidence = item.get("evidence", [])
        if not evidence:
            raise AssertionError(f"INT 21h/{call}: missing evidence")
        for relative in evidence:
            path = ROOT / relative
            if not path.is_file():
                raise AssertionError(f"INT 21h/{call}: evidence does not exist: {relative}")
        if item["level"] == "contract":
            runnable = [relative for relative in evidence if relative.endswith(".sh")]
            if not runnable or not any(path in workflow_text for path in runnable):
                raise AssertionError(
                    f"INT 21h/{call}: contract evidence is not wired into CI"
                )

    for call, reason in excluded.items():
        if not reason.strip():
            raise AssertionError(f"INT 21h/{call}: exclusion has no justification")

    contract = {call for call, item in functions.items() if item["level"] == "contract"}
    observed = set(functions) - contract
    uncovered = known - declared
    print(f"INT 21h dispatch entries: {len(entries)}")
    print(f"  contract tested: {len(contract)}")
    print(f"  behavior observed: {len(observed)}")
    print(f"  justified exclusions: {len(excluded)}")
    print(f"  uncovered: {len(uncovered)}")
    if uncovered:
        print("  uncovered calls: " + " ".join(sorted(uncovered)))

    if args.require_complete:
        incomplete = known - contract - set(excluded)
        if incomplete:
            raise SystemExit(
                "contract coverage incomplete for: " + " ".join(sorted(incomplete))
            )


if __name__ == "__main__":
    main()
