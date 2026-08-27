#!/usr/bin/env python3
"""Validate behavioral traceability for COMMAND.COM's live internal table."""

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tests/command_coverage.json"
LEVELS = {"contract", "observed", "uncovered"}


def live_commands(source):
    try:
        table = source.split("COMTAB\tDB", 1)[1].split(
            "\n\tDB\t0\t\t\t\t; Terminate command table", 1
        )[0]
    except IndexError as error:
        raise AssertionError("COMMAND.COM COMTAB delimiters changed") from error
    commands = re.findall(
        r'^\s*(?:COMTAB\s+)?DB\s+\d+,\s*"([A-Z]+)"',
        "DB" + table,
        re.IGNORECASE | re.MULTILINE,
    )
    if not commands:
        raise AssertionError("no internal commands derived from COMTAB")
    if len(commands) != len(set(commands)):
        raise AssertionError("duplicate internal command in COMTAB")
    return {command.upper() for command in commands}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text())
    if manifest.get("schema") != 1:
        raise AssertionError("unsupported COMMAND.COM coverage schema")
    source_path = ROOT / manifest["dispatch_source"]
    expected = live_commands(source_path.read_text(encoding="latin-1"))
    commands = manifest["commands"]
    declared = set(commands)
    if expected != declared:
        raise AssertionError(
            f"COMMAND.COM inventory mismatch: missing={sorted(expected - declared)}, "
            f"stale={sorted(declared - expected)}"
        )

    ci_corpus = (ROOT / "Makefile").read_text() + "\n" + (
        ROOT / ".github/workflows/ci.yml"
    ).read_text()
    counts = {level: 0 for level in LEVELS}
    for command, item in commands.items():
        level = item.get("level")
        if level not in LEVELS:
            raise AssertionError(f"{command}: invalid level {level!r}")
        if not item.get("note", "").strip():
            raise AssertionError(f"{command}: missing coverage note")
        evidence = item.get("evidence", [])
        if level != "uncovered" and not evidence:
            raise AssertionError(f"{command}: missing evidence")
        for relative in evidence:
            if not (ROOT / relative).is_file():
                raise AssertionError(f"{command}: missing evidence file {relative}")
        runnable = [path for path in evidence if path.endswith(".sh")]
        if level == "contract" and (
            not runnable or not any(path in ci_corpus for path in runnable)
        ):
            raise AssertionError(f"{command}: contract evidence is not wired into CI")
        counts[level] += 1

    print(f"COMMAND.COM internal commands: {len(expected)}")
    print(f"  contract tested: {counts['contract']}")
    print(f"  behavior observed: {counts['observed']}")
    print(f"  uncovered: {counts['uncovered']}")
    incomplete = sorted(
        command for command, item in commands.items() if item["level"] != "contract"
    )
    if incomplete:
        print("  incomplete: " + " ".join(incomplete))
    if args.require_complete and incomplete:
        raise SystemExit("COMMAND.COM coverage incomplete for: " + " ".join(incomplete))


if __name__ == "__main__":
    main()
