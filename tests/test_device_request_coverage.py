#!/usr/bin/env python3
"""Inventory installable-driver request tables and report behavioral gaps."""

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tests/device_request_coverage.json"


def table_handlers(path: Path, label: str, maximum: int) -> list[str]:
    lines = path.read_text(encoding="latin-1").splitlines()
    start_re = re.compile(rf"^\s*{re.escape(label)}(?:\s+LABEL\s+WORD|\s*:)", re.I)
    start = next((i for i, line in enumerate(lines) if start_re.search(line)), None)
    if start is None:
        raise AssertionError(f"{path}: table {label} not found")
    handlers = []
    for line in lines[start + 1:]:
        code = line.split(";", 1)[0]
        match = re.match(r"^\s*DW\s+(?:OFFSET\s+)?([^\s,]+)", code, re.I)
        if match:
            handlers.append(match.group(1).upper())
            if len(handlers) == maximum + 1:
                break
        elif (re.match(r"^\s*DB\s+", code, re.I)
              or re.match(r"^\s*MAX_CMD\s+EQU\b", code, re.I)
              or not code.strip()):
            continue
        elif handlers:
            raise AssertionError(f"{path}: unexpected line inside {label}: {line.strip()}")
    if len(handlers) != maximum + 1:
        raise AssertionError(f"{path}: {label} has {len(handlers)} commands, expected {maximum + 1}")
    return handlers


def expand(spec: str) -> set[int]:
    if "-" not in spec:
        return {int(spec)}
    first, last = map(int, spec.split("-", 1))
    return set(range(first, last + 1))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()
    data = json.loads(MANIFEST.read_text())
    if data.get("schema") != 1:
        raise AssertionError("unsupported device request coverage schema")

    total = covered = excluded = 0
    gaps = []
    for driver, table in data["tables"].items():
        maximum = table["max_command"]
        handlers = table_handlers(ROOT / table["source"], table["label"], maximum)
        claims = {}
        for spec, claim in data.get("coverage", {}).get(driver, {}).items():
            for command in expand(spec):
                if command in claims:
                    raise AssertionError(f"{driver}: command {command} claimed twice")
                if not 0 <= command <= maximum:
                    raise AssertionError(f"{driver}: command {command} outside source table")
                claims[command] = claim
        for command, handler in enumerate(handlers):
            total += 1
            claim = claims.get(command)
            if claim is None:
                gaps.append(f"{driver} command {command:02d} -> {handler}")
                continue
            if not claim.get("evidence") or not claim.get("note"):
                raise AssertionError(f"{driver}: command {command} lacks evidence or note")
            for item in claim["evidence"]:
                if not (ROOT / item).exists():
                    raise AssertionError(f"{driver}: missing evidence {item}")
            if claim["level"] == "contract":
                covered += 1
            elif claim["level"] == "excluded":
                excluded += 1
            else:
                raise AssertionError(f"{driver}: invalid level {claim['level']}")

    for driver, claim in data.get("forwarding_interfaces", {}).items():
        total += 1
        evidence = [claim["source"], *claim.get("evidence", [])]
        for item in evidence:
            if not (ROOT / item).exists():
                raise AssertionError(f"{driver}: missing evidence {item}")
        if claim.get("level") == "contract" and claim.get("note"):
            covered += 1
        else:
            gaps.append(f"{driver} forwarding/interception interface")

    print(f"Device request surfaces: {total}")
    print(f"  contract tested: {covered}")
    print(f"  justified exclusions: {excluded}")
    print(f"  uncovered: {len(gaps)}")
    for gap in gaps:
        print(f"    {gap}")
    return int(args.require_complete and bool(gaps))


if __name__ == "__main__":
    raise SystemExit(main())
