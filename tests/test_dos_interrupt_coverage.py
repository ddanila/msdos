#!/usr/bin/env python3
"""Validate coverage of the DOS-owned and DOS-initialized interrupt surface."""

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tests/dos_interrupt_coverage.json"
EXPECTED = {f"{value:02X}" for value in range(0x20, 0x2A)} | {"2F"}
LEVELS = {"contract", "observed", "uncovered"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text())
    if manifest.get("schema") != 1:
        raise AssertionError("unsupported DOS interrupt coverage schema")

    source = (ROOT / manifest["vector_source"]).read_text(encoding="latin-1")
    source_assertions = {
        "20h-28h initialization": "Set vectors 20-28" in source,
        "29h preservation": "Skip INT 29H vector" in source,
        "20h handler": "addr_int_abort],OFFSET DOSGROUP:QUIT" in source,
        "21h handler": "addr_int_command],OFFSET DOSGROUP:COMMAND" in source,
        "25h handler": "addr_int_disk_read],OFFSET DOSGROUP:ABSDRD" in source,
        "26h handler": "addr_int_disk_write],OFFSET DOSGROUP:ABSDWRT" in source,
        "27h handler": "addr_int_keep_process],OFFSET DOSGROUP:Stay_resident" in source,
        "2Fh handler": "DS:[02FH * 4],OFFSET DOSGROUP:INT2F" in source,
    }
    missing_assertions = [name for name, present in source_assertions.items() if not present]
    if missing_assertions:
        raise AssertionError("vector source changed: " + ", ".join(missing_assertions))

    surfaces = manifest["surfaces"]
    excluded = manifest["excluded"]
    actual = set(surfaces) | set(excluded)
    if actual != EXPECTED:
        raise AssertionError(
            f"interrupt inventory mismatch: missing={sorted(EXPECTED - actual)}, "
            f"stale={sorted(actual - EXPECTED)}"
        )

    workflow = (ROOT / ".github/workflows/ci.yml").read_text()
    makefile = (ROOT / "Makefile").read_text()
    ci_corpus = workflow + "\n" + makefile
    counts = {level: 0 for level in LEVELS}
    for vector, item in surfaces.items():
        level = item.get("level")
        if level not in LEVELS:
            raise AssertionError(f"INT {vector}h: invalid level {level!r}")
        if not item.get("note", "").strip():
            raise AssertionError(f"INT {vector}h: missing note")
        evidence = item.get("evidence", [])
        if level != "uncovered" and not evidence:
            raise AssertionError(f"INT {vector}h: missing evidence")
        for relative in evidence:
            if not (ROOT / relative).is_file():
                raise AssertionError(f"INT {vector}h: missing evidence file {relative}")
        runnable = [path for path in evidence if path.endswith(".sh")]
        if level == "contract" and vector != "21":
            if not runnable or not any(path in ci_corpus for path in runnable):
                raise AssertionError(f"INT {vector}h: contract evidence is not wired into CI")
        counts[level] += 1

    for vector, item in excluded.items():
        if not item.get("reason", "").strip() or not item.get("evidence"):
            raise AssertionError(f"INT {vector}h: incomplete exclusion")
        for relative in item["evidence"]:
            if not (ROOT / relative).is_file():
                raise AssertionError(f"INT {vector}h: missing exclusion evidence {relative}")

    print(f"DOS interrupt surfaces: {len(EXPECTED)}")
    print(f"  contract tested: {counts['contract']}")
    print(f"  behavior observed: {counts['observed']}")
    print(f"  justified exclusions: {len(excluded)}")
    print(f"  uncovered: {counts['uncovered']}")
    incomplete = [
        vector for vector, item in surfaces.items() if item["level"] != "contract"
    ]
    if incomplete:
        print("  incomplete vectors: " + " ".join(incomplete))
    if args.require_complete and incomplete:
        raise SystemExit("DOS interrupt coverage is incomplete")


if __name__ == "__main__":
    main()
