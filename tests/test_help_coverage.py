#!/usr/bin/env python3
"""Validate behavioral /? coverage across every shipped executable."""

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    return json.loads((ROOT / "tests" / name).read_text())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-complete", action="store_true")
    parser.parse_args()

    runtime = load("runtime_coverage.json")["runtime_components"]
    shipped = {
        name for name, item in runtime.items()
        if item["kind"] in {
            "command", "driver_command", "command+driver", "tsr", "command_tsr", "shell"
        }
    }
    run_tests = (ROOT / "tests/run_tests.sh").read_text()
    calls = re.findall(
        r'^check_help\s+"([A-Z0-9]+)"\s+"[^"]+"\s+"[^"]+"\s*$',
        run_tests,
        re.MULTILINE,
    )
    if len(calls) != len(set(calls)):
        raise AssertionError("duplicate executable /? test in run_tests.sh")
    tested = {f"{name}.COM" if f"{name}.COM" in shipped else f"{name}.EXE" for name in calls}
    unknown = tested - shipped
    if unknown:
        raise AssertionError(f"/? tests name unshipped executables: {sorted(unknown)}")

    manifest = load("help_coverage.json")
    if manifest.get("schema") != 1:
        raise AssertionError("unsupported help coverage schema")
    excluded = manifest["no_help_interfaces"]

    database = (ROOT / "src/CMD/HELP/HELP.HLP").read_text().splitlines()
    markers = [line[1:] for line in database if line.startswith("@")]
    if not markers or markers[0] != "INDEX" or len(markers) != len(set(markers)):
        raise AssertionError("HELP database topic markers are missing, reordered, or duplicated")
    first_topic = next(index for index, line in enumerate(database) if line.startswith("@") and line != "@INDEX")
    indexed = {
        line.split()[0]
        for line in database[2:first_topic]
        if line and not line.startswith("Type HELP ")
    }
    topics = set(markers[1:])
    if indexed != topics:
        raise AssertionError(
            f"HELP index mismatch; missing={sorted(topics-indexed)}, stale={sorted(indexed-topics)}"
        )
    for index, marker in enumerate(markers[1:], 1):
        start = database.index(f"@{marker}") + 1
        end = len(database)
        for pos in range(start, len(database)):
            if database[pos].startswith("@"):
                end = pos
                break
        body = database[start:end]
        if not body or not body[0] or not any(line.startswith("Syntax:") for line in body):
            raise AssertionError(f"HELP topic {marker} lacks a description or syntax")
    if tested & set(excluded):
        raise AssertionError(f"help-tested interfaces are also excluded: {sorted(tested & set(excluded))}")
    if tested | set(excluded) != shipped:
        raise AssertionError(
            f"help interface mismatch; missing={sorted(shipped-tested-set(excluded))}, "
            f"stale={sorted(set(excluded)-shipped)}"
        )

    ci_corpus = (ROOT / "Makefile").read_text() + (ROOT / ".github/workflows/ci.yml").read_text()
    if "tests/run_tests.sh" not in ci_corpus:
        raise AssertionError("the /? behavior corpus is not wired into CI")
    for program, item in excluded.items():
        source = ROOT / item["source"]
        if not source.is_file() or item["marker"] not in source.read_text(encoding="latin-1"):
            raise AssertionError(f"{program}: no-help source evidence is missing or stale")
        if not item.get("note") or not item.get("evidence"):
            raise AssertionError(f"{program}: incomplete no-help justification")
        for relative in item["evidence"]:
            if not (ROOT / relative).is_file():
                raise AssertionError(f"{program}: missing evidence {relative}")
            if relative.endswith(".sh") and relative not in ci_corpus:
                raise AssertionError(f"{program}: evidence is not wired into CI")

    print(f"Shipped executable help surfaces: {len(shipped)}")
    print(f"  /? behavior tested: {len(tested)}")
    print(f"  source-justified no-help interfaces: {len(excluded)}")
    print(f"  indexed HELP database topics: {len(topics)}")
    print("  unaccounted: 0")


if __name__ == "__main__":
    main()
