#!/usr/bin/env python3
"""Validate source-derived switch coverage for standalone utility parsers."""

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tests/utility_parser_coverage.json"
VALID_LEVELS = {"uncovered", "observed", "contract"}


def source_switches(text):
    return {value.upper() for value in re.findall(
        r"\bDB\s+[\"'](/[^\"',\s]+)[\"']\s*,\s*0", text, re.IGNORECASE
    )}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    if manifest.get("schema") != 1:
        raise AssertionError("unsupported utility parser coverage schema")

    ci_corpus = (ROOT / "Makefile").read_text() + (ROOT / ".github/workflows/ci.yml").read_text()
    incomplete = []
    counts = {level: 0 for level in VALID_LEVELS}
    total = 0
    for utility, definition in manifest["utilities"].items():
        source = ROOT / definition["source"]
        if not source.is_file():
            raise AssertionError(f"{utility}: missing parser source {definition['source']}")
        derived = source_switches(source.read_text(encoding="latin-1"))
        declared = {switch.upper() for switch in definition["switches"]}
        if derived != declared:
            raise AssertionError(f"{utility}: parser mismatch; missing={sorted(derived-declared)}, stale={sorted(declared-derived)}")
        for switch, item in definition["switches"].items():
            total += 1
            level = item.get("level")
            if level not in VALID_LEVELS:
                raise AssertionError(f"{utility} {switch}: invalid level {level!r}")
            counts[level] += 1
            if not item.get("note"):
                raise AssertionError(f"{utility} {switch}: missing note")
            evidence = item.get("evidence", [])
            if level == "uncovered":
                if evidence:
                    raise AssertionError(f"{utility} {switch}: uncovered item claims evidence")
                incomplete.append(f"{utility}:{switch}")
                continue
            if not evidence:
                raise AssertionError(f"{utility} {switch}: missing evidence")
            for relative in evidence:
                if not (ROOT / relative).is_file():
                    raise AssertionError(f"{utility} {switch}: missing evidence file {relative}")
            if level == "contract":
                runnable = [path for path in evidence if path.endswith(".sh")]
                if not runnable or not any(path in ci_corpus for path in runnable):
                    raise AssertionError(f"{utility} {switch}: evidence is not wired into CI")
            else:
                incomplete.append(f"{utility}:{switch}")

    print(f"Standalone utility parser switches: {total}")
    print(f"  utilities: {len(manifest['utilities'])}")
    print(f"  contract tested: {counts['contract']}")
    print(f"  behavior observed: {counts['observed']}")
    print(f"  uncovered: {counts['uncovered']}")
    if incomplete:
        print("  incomplete: " + " ".join(incomplete))
    if args.require_complete and incomplete:
        raise SystemExit("utility parser coverage incomplete")


if __name__ == "__main__":
    main()
