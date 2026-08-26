"""Byte-preserving parser for the MS-DOS 4 message catalog format."""

from __future__ import annotations

import re
from pathlib import Path


POOL_LINE = re.compile(rb"^([A-Z][A-Z0-9_-]*) +[0-9A-Fa-f]{4} +[0-9A-Fa-f]{4}$")
MESSAGE_LINE = re.compile(rb"^([0-9]{4}) U [0-9A-Fa-f]{4} (.*)$")


def host_path(name: str) -> Path:
    """Interpret DOS separators in build-file arguments on a modern host."""
    return Path(name.replace("\\", "/"))


def read_catalog(path: Path) -> dict[tuple[bytes, int], list[bytes]]:
    messages: dict[tuple[bytes, int], list[bytes]] = {}
    pool: bytes | None = None
    current: list[bytes] | None = None

    for line in path.read_bytes().splitlines():
        pool_match = POOL_LINE.fullmatch(line)
        if pool_match:
            pool = pool_match.group(1).upper()
            current = None
            continue

        message_match = MESSAGE_LINE.match(line)
        if message_match and pool is not None:
            key = (pool, int(message_match.group(1), 10))
            current = [message_match.group(2)]
            messages[key] = current
            continue

        if current is not None and line.startswith(b"\t"):
            current.append(line.lstrip(b"\t "))

    return messages
