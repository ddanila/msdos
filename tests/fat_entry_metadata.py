#!/usr/bin/env python3
"""Print stable FAT12/16 directory-entry metadata for a root file."""

import struct
import sys

image, offset_text, filename = sys.argv[1:]
offset = int(offset_text, 0)
name, dot, extension = filename.upper().partition(".")
short_name = name[:8].ljust(8) + extension[:3].ljust(3)

with open(image, "rb") as stream:
    stream.seek(offset)
    boot = stream.read(512)
    bytes_per_sector = struct.unpack_from("<H", boot, 11)[0]
    reserved = struct.unpack_from("<H", boot, 14)[0]
    fats = boot[16]
    root_entries = struct.unpack_from("<H", boot, 17)[0]
    sectors_per_fat = struct.unpack_from("<H", boot, 22)[0]
    root_offset = offset + (reserved + fats * sectors_per_fat) * bytes_per_sector
    stream.seek(root_offset)
    root = stream.read(root_entries * 32)

for position in range(0, len(root), 32):
    entry = root[position:position + 32]
    if entry[0] in (0, 0xE5) or entry[11] == 0x0F:
        continue
    if entry[:11].decode("ascii", errors="replace") == short_name:
        attributes = entry[11]
        time, date = struct.unpack_from("<HH", entry, 22)
        size = struct.unpack_from("<I", entry, 28)[0]
        print(f"{attributes:02x} {date:04x} {time:04x} {size}")
        break
else:
    raise SystemExit(f"{filename}: root entry not found")
