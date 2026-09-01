#!/usr/bin/env python3
"""Require executable evidence for every externally consumed DOS structure."""

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tests/internal_structure_coverage.json"
EXPECTED = {"PSP", "MCB", "List of Lists", "DPB", "CDS", "SFT", "SDA", "device chain"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-complete", action="store_true")
    parser.parse_args()

    manifest = json.loads(MANIFEST.read_text())
    if manifest.get("schema") != 1:
        raise AssertionError("unsupported internal-structure coverage schema")
    surfaces = manifest.get("surfaces", {})
    if set(surfaces) != EXPECTED:
        raise AssertionError(
            f"structure inventory mismatch: missing={sorted(EXPECTED - set(surfaces))}, "
            f"stale={sorted(set(surfaces) - EXPECTED)}"
        )

    makefile = (ROOT / "Makefile").read_text()
    for name, item in surfaces.items():
        source = item.get("source", "")
        evidence = item.get("evidence", [])
        if not source or not (ROOT / source).is_file():
            raise AssertionError(f"{name}: missing structure source")
        if not evidence:
            raise AssertionError(f"{name}: missing evidence")
        for relative in evidence:
            if not (ROOT / relative).is_file():
                raise AssertionError(f"{name}: missing evidence file {relative}")
        scripts = [path for path in evidence if path.endswith(".sh")]
        if not scripts or not any(path in makefile for path in scripts):
            raise AssertionError(f"{name}: runtime contract is not wired into Makefile")

    print(f"Observable DOS structures: {len(surfaces)}")
    print(f"  contract tested: {len(surfaces)}")
    print("  uncovered: 0")


if __name__ == "__main__":
    main()
