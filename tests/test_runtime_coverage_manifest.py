#!/usr/bin/env python3
"""Validate shipped runtime and CONFIG.SYS behavioral traceability."""

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tests/runtime_coverage.json"
RUNTIME_SUFFIXES = ("COM", "EXE", "SYS", "OVL")
VALID_LEVELS = {"uncovered", "observed", "contract"}


def shipped_runtime_components(make_text):
    artifacts = make_text.split("ARTIFACTS :=", 1)[1].split("\n\ntest:", 1)[0]
    artifact_names = {
        path.rsplit("/", 1)[-1].upper()
        for path in re.findall(
            r"\b[\w./-]+\.(?:" + "|".join(RUNTIME_SUFFIXES) + r")\b",
            artifacts,
            re.IGNORECASE,
        )
    }
    floppy_recipe = make_text.split("$(FLOPPY):", 1)[1].split(
        "\n# Enter one jobserver-aware", 1
    )[0]
    deployed_names = {
        name.upper()
        for name in re.findall(
            r"::([\w.-]+\.(?:" + "|".join(RUNTIME_SUFFIXES) + r"))",
            floppy_recipe,
            re.IGNORECASE,
        )
    }
    return artifact_names | deployed_names


def config_directives(source_text):
    table = source_text.split("COMTAB\tLABEL\tBYTE", 1)[1].split("\n\tDB\t0", 1)[0]
    directives = {
        name.upper()
        for name in re.findall(
            r'^\s*DB\s+\d+,\s*"([A-Z]+)"', table, re.IGNORECASE | re.MULTILINE
        )
    }
    directives.update(
        name.upper()
        for name in re.findall(
            r"^[a-z_]+_lit\s+db\s+'([A-Z]+)'",
            source_text,
            re.IGNORECASE | re.MULTILINE,
        )
    )
    return directives


def select_modes(source_text):
    """Derive SELECT.EXE's accepted positional mode keywords."""
    return {
        value.upper()
        for value in re.findall(
            r"^KEYWORD_[A-Z0-9_]+\s+DB\s+'([A-Z]+)',0",
            source_text,
            re.IGNORECASE | re.MULTILINE,
        )
    }


def validate_items(items, expected, category, ci_corpus):
    declared = set(items)
    missing = expected - declared
    extra = declared - expected
    if missing:
        raise AssertionError(f"{category}: missing manifest entries: {sorted(missing)}")
    if extra:
        raise AssertionError(f"{category}: stale manifest entries: {sorted(extra)}")

    for name, item in items.items():
        level = item.get("level")
        if level not in VALID_LEVELS:
            raise AssertionError(f"{category}/{name}: invalid level {level!r}")
        if not item.get("note"):
            raise AssertionError(f"{category}/{name}: missing coverage note")
        evidence = item.get("evidence", [])
        if level == "uncovered":
            if evidence:
                raise AssertionError(
                    f"{category}/{name}: uncovered item must not claim evidence"
                )
            continue
        if not evidence:
            raise AssertionError(f"{category}/{name}: missing evidence")
        for relative in evidence:
            if not (ROOT / relative).is_file():
                raise AssertionError(
                    f"{category}/{name}: evidence does not exist: {relative}"
                )
        if level == "contract":
            runnable = [relative for relative in evidence if relative.endswith(".sh")]
            if not runnable or not any(path in ci_corpus for path in runnable):
                raise AssertionError(
                    f"{category}/{name}: contract evidence is not wired into CI"
                )


def summarize(label, items):
    counts = {
        level: sum(item["level"] == level for item in items.values())
        for level in ("contract", "observed", "uncovered")
    }
    print(f"{label}: {len(items)}")
    print(f"  contract tested: {counts['contract']}")
    print(f"  behavior observed: {counts['observed']}")
    print(f"  uncovered: {counts['uncovered']}")
    incomplete = sorted(
        name for name, item in items.items() if item["level"] != "contract"
    )
    if incomplete:
        print("  incomplete: " + " ".join(incomplete))
    return incomplete


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--require-complete",
        action="store_true",
        help="fail unless every shipped runtime and CONFIG.SYS entry is contract tested",
    )
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text())
    if manifest.get("schema") != 1:
        raise AssertionError("unsupported runtime coverage manifest schema")

    make_text = (ROOT / "Makefile").read_text()
    workflow_text = (ROOT / ".github/workflows/ci.yml").read_text()
    ci_corpus = make_text + "\n" + workflow_text
    runtime = manifest["runtime_components"]
    modes = manifest["select_modes"]
    directives = manifest["config_directives"]

    validate_items(
        runtime,
        shipped_runtime_components(make_text),
        "runtime component",
        ci_corpus,
    )
    validate_items(
        modes,
        select_modes(
            (ROOT / "src/SELECT/SCN_PARM.ASM").read_text(
                encoding="latin-1"
            )
        ),
        "SELECT.EXE mode",
        ci_corpus,
    )
    validate_items(
        directives,
        config_directives(
            (ROOT / "src/BIOS/SYSINIT2.ASM").read_text(encoding="latin-1")
            + "\n"
            + (ROOT / "src/BIOS/SYSMENU.ASM").read_text(encoding="latin-1")
        ),
        "CONFIG.SYS directive",
        ci_corpus,
    )

    incomplete = summarize("Shipped runtime components", runtime)
    incomplete += summarize("SELECT.EXE modes", modes)
    incomplete += summarize("CONFIG.SYS directives", directives)
    if args.require_complete and incomplete:
        raise SystemExit("runtime coverage incomplete for: " + " ".join(incomplete))


if __name__ == "__main__":
    main()
