#!/usr/bin/env python3
"""Deterministic Microsoft SZDD encoder/decoder used by DOS 5 media tooling."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


MAGIC = b"SZDD\x88\xf0\x27\x33"
WINDOW_SIZE = 4096
WINDOW_START = 0xFEE
MAX_MATCH = 18


def encode(data: bytes, missing_character: int = 0) -> bytes:
    if not 0 <= missing_character <= 255:
        raise ValueError("missing character must fit in one byte")
    window = bytearray(b" " * WINDOW_SIZE)
    positions = {value: set() for value in range(256)}
    positions[0x20].update(range(WINDOW_SIZE))
    cursor = WINDOW_START
    source = 0
    payload = bytearray()

    def add_output(value: int) -> None:
        nonlocal cursor
        positions[window[cursor]].discard(cursor)
        window[cursor] = value
        positions[value].add(cursor)
        cursor = (cursor + 1) & 0xFFF

    while source < len(data):
        flag_offset = len(payload)
        payload.append(0)
        flags = 0
        for bit in range(8):
            if source >= len(data):
                break
            best_position = 0
            best_length = 0
            candidates = positions[data[source]]
            # Nearest references make overlap runs effective. Limiting the
            # search keeps builds quick without changing format correctness.
            ordered = sorted(candidates, key=lambda item: (cursor - item) & 0xFFF)
            for candidate in ordered[:256]:
                distance = (cursor - candidate) & 0xFFF
                if distance == 0:
                    distance = WINDOW_SIZE
                length = 1
                limit = min(MAX_MATCH, len(data) - source)
                while length < limit:
                    if length >= distance:
                        value = data[source + length - distance]
                    else:
                        value = window[(candidate + length) & 0xFFF]
                    if value != data[source + length]:
                        break
                    length += 1
                if length > best_length:
                    best_position, best_length = candidate, length
                    if length == limit:
                        break
            if best_length >= 3:
                payload.append(best_position & 0xFF)
                payload.append(((best_position >> 4) & 0xF0) | (best_length - 3))
                for value in data[source:source + best_length]:
                    add_output(value)
                source += best_length
            else:
                flags |= 1 << bit
                value = data[source]
                payload.append(value)
                add_output(value)
                source += 1
        payload[flag_offset] = flags

    return MAGIC + bytes((0x41, missing_character)) + struct.pack("<I", len(data)) + payload


def decode(stream: bytes) -> tuple[bytes, int]:
    if len(stream) < 14 or stream[:8] != MAGIC or stream[8] != 0x41:
        raise ValueError("not an SZDD stream")
    missing_character = stream[9]
    expected = struct.unpack_from("<I", stream, 10)[0]
    window = bytearray(b" " * WINDOW_SIZE)
    cursor = WINDOW_START
    source = 14
    output = bytearray()
    while len(output) < expected:
        if source >= len(stream):
            raise ValueError("truncated SZDD stream")
        flags = stream[source]
        source += 1
        for bit in range(8):
            if len(output) >= expected:
                break
            if flags & (1 << bit):
                if source >= len(stream):
                    raise ValueError("truncated SZDD literal")
                values = (stream[source],)
                source += 1
            else:
                if source + 2 > len(stream):
                    raise ValueError("truncated SZDD match")
                first, second = stream[source:source + 2]
                source += 2
                match = first | ((second & 0xF0) << 4)
                length = (second & 0x0F) + 3
                values = []
                for _ in range(length):
                    value = window[match]
                    values.append(value)
                    window[cursor] = value
                    cursor = (cursor + 1) & 0xFFF
                    match = (match + 1) & 0xFFF
                    if len(output) + len(values) >= expected:
                        break
                output.extend(values)
                continue
            for value in values:
                output.append(value)
                window[cursor] = value
                cursor = (cursor + 1) & 0xFFF
    return bytes(output), missing_character


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("compress", "expand"))
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--missing-character", default="", metavar="CHAR")
    args = parser.parse_args()
    source = args.source.read_bytes()
    if args.mode == "compress":
        if len(args.missing_character) > 1:
            parser.error("--missing-character accepts at most one character")
        missing = ord(args.missing_character) if args.missing_character else 0
        result = encode(source, missing)
    else:
        result, _ = decode(source)
    args.destination.write_bytes(result)


if __name__ == "__main__":
    main()
