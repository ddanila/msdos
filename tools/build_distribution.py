#!/usr/bin/env python3
"""Build deterministic boot and compressed-data FAT12 installation disks."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import struct
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("szdd", ROOT / "tools" / "szdd.py")
szdd = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(szdd)

SECTOR_SIZE = 512
TOTAL_SECTORS = 2880
RESERVED = 1
FATS = 2
SECTORS_PER_FAT = 9
ROOT_ENTRIES = 224
ROOT_SECTORS = 14
DATA_START = RESERVED + FATS * SECTORS_PER_FAT + ROOT_SECTORS
DATA_CLUSTERS = TOTAL_SECTORS - DATA_START
FIXED_DATE = ((1991 - 1980) << 9) | (6 << 5) | 11
FIXED_TIME = 0


@dataclass(frozen=True)
class MediaFile:
    name: str
    data: bytes
    attributes: int = 0x20


def dos_name(name: str) -> bytes:
    if "/" in name or "\\" in name:
        raise ValueError(f"media files must be root-level: {name}")
    stem, dot, extension = name.upper().partition(".")
    if not stem or len(stem) > 8 or len(extension) > 3 or (not dot and extension):
        raise ValueError(f"not an 8.3 filename: {name}")
    return stem.ljust(8).encode("ascii") + extension.ljust(3).encode("ascii")


def compressed_name(destination: str) -> tuple[str, int]:
    stem, dot, extension = destination.upper().partition(".")
    if dot and extension:
        missing = ord(extension[-1])
        extension = extension[:-1] + "_"
        return stem + "." + extension, missing
    missing = ord(stem[-1])
    return stem[:-1] + "_", missing


def set_fat12(fat: bytearray, cluster: int, value: int) -> None:
    offset = cluster + cluster // 2
    if cluster & 1:
        fat[offset] = (fat[offset] & 0x0F) | ((value << 4) & 0xF0)
        fat[offset + 1] = (value >> 4) & 0xFF
    else:
        fat[offset] = value & 0xFF
        fat[offset + 1] = (fat[offset + 1] & 0xF0) | ((value >> 8) & 0x0F)


def build_image(files: list[MediaFile], boot_sector: bytes, label: str, serial: int) -> bytes:
    if len(boot_sector) != SECTOR_SIZE:
        raise ValueError("boot sector must be exactly 512 bytes")
    if len(files) + 1 > ROOT_ENTRIES:
        raise ValueError("too many root-directory entries")
    image = bytearray(SECTOR_SIZE * TOTAL_SECTORS)
    image[:SECTOR_SIZE] = boot_sector
    struct.pack_into("<H", image, 11, SECTOR_SIZE)
    image[13] = 1
    struct.pack_into("<H", image, 14, RESERVED)
    image[16] = FATS
    struct.pack_into("<H", image, 17, ROOT_ENTRIES)
    struct.pack_into("<H", image, 19, TOTAL_SECTORS)
    image[21] = 0xF0
    struct.pack_into("<H", image, 22, SECTORS_PER_FAT)
    struct.pack_into("<H", image, 24, 18)
    struct.pack_into("<H", image, 26, 2)
    struct.pack_into("<I", image, 28, 0)
    struct.pack_into("<I", image, 32, 0)
    image[36] = 0
    image[38] = 0x29
    struct.pack_into("<I", image, 39, serial)
    image[43:54] = label.ljust(11).encode("ascii")
    image[54:62] = b"FAT12   "
    image[510:512] = b"\x55\xaa"

    fat = bytearray(SECTOR_SIZE * SECTORS_PER_FAT)
    fat[:3] = b"\xf0\xff\xff"
    root = bytearray(SECTOR_SIZE * ROOT_SECTORS)
    next_cluster = 2
    for index, item in enumerate(files):
        clusters = (len(item.data) + SECTOR_SIZE - 1) // SECTOR_SIZE
        first = next_cluster if clusters else 0
        if next_cluster + clusters - 2 > DATA_CLUSTERS:
            raise ValueError(f"disk full while adding {item.name}")
        for number in range(clusters):
            cluster = next_cluster + number
            set_fat12(fat, cluster, 0xFFF if number + 1 == clusters else cluster + 1)
            start = (DATA_START + cluster - 2) * SECTOR_SIZE
            chunk = item.data[number * SECTOR_SIZE:(number + 1) * SECTOR_SIZE]
            image[start:start + len(chunk)] = chunk
        next_cluster += clusters
        offset = index * 32
        root[offset:offset + 11] = dos_name(item.name)
        root[offset + 11] = item.attributes
        struct.pack_into("<HHH", root, offset + 22, FIXED_TIME, FIXED_DATE, first)
        struct.pack_into("<I", root, offset + 28, len(item.data))

    label_offset = len(files) * 32
    root[label_offset:label_offset + 11] = label.ljust(11).encode("ascii")
    root[label_offset + 11] = 0x08
    struct.pack_into("<HH", root, label_offset + 22, FIXED_TIME, FIXED_DATE)
    for fat_number in range(FATS):
        start = (RESERVED + fat_number * SECTORS_PER_FAT) * SECTOR_SIZE
        image[start:start + len(fat)] = fat
    root_start = (RESERVED + FATS * SECTORS_PER_FAT) * SECTOR_SIZE
    image[root_start:root_start + len(root)] = root
    return bytes(image)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=ROOT / "distribution" / "files.json")
    parser.add_argument("--output", type=Path, default=ROOT / "out" / "distribution")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    if manifest.get("schema") != 1:
        raise SystemExit("unsupported distribution manifest")
    boot_path = ROOT / "out" / "floppy.img"
    if not boot_path.is_file():
        raise SystemExit("run make deploy first")
    boot_sector = boot_path.read_bytes()[:SECTOR_SIZE]

    boot_files: list[MediaFile] = []
    packing: list[tuple[int, str, str, int, str]] = []
    destinations: set[str] = set()
    for relative, destination in manifest["boot"]:
        if destination in destinations:
            raise ValueError(f"duplicate destination {destination}")
        destinations.add(destination)
        data = (ROOT / relative).read_bytes()
        attributes = 0x07 if destination in {"IO.SYS", "MSDOS.SYS"} else 0x20
        boot_files.append(MediaFile(destination, data, attributes))
        packing.append((1, destination, destination, len(data), hashlib.sha256(data).hexdigest()))

    compressed_files: list[MediaFile] = []
    for relative, destination in manifest["compressed"]:
        if destination in destinations:
            raise ValueError(f"duplicate destination {destination}")
        destinations.add(destination)
        data = (ROOT / relative).read_bytes()
        media_name, missing = compressed_name(destination)
        packed = szdd.encode(data, missing)
        compressed_files.append(MediaFile(media_name, packed))
        packing.append((2, media_name, destination, len(data), hashlib.sha256(data).hexdigest()))

    lines = ["Disk  Stored name  Installed name  Size  SHA-256"]
    lines.extend(f"{disk:>4}  {stored:<11}  {installed:<14}  {size:>7}  {digest}" for disk, stored, installed, size, digest in packing)
    packing_data = ("\r\n".join(lines) + "\r\n").encode("ascii")
    boot_files.append(MediaFile("PACKING.LST", packing_data))
    compressed_files.append(MediaFile("PACKING.LST", packing_data))
    setup_lines = []
    for relative, destination in manifest["compressed"]:
        media_name, _ = compressed_name(destination)
        setup_lines.append(f"{media_name}|{destination}")
    setup_data = ("\r\n".join(setup_lines) + "\r\n").encode("ascii")
    compressed_files.append(MediaFile("SETUP.DAT", setup_data))

    args.output.mkdir(parents=True, exist_ok=True)
    disk1 = build_image(boot_files, boot_sector, "MSDOS5_1", 0x05000001)
    disk2 = build_image(compressed_files, boot_sector, "MSDOS5_2", 0x05000002)
    (args.output / "disk1.img").write_bytes(disk1)
    (args.output / "disk2.img").write_bytes(disk2)
    result = {
        "schema": 1,
        "disks": [
            {"file": "disk1.img", "sha256": hashlib.sha256(disk1).hexdigest()},
            {"file": "disk2.img", "sha256": hashlib.sha256(disk2).hexdigest()},
        ],
        "files": len(packing),
    }
    (args.output / "manifest.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="ascii"
    )
    print(f"Built 2 deterministic installation disks with {len(packing)} files")


if __name__ == "__main__":
    main()
