#!/usr/bin/env python3
"""Ensure every shipped executable has a machine-accounted input grammar."""

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    return json.loads((ROOT / "tests" / name).read_text())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-complete", action="store_true")
    parser.parse_args()

    runtime = load("runtime_coverage.json")["runtime_components"]
    utility = set(load("utility_parser_coverage.json")["utilities"])
    manifest = load("program_interface_coverage.json")
    if manifest.get("schema") != 1:
        raise AssertionError("unsupported program-interface coverage schema")
    specialized = manifest["specialized_interfaces"]

    executable_kinds = {"command", "driver_command", "tsr", "command_tsr", "shell"}
    shipped = {name for name, item in runtime.items() if item["kind"] in executable_kinds}
    table_driven = utility | {"COMMAND.COM", "SELECT.EXE"}
    overlap = table_driven & set(specialized)
    if overlap:
        raise AssertionError(f"interfaces have duplicate classifications: {sorted(overlap)}")
    accounted = table_driven | set(specialized)
    if accounted != shipped:
        raise AssertionError(
            f"executable interface mismatch; missing={sorted(shipped-accounted)}, "
            f"stale={sorted(accounted-shipped)}"
        )

    valid_classes = {"positional", "positional_interactive", "interactive", "keyword", "stream", "bootstrap"}
    ci_corpus = (ROOT / "Makefile").read_text() + (ROOT / ".github/workflows/ci.yml").read_text()
    for program, item in specialized.items():
        if item.get("class") not in valid_classes:
            raise AssertionError(f"{program}: invalid interface class {item.get('class')!r}")
        source = ROOT / item["source"]
        if not source.is_file():
            raise AssertionError(f"{program}: missing source {item['source']}")
        if item.get("marker") not in source.read_text(encoding="latin-1"):
            raise AssertionError(f"{program}: source marker is missing or stale")
        if not item.get("note"):
            raise AssertionError(f"{program}: missing classification note")
        evidence = item.get("evidence", [])
        if not evidence:
            raise AssertionError(f"{program}: missing behavioral evidence")
        for relative in evidence:
            if not (ROOT / relative).is_file():
                raise AssertionError(f"{program}: missing evidence file {relative}")
        runnable = [relative for relative in evidence if relative.endswith(".sh")]
        if not runnable or not any(relative in ci_corpus for relative in runnable):
            raise AssertionError(f"{program}: evidence is not wired into CI")

    print(f"Shipped executable interfaces: {len(shipped)}")
    print(f"  source-derived switch grammars: {len(utility)}")
    print("  COMMAND.COM grammar: 1")
    print("  SELECT.EXE mode grammar: 1")
    print(f"  specialized interfaces: {len(specialized)}")
    print("  unaccounted: 0")


if __name__ == "__main__":
    main()
