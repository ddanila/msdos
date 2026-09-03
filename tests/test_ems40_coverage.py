#!/usr/bin/env python3
"""Derive and enforce LIM EMS 4.0 INT 67h function coverage."""

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tests/ems40_coverage.json"
EXPECTED = {f"{number:02X}" for number in range(0x40, 0x5E)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-complete", action="store_true")
    parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    if manifest.get("schema") != 1:
        raise AssertionError("unsupported EMS coverage schema")
    functions = manifest.get("functions", {})
    if set(functions) != EXPECTED:
        raise AssertionError(
            f"EMS inventory mismatch: missing={sorted(EXPECTED-set(functions))}, "
            f"stale={sorted(set(functions)-EXPECTED)}"
        )
    source = (ROOT / manifest["dispatcher"]).read_text(encoding="latin-1")
    block = source.split("dispatch_vector", 2)[2].split(";*************************************", 1)[0]
    handlers = re.findall(r"^\s*mkvect(?:_alias)?\s+(\w+)", block, re.MULTILINE)
    fixed = re.search(r"extrn\s+_(GetMappablePAddrArrayFixed):near\s*\n\s*dw", block)
    if fixed:
        handlers.insert(24, fixed.group(1))
    expected_handlers = [functions[f"{number:02X}"]["handler"] for number in range(0x40, 0x5E)]
    if handlers != expected_handlers:
        raise AssertionError(f"EMS dispatcher changed: {handlers}")
    makefile = (ROOT / "Makefile").read_text()
    for function, item in functions.items():
        evidence = item.get("evidence", [])
        if not evidence:
            raise AssertionError(f"EMS {function}: missing evidence")
        for relative in evidence:
            if not (ROOT / relative).is_file():
                raise AssertionError(f"EMS {function}: missing {relative}")
        scripts = [path for path in evidence if path.endswith(".sh")]
        if not scripts or not any(path in makefile for path in scripts):
            raise AssertionError(f"EMS {function}: runtime evidence is not wired")
    print(f"LIM EMS 4.0 functions: {len(functions)}")
    print(f"  contract tested: {len(functions)}")
    print("  uncovered: 0")


if __name__ == "__main__":
    main()
