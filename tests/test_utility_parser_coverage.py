#!/usr/bin/env python3
"""Validate source-derived switch coverage for standalone utility parsers."""

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tests/utility_parser_coverage.json"
VALID_LEVELS = {"uncovered", "observed", "contract"}


def source_switches(text, extractor="asm_db"):
    if extractor in {"asm_db", "asm_include"}:
        if extractor == "asm_include":
            text = re.sub(
                r"^IF\s+(?:FSExec|ShipDisk)\b.*?^ENDIF[^\n]*\n?",
                "", text, flags=re.IGNORECASE | re.MULTILINE | re.DOTALL,
            )
        values = re.findall(
            r"\bDB\s+[\"'](/[^\"',\s]+)[\"']\s*,\s*0", text, re.IGNORECASE
        )
    elif extractor == "c_parser_literals":
        values = re.findall(
            r"strcpy\([^;]*?[\"'](/[^\"',+\s]+)[\"']", text, re.IGNORECASE
        )
        values += re.findall(
            r"str(?:n)?icmp\([^,]+,[\"'](/[^\"']+)[\"']", text, re.IGNORECASE
        )
        values += re.findall(
            r"^\s*#define\s+\w+\s+[\"'](/[^\"']+)[\"']",
            text,
            re.IGNORECASE | re.MULTILINE,
        )
        values += [
            "/" + value
            for value in re.findall(
                r"equal_switch\([^,]+,\s*[\"']([^\"']+)[\"']",
                text,
                re.IGNORECASE,
            )
        ]
    elif extractor == "fc_code":
        parser = text.split("if(*(v[i]+j)=='/')", 1)[1].split(
            "end parse of argument", 1
        )[0]
        parser = re.sub(r"#ifdef\s+DEBUG.*?#endif", "", parser, flags=re.DOTALL)
        values = [f"/{letter}" for letter in re.findall(r"case\s+'([A-Z])'", parser)]
        if re.search(r"j\+2\)\)\s*==\s*'B'", parser):
            values.append("/LB")
        if 'strbskip((v[i]+j+1),"0123456789")' in parser:
            values.append("/NNNN")
    elif extractor == "flush13_code":
        parser = text.split("/* Parse the arguments */", 1)[1].split(
            "/* Open the device */", 1
        )[0]
        cases = set(re.findall(r"case\s+'([a-z])'", parser))
        values = [f"/{letter}" for letter in cases & {"d", "e", "l", "u", "i", "f"}]
        if "s" in cases:
            status = parser.split("case 's':", 1)[1].split("break;", 1)[0]
            suffixes = set(re.findall(r"\*cptr\s*==\s*'([a-z])'", status))
            values += ["/S"] + [f"/S{suffix}" for suffix in suffixes]
        for letter in cases & {"c", "r"}:
            values += [f"/{letter}:ON", f"/{letter}:OFF"]
        if "t" in cases and "GetNum" in parser.split("case 't':", 1)[1].split("break;", 1)[0]:
            values.append("/T:NNNN")
        if "w" in cases:
            write = parser.split("case 'w':", 1)[1].split("break;", 1)[0]
            for suffix in re.findall(r"\*cptr\s*==\s*'([a-z])'", write):
                values += [f"/W{suffix}:ON", f"/W{suffix}:OFF"]
    elif extractor == "attrib_header":
        values = re.findall(
            r"^\s*char\s+\w+\[\]\s*=\s*[\"']([+-][ARHS])[\"']",
            text, re.IGNORECASE | re.MULTILINE,
        )
        values += re.findall(r"[\"'](/S)[\"']", text, re.IGNORECASE)
    elif extractor == "c_define_switches":
        values = re.findall(
            r"^\s*#define\s+\w+\s+[\"'](/[^\"']+)[\"']",
            text, re.IGNORECASE | re.MULTILINE,
        )
    elif extractor == "fastopen_code":
        values = re.findall(
            r"^\s*E_Switch\s+DB\s+[\"'](/[^\"']+)[\"']",
            text, re.IGNORECASE | re.MULTILINE,
        )
    else:
        raise AssertionError(f"unknown parser extractor {extractor!r}")
    return {value.upper() for value in values}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    if manifest.get("schema") != 1:
        raise AssertionError("unsupported utility parser coverage schema")

    ci_corpus = (ROOT / "Makefile").read_text() + (ROOT / ".github/workflows/ci.yml").read_text()
    assembly_sources = {
        path.relative_to(ROOT).as_posix()
        for path in (ROOT / "src/CMD").rglob("*.ASM")
        if "COMMAND" not in path.parts
        and source_switches(path.read_text(encoding="latin-1"))
    }
    c_sources = {
        path.relative_to(ROOT).as_posix()
        for path in (ROOT / "src/CMD").rglob("*.C")
        if source_switches(path.read_text(encoding="latin-1"), "c_parser_literals")
    }
    include_sources = {
        path.relative_to(ROOT).as_posix()
        for path in (ROOT / "src/CMD").rglob("*.INC")
        if source_switches(path.read_text(encoding="latin-1"), "asm_include")
    }
    declared_assembly = {
        item["source"] for item in manifest["utilities"].values()
        if item.get("extractor", "asm_db") == "asm_db"
    }
    declared_c = {
        item["source"] for item in manifest["utilities"].values()
        if item.get("extractor") == "c_parser_literals"
    }
    declared_includes = {
        item["source"] for item in manifest["utilities"].values()
        if item.get("extractor") == "asm_include"
    }
    if assembly_sources != declared_assembly:
        raise AssertionError(
            f"assembly parser source mismatch; missing={sorted(assembly_sources-declared_assembly)}, "
            f"stale={sorted(declared_assembly-assembly_sources)}"
        )
    if c_sources != declared_c:
        raise AssertionError(
            f"C parser source mismatch; missing={sorted(c_sources-declared_c)}, "
            f"stale={sorted(declared_c-c_sources)}"
        )
    if include_sources != declared_includes:
        raise AssertionError(
            f"include parser source mismatch; missing={sorted(include_sources-declared_includes)}, "
            f"stale={sorted(declared_includes-include_sources)}"
        )
    if {
        item["source"] for item in manifest["utilities"].values()
        if item.get("extractor") == "fc_code"
    } != {"src/CMD/FC/FC.C"}:
        raise AssertionError("FC code-driven parser source is missing or stale")
    if {
        item["source"] for item in manifest["utilities"].values()
        if item.get("extractor") == "flush13_code"
    } != {"src/DEV/SMARTDRV/FLUSH13.C"}:
        raise AssertionError("FLUSH13 code-driven parser source is missing or stale")
    specialized_sources = {
        item.get("extractor"): item["source"] for item in manifest["utilities"].values()
        if item.get("extractor") in {"attrib_header", "c_define_switches", "fastopen_code"}
    }
    if specialized_sources != {
        "attrib_header": "src/CMD/ATTRIB/ATTRIB.H",
        "c_define_switches": "src/CMD/FDISK/PARSE.H",
        "fastopen_code": "src/CMD/FASTOPEN/FASTINIT.ASM",
    }:
        raise AssertionError(f"specialized C header parser sources are missing or stale: {specialized_sources}")
    incomplete = []
    counts = {level: 0 for level in VALID_LEVELS}
    total = 0
    for utility, definition in manifest["utilities"].items():
        source = ROOT / definition["source"]
        if not source.is_file():
            raise AssertionError(f"{utility}: missing parser source {definition['source']}")
        derived = source_switches(
            source.read_text(encoding="latin-1"), definition.get("extractor", "asm_db")
        )
        declared = {switch.upper() for switch in definition["switches"]}
        if derived != declared:
            raise AssertionError(f"{utility}: parser mismatch; missing={sorted(derived-declared)}, stale={sorted(declared-derived)}")
        for switch, item in definition["switches"].items():
            total += 1
            level = item.get("level")
            if level not in VALID_LEVELS:
                raise AssertionError(f"{utility} {switch}: invalid level {level!r}")
            counts[level] += 1
            if not item.get("note"):
                raise AssertionError(f"{utility} {switch}: missing note")
            evidence = item.get("evidence", [])
            if level == "uncovered":
                if evidence:
                    raise AssertionError(f"{utility} {switch}: uncovered item claims evidence")
                incomplete.append(f"{utility}:{switch}")
                continue
            if not evidence:
                raise AssertionError(f"{utility} {switch}: missing evidence")
            for relative in evidence:
                if not (ROOT / relative).is_file():
                    raise AssertionError(f"{utility} {switch}: missing evidence file {relative}")
            if level == "contract":
                runnable = [path for path in evidence if path.endswith(".sh")]
                if not runnable or not any(path in ci_corpus for path in runnable):
                    raise AssertionError(f"{utility} {switch}: evidence is not wired into CI")
            else:
                incomplete.append(f"{utility}:{switch}")

    print(f"Standalone utility parser switches: {total}")
    print(f"  utilities: {len(manifest['utilities'])}")
    print(f"  contract tested: {counts['contract']}")
    print(f"  behavior observed: {counts['observed']}")
    print(f"  uncovered: {counts['uncovered']}")
    if incomplete:
        print("  incomplete: " + " ".join(incomplete))
    if args.require_complete and incomplete:
        raise SystemExit("utility parser coverage incomplete")


if __name__ == "__main__":
    main()
