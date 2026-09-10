#!/usr/bin/env python3
"""Build EGA866.CPI and review sheets from pinned local font inputs.

The binary layout follows src/DEV/DISPLAY/EGA/{CPI-HEAD,437-CPI}.ASM:
one EGA code page, absolute file offsets, and 16/14/8-row screen fonts.
"""

import argparse
import hashlib
import json
from pathlib import Path
import struct

from audit_ru_fonts import LOCALE, audit, contact_png


def build_fonts(directory=LOCALE):
    report = json.loads(audit(directory)["font-audit.json"])
    edits = json.loads((directory / "font-edits.json").read_text())
    seen = set()
    for edit in edits["edits"]:
        height, byte = edit["height"], edit["byte"]
        key = (height, byte)
        if key in seen or height not in (8, 14, 16) or not 0 <= byte <= 255:
            raise ValueError(f"invalid or duplicate font edit: {key}")
        seen.add(key)
        rows = bytes.fromhex(edit["rows_hex"])
        if len(rows) != height:
            raise ValueError(f"wrong edited glyph height: {key}")
        report["fonts"][str(height)]["glyphs"][byte].update(
            rows=list(rows), status="edited", source=edit["source"],
            license=edit["license"], operation=edit["operation"])
    fonts = {}
    for height in (8, 14, 16):
        glyphs = report["fonts"][str(height)]["glyphs"]
        for glyph in glyphs:
            if glyph["status"] not in ("present", "edited", "intentional-blank"):
                raise ValueError(f"unresolved glyph at {height}/{glyph['byte']:02X}")
            if not any(glyph["rows"]) and glyph["byte"] not in (0, 32, 255):
                raise ValueError(f"unexpected blank at {height}/{glyph['byte']:02X}")
        fonts[height] = glyphs
    return fonts


def pack_cpi(fonts, page=866, pack_name="Russian"):
    data = bytearray()
    for height in (16, 14, 8):
        data.extend(struct.pack("<BBBBH", height, 8, 0, 0, 256))
        data.extend(byte for glyph in fonts[height] for byte in glyph["rows"])
    # File header (23), info count (2), entry header (28), font header (6).
    result = b"\xffFONT   " + bytes(8) + struct.pack("<HBIH", 1, 1, 23, 1)
    result += struct.pack("<HIH8sH6sI", 28, 59 + len(data), 1, b"EGA     ",
                          page, bytes(6), 53)
    result += struct.pack("<HHH", 1, 3, len(data)) + data
    result += (f"CP{page} screen fonts: Cozette (MIT), 512_8 sans (Unlicense).\r\n"
               f"See the {pack_name} pack documentation for source notices.\r\n\x1a").encode("ascii")
    return result


def review_outputs(fonts, cpi):
    report = {"schema_version": 1, "status": "complete-source-coverage",
              "cpi_sha256": hashlib.sha256(cpi).hexdigest(), "fonts": {}}
    outputs = {}
    for height, glyphs in fonts.items():
        payload = bytes(byte for glyph in glyphs for byte in glyph["rows"])
        report["fonts"][str(height)] = {
            "sha256": hashlib.sha256(payload).hexdigest(),
            "glyphs": [{**{k: v for k, v in glyph.items() if k != "rows"},
                        "rows_hex": bytes(glyph["rows"]).hex()} for glyph in glyphs],
        }
        outputs[f"selected-8x{height}.png"] = contact_png(glyphs, height)
    outputs["selected-fonts.json"] = (json.dumps(report, indent=2) + "\n").encode()
    return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--locale", type=Path, default=LOCALE,
                        help="locale directory with pinned manifest and glyph edits")
    parser.add_argument("--output", type=Path, help="write the CPI build artifact")
    parser.add_argument("--review", action="store_true", help="regenerate selected-font reviews")
    parser.add_argument("--check", action="store_true", help="check selected-font reviews")
    args = parser.parse_args()
    if not (args.output or args.review or args.check):
        parser.error("specify --output, --review or --check")
    manifest = json.loads((args.locale / "manifest.json").read_text())
    fonts = build_fonts(args.locale)
    cpi = pack_cpi(fonts, manifest["code_page"], manifest.get("pack_name", "Russian"))
    if args.check or args.review:
        for name, data in review_outputs(fonts, cpi).items():
            path = args.locale / "review" / name
            if args.check:
                if not path.exists() or path.read_bytes() != data:
                    raise SystemExit(f"stale selected-font review: {path}")
            else:
                path.write_bytes(data)
    if args.output:
        args.output.write_bytes(cpi)


if __name__ == "__main__":
    main()
