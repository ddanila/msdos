#!/usr/bin/env python3
"""Validate mutation evidence against the source-derived runtime inventory."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()

    runtime_manifest = json.loads(
        (ROOT / "tests/runtime_coverage.json").read_text()
    )
    runtime = runtime_manifest["runtime_components"]
    manifest = json.loads((ROOT / "tests/oracle_mutation_coverage.json").read_text())
    components = manifest.get("components", {})
    errors: list[str] = []

    if manifest.get("schema") != 1:
        errors.append("unsupported mutation manifest schema")

    for name, entry in components.items():
        if name not in runtime:
            errors.append(f"stale component: {name}")
            continue
        level = entry.get("level")
        if level == "killed":
            if entry.get("mutation") != "remove_artifact":
                errors.append(f"{name}: unsupported killed mutation")
            test_name = entry.get("test", "")
            test_path = ROOT / test_name
            if test_name not in runtime[name].get("evidence", []):
                errors.append(f"{name}: mutation test is not runtime evidence")
            if not test_path.is_file():
                errors.append(f"{name}: missing mutation test {test_name}")
            elif 'FLOPPY_IMAGE' not in test_path.read_text(encoding="utf-8"):
                errors.append(f"{name}: mutation test lacks an isolated image seam")
        elif level == "justified_exclusion":
            if not entry.get("note"):
                errors.append(f"{name}: exclusion lacks a justification")
        else:
            errors.append(f"{name}: invalid mutation level {level!r}")

    uncovered = sorted(set(runtime) - set(components))
    killed = sum(entry.get("level") == "killed" for entry in components.values())
    excluded = sum(
        entry.get("level") == "justified_exclusion" for entry in components.values()
    )

    if args.require_complete and uncovered:
        errors.append("uncovered runtime components: " + ", ".join(uncovered))

    print(f"Runtime component oracle mutations: {len(runtime)}")
    print(f"  killed: {killed}")
    print(f"  justified exclusions: {excluded}")
    print(f"  uncovered: {len(uncovered)}")

    if errors:
        raise SystemExit("\n".join(errors))


if __name__ == "__main__":
    main()
