#!/usr/bin/env python3
"""Extract the 128 eight-byte GRAFTABL glyphs from an assembly source file."""

import argparse
import re
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    source = args.source.read_text(errors="replace")
    table = source.split("EQU\tTHIS BYTE", 1)[1].split("\n\tDW\t", 1)[0]
    glyphs = bytes(int(bits, 2) for bits in re.findall(r"^\s*DB\s+([01]{8})B", table, re.MULTILINE))
    if len(glyphs) != 128 * 8:
        raise SystemExit(f"expected 1024 glyph bytes in {args.source}, found {len(glyphs)}")
    args.output.write_bytes(glyphs)


if __name__ == "__main__":
    main()
