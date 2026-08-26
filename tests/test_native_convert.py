#!/usr/bin/env python3
"""Compare native CONVERT with hashes captured from the Microsoft tool."""

from __future__ import annotations

import hashlib
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "MS-DOS/v4.0/src"
CONVERT = ROOT / "bin/convert"


def main() -> None:
    cases = {}
    for line in (ROOT / "tests/native_convert.sha256").read_text().splitlines():
        checksum, output_name = line.split(maxsplit=1)
        cases[output_name] = checksum

    with tempfile.TemporaryDirectory(prefix="msdos-convert-") as temp_name:
        temp = Path(temp_name)
        loader = temp / "convert-loader.bin"
        subprocess.run(
            [
                "nasm",
                "-f",
                "bin",
                "-o",
                loader,
                ROOT / "bin/convert-loader.asm",
            ],
            check=True,
        )
        loader_bytes = loader.read_bytes()
        for output_name, expected in cases.items():
            source = SOURCE / Path(output_name).with_suffix(".EXE")
            output = temp / Path(output_name).name
            subprocess.run([CONVERT, f"{source} {output}"], check=True)
            actual = hashlib.sha256(output.read_bytes()).hexdigest()
            if actual != expected:
                raise SystemExit(
                    f"CONVERT mismatch for {output_name}: {actual} != {expected}"
                )
            if not output.read_bytes().endswith(loader_bytes):
                raise SystemExit(f"CONVERT loader source mismatch for {output_name}")

    print(f"native CONVERT parity tests passed ({len(cases)} production cases)")


if __name__ == "__main__":
    main()
