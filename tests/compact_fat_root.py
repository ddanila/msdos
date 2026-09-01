#!/usr/bin/env python3
"""Remove VFAT/deleted root slots and put DOS system files first."""

import argparse
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    args = parser.parse_args()

    disk = bytearray(args.image.read_bytes())
    bytes_per_sector = int.from_bytes(disk[11:13], "little")
    reserved = int.from_bytes(disk[14:16], "little")
    fats = disk[16]
    root_entries = int.from_bytes(disk[17:19], "little")
    sectors_per_fat = int.from_bytes(disk[22:24], "little")
    if bytes_per_sector != 512 or not root_entries or not sectors_per_fat:
        parser.error("image does not have a supported FAT12/16 BPB")

    root = (reserved + fats * sectors_per_fat) * bytes_per_sector
    size = root_entries * 32
    entries = []
    for offset in range(root, root + size, 32):
        entry = bytes(disk[offset : offset + 32])
        if entry[0] == 0:
            break
        if entry[0] == 0xE5 or entry[11] == 0x0F:
            continue
        entries.append(entry)

    system_names = (b"IO      SYS", b"MSDOS   SYS")
    by_name = {entry[:11]: entry for entry in entries}
    missing = [name.decode("ascii") for name in system_names if name not in by_name]
    if missing:
        parser.error("missing system root entry: " + ", ".join(missing))
    ordered = [by_name[name] for name in system_names]
    ordered.extend(entry for entry in entries if entry[:11] not in system_names)

    disk[root : root + size] = b"\0" * size
    for index, entry in enumerate(ordered):
        start = root + index * 32
        disk[start : start + 32] = entry
    args.image.write_bytes(disk)


if __name__ == "__main__":
    main()
