#!/usr/bin/env python3
"""Reject serial test batches whose command echo can satisfy their own oracle."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
failures: list[str] = []
checked = 0

for script in sorted((ROOT / "tests").glob("test*.sh")):
    lines = script.read_text(encoding="utf-8").splitlines()
    for index, line in enumerate(lines):
        if "printf" not in line or "CTTY AUX" not in line:
            continue
        checked += 1
        # Inline batches may put both commands in one printf.  For block-built
        # batches, require ECHO OFF on the immediately preceding nonblank line.
        prior = ""
        for candidate in reversed(lines[:index]):
            if candidate.strip():
                prior = candidate
                break
        if "@ECHO OFF" not in line and "@ECHO OFF" not in prior:
            failures.append(
                f"{script.relative_to(ROOT)}:{index + 1}: "
                "CTTY AUX batch must begin with @ECHO OFF"
            )

if failures:
    print("Serial batch oracle isolation failed:", file=sys.stderr)
    print("\n".join(f"  {failure}" for failure in failures), file=sys.stderr)
    sys.exit(1)

print(f"Serial batch oracle isolation: {checked} CTTY AUX batches protected")
