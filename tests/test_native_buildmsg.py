#!/usr/bin/env python3
"""Compare native BUILDMSG with all captured production outputs."""

from __future__ import annotations

import hashlib
import subprocess
import tempfile
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "MS-DOS/v4.0/src"
BUILDMSG = ROOT / "bin/buildmsg"
CATALOG = SRC / "MESSAGES/USA-MS"
MANIFEST = ROOT / "tests/native_buildmsg.sha256"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    cases: dict[tuple[Path, str], dict[str, str]] = defaultdict(dict)
    for line in MANIFEST.read_text().splitlines():
        expected, relative = line.split("  ", 1)
        path = Path(relative)
        cases[(path.parent, path.stem)][path.name] = expected

    checked = 0
    with tempfile.TemporaryDirectory(prefix="msdos-buildmsg-") as temporary:
        temporary_root = Path(temporary)
        for index, ((parent, stem), expected_files) in enumerate(cases.items()):
            output = temporary_root / str(index)
            output.mkdir()
            skeleton = SRC / parent / f"{stem}.SKL"
            subprocess.run(
                [BUILDMSG, CATALOG, skeleton], cwd=output, check=True
            )
            actual_files = {path.name for path in output.iterdir()}
            assert actual_files == set(expected_files), (
                skeleton,
                sorted(actual_files),
                sorted(expected_files),
            )
            for name, expected in expected_files.items():
                actual = digest(output / name)
                assert actual == expected, (skeleton, name, actual, expected)
                checked += 1

    assert len(cases) == 43, len(cases)
    assert checked == 204, checked
    print(f"native BUILDMSG parity tests passed ({len(cases)} cases, {checked} outputs)")


if __name__ == "__main__":
    main()
