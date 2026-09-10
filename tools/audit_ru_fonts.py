#!/usr/bin/env python3
"""Audit local CP866 font candidates; missing glyphs never silently fall back.

This produces review artifacts, not installable CPI fonts. Only the standard
library is needed. Source licenses and hashes live in locales/ru/manifest.json.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
LOCALE = ROOT / "locales/ru"


def read_bdf(path):
    glyphs = {}
    for block in path.read_text().split("STARTCHAR ")[1:]:
        lines = block.splitlines()
        code = int(next(x for x in lines if x.startswith("ENCODING ")).split()[1])
        width, height, x, y = map(int, next(
            x for x in lines if x.startswith("BBX ")).split()[1:])
        start = lines.index("BITMAP") + 1
        rows = [int(row, 16) for row in lines[start:start + height]]
        if len(rows) != height or lines[start + height] != "ENDCHAR":
            raise ValueError(f"invalid BDF bitmap: {code}")
        if code >= 0:
            if code in glyphs:
                raise ValueError(f"duplicate BDF encoding: {code}")
            glyphs[code] = (width, height, x, y, rows)
    return glyphs


def read_short_font(directory):
    data = (directory / "512_8_sans.fnt").read_bytes()
    if len(data) != 512 * 8:
        raise ValueError("512_8 bitmap length changed")
    mapping = {code: code for code in range(32, 127)}
    for code, index in re.findall(
            r"CDPT\(0x([0-9A-Fa-f]+)\) FIDX\(0x([0-9A-Fa-f]+)\)",
            (directory / "512_8_sans.tab").read_text()):
        mapping[int(code, 16)] = int(index, 16)
    return {code: (index, list(data[index * 8:(index + 1) * 8]))
            for code, index in mapping.items()}


def place_bdf(glyph, height):
    """Center the 6x13 advance cell in 8xh, preserving the BDF baseline.

    Reject lit pixels outside the destination instead of truncating them.
    One extra row follows the 13-row cell at height 14; height 16 has one
    row above and two below. Box edges need explicit edits in a later step.
    """
    width, source_height, x_offset, y_offset, source = glyph
    rows = [0] * height
    clipped = False
    top = (height - 13) // 2 + 10 - y_offset - source_height
    stride = ((width + 7) // 8) * 8
    for sy, bits in enumerate(source):
        for sx in range(width):
            if bits & (1 << (stride - 1 - sx)):
                x, y = 1 + x_offset + sx, top + sy
                if not (0 <= x < 8 and 0 <= y < height):
                    clipped = True
                else:
                    rows[y] |= 0x80 >> x
    return rows, clipped


def contact_png(glyphs, height):
    # 16x16 slots in byte order. Blue = missing/clipped; red = cell boundary.
    scale, cell_width, cell_height = 3, 12, height + 4
    width, image_height = 16 * cell_width * scale, 16 * cell_height * scale
    pixels = bytearray([255]) * (width * image_height * 3)
    def dot(x, y, color):
        for dy in range(scale):
            for dx in range(scale):
                offset = ((y * scale + dy) * width + x * scale + dx) * 3
                pixels[offset:offset + 3] = bytes(color)
    for item in glyphs:
        slot = item["byte"]
        ox, oy = (slot % 16) * cell_width, (slot // 16) * cell_height
        dot(ox, oy, (200, 70, 70))
        rows = item["rows"]
        if item["status"] in ("missing", "clipped"):
            for y in range(height):
                dot(ox + 2 + y % 8, oy + 2 + y, (40, 90, 230))
        for y, bits in enumerate(rows):
            for x in range(8):
                if bits & (0x80 >> x):
                    dot(ox + 2 + x, oy + 2 + y, (0, 0, 0))
    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data)))
    raw = b"".join(b"\0" + pixels[y * width * 3:(y + 1) * width * 3]
                   for y in range(image_height))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, image_height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def audit(directory=LOCALE):
    manifest = json.loads((directory / "manifest.json").read_text())
    page = manifest["code_page"]
    for source in manifest["sources"]:
        data = (directory / source["path"]).read_bytes()
        if hashlib.sha256(data).hexdigest() != source["sha256"]:
            raise ValueError(f"source hash mismatch: {source['path']}")
    published = {}
    for line in (directory / f"upstream/CP{page}.TXT").read_text().splitlines():
        if line.startswith("0x"):
            byte, code = line.split()[:2]
            published[int(byte, 16)] = int(code, 16)
    if sorted(published) != list(range(256)) or manifest["unicode_mapping"] != [
            published[i] for i in range(256)]:
        raise ValueError(f"manifest differs from published CP{page} mapping")
    display = manifest["display_mapping"]
    if len(display) != 256 or display[32:127] != manifest["unicode_mapping"][32:127] or (
            display[128:] != manifest["unicode_mapping"][128:]):
        raise ValueError("display mapping changed a printable slot")
    inputs = manifest.get("font_inputs", {})
    short = read_short_font(directory / inputs.get("short", "upstream/512_8"))
    tall = read_bdf(directory / inputs.get("tall", "upstream/cozette/cozette.bdf"))
    report = {"schema_version": 1, "status": "prototype-not-qualified", "fonts": {}}
    outputs = {}
    for height in (8, 14, 16):
        glyphs = []
        for byte, code in enumerate(display):
            item = {"byte": byte, "unicode": f"U+{code:04X}", "rows": [0] * height}
            if byte == 0:
                item.update(status="intentional-blank", source="DOS blank slot policy")
            elif height == 8 and code in short:
                index, rows = short[code]
                item.update(status="present", source=f"512_8 index {index}", rows=rows)
            elif height != 8 and code in tall:
                rows, clipped = place_bdf(tall[code], height)
                item.update(status="clipped" if clipped else "present", source="Cozette", rows=rows)
            else:
                item.update(status="missing", source=None)
            if item["status"] == "present" and not any(item["rows"]) and byte not in (32, 255):
                item["status"] = "unexpected-blank"
            glyphs.append(item)
        report["fonts"][str(height)] = {
            "counts": {state: sum(x["status"] == state for x in glyphs)
                       for state in sorted({x["status"] for x in glyphs})},
            "glyphs": glyphs,
        }
        outputs[f"contact-8x{height}.png"] = contact_png(glyphs, height)
    outputs["font-audit.json"] = (json.dumps(report, indent=2) + "\n").encode()
    return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--locale", type=Path, default=LOCALE,
                        help="locale directory with manifest and pinned inputs")
    parser.add_argument("--check", action="store_true", help="reject stale review artifacts")
    args = parser.parse_args()
    outputs = audit(args.locale)
    destination = args.locale / "review"
    if not args.check:
        destination.mkdir(parents=True, exist_ok=True)
    for name, data in outputs.items():
        path = destination / name
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                raise SystemExit(f"stale font review artifact: {path}")
        else:
            path.write_bytes(data)
    report = json.loads(outputs["font-audit.json"])
    for height, font in report["fonts"].items():
        print(f"8x{height}: {font['counts']}")


if __name__ == "__main__":
    main()
