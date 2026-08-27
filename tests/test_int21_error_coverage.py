#!/usr/bin/env python3
"""Validate traceability against DOS's live INT 21h allowed-error table."""

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tests/int21_error_coverage.json"


def normalize_handler(name):
    normalized = name.strip().lstrip("$").casefold()
    aliases = {
        "xdup": "dup",
        "xdup2": "dup2",
        "extopen": "extended_open",
        "getsetmediaid": "gsetmediaid",
    }
    return aliases.get(normalized, normalized)


def dispatch_handlers(text):
    table = text.split("DISPATCH    LABEL WORD", 1)[1].split("VAL2", 1)[0]
    pattern = re.compile(
        r"^\s*short_addr\s+(\S+)\s*;\s*(\d+)\s+([0-9A-Fa-f]+)\b",
        re.MULTILINE | re.IGNORECASE,
    )
    handlers = {}
    for handler, decimal, hexadecimal in pattern.findall(table):
        call = int(decimal)
        if call != int(hexadecimal, 16):
            raise AssertionError(f"dispatch annotation mismatch for {handler}")
        handlers[normalize_handler(handler)] = f"{call:02X}"
    return handlers


def allowed_errors(text):
    handlers = dispatch_handlers(text)
    table = text.split("I21_MAP_E_TAB   LABEL   BYTE", 1)[1].split(
        "DB  0FFh", 1
    )[0]
    records = []
    current = None
    for raw_line in table.splitlines():
        line = raw_line.split(";", 1)[0]
        match = re.match(r"\s*DB\s+(.+)", line, re.IGNORECASE)
        if not match:
            continue
        tokens = [token.strip() for token in match.group(1).split(",") if token.strip()]
        if not tokens:
            continue
        if tokens[0].casefold().startswith("error_"):
            if current is None:
                raise AssertionError("orphan error-table continuation")
            current[2].extend(tokens)
        else:
            if len(tokens) < 2:
                raise AssertionError(f"malformed error-table row: {raw_line}")
            current = [tokens[0], int(tokens[1]), tokens[2:]]
            records.append(current)

    pairs = set()
    for handler, count, errors in records:
        if len(errors) != count:
            raise AssertionError(
                f"{handler}: declares {count} errors but contains {len(errors)}"
            )
        key = normalize_handler(handler)
        if key not in handlers:
            raise AssertionError(f"error-table handler is absent from dispatch: {handler}")
        call = handlers[key]
        for error in errors:
            pair = (call, error.casefold())
            if pair in pairs:
                raise AssertionError(f"duplicate live error pair: {pair}")
            pairs.add(pair)
    return pairs


def item_pair(item):
    return item["function"].upper(), item["error"].casefold()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--require-complete",
        action="store_true",
        help="fail unless every live allowed-error pair has evidence or an exclusion",
    )
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text())
    if manifest.get("schema") != 1:
        raise AssertionError("unsupported INT 21h error coverage schema")
    source = ROOT / manifest["error_table_source"]
    expected = allowed_errors(source.read_text(encoding="latin-1"))
    workflow = (ROOT / ".github/workflows/ci.yml").read_text()
    makefile = (ROOT / "Makefile").read_text()
    ci_corpus = workflow + "\n" + makefile

    contract_items = manifest["contracts"]
    excluded_items = manifest["excluded"]
    contracts = {item_pair(item) for item in contract_items}
    excluded = {item_pair(item) for item in excluded_items}
    if len(contracts) != len(contract_items):
        raise AssertionError("duplicate INT 21h error contract")
    if len(excluded) != len(excluded_items):
        raise AssertionError("duplicate INT 21h error exclusion")
    overlap = contracts & excluded
    if overlap:
        raise AssertionError(f"error pairs are both covered and excluded: {sorted(overlap)}")
    unknown = (contracts | excluded) - expected
    if unknown:
        raise AssertionError(f"manifest contains non-live error pairs: {sorted(unknown)}")

    for item in contract_items:
        if not item.get("note"):
            raise AssertionError(f"{item_pair(item)}: missing contract note")
        evidence = item.get("evidence", [])
        if not evidence:
            raise AssertionError(f"{item_pair(item)}: missing evidence")
        for relative in evidence:
            if not (ROOT / relative).is_file():
                raise AssertionError(f"{item_pair(item)}: missing evidence file {relative}")
        runnable = [path for path in evidence if path.endswith(".sh")]
        if not runnable or not any(path in ci_corpus for path in runnable):
            raise AssertionError(f"{item_pair(item)}: evidence is not wired into CI")
    for item in excluded_items:
        if not item.get("reason", "").strip():
            raise AssertionError(f"{item_pair(item)}: missing exclusion reason")
        evidence = item.get("evidence", [])
        if not evidence:
            raise AssertionError(f"{item_pair(item)}: missing exclusion evidence")
        for relative in evidence:
            if not (ROOT / relative).is_file():
                raise AssertionError(
                    f"{item_pair(item)}: missing exclusion evidence file {relative}"
                )

    uncovered = expected - contracts - excluded
    print(f"INT 21h allowed error contracts: {len(expected)}")
    print(f"  contract tested: {len(contracts)}")
    print(f"  justified exclusions: {len(excluded)}")
    print(f"  uncovered: {len(uncovered)}")
    if uncovered:
        grouped = {}
        for call, error in sorted(uncovered):
            grouped.setdefault(call, []).append(error.removeprefix("error_"))
        print("  incomplete calls: " + " ".join(grouped))

    if args.require_complete and uncovered:
        raise SystemExit("INT 21h allowed-error coverage is incomplete")


if __name__ == "__main__":
    main()
