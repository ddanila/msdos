#!/usr/bin/env python3
"""Check native CONVERT against the current production outputs."""

from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "MS-DOS/v4.0/src"
CONVERT = ROOT / "bin/convert"
CASES = (
    "CMD/FORMAT/FORMAT.COM",
    "CMD/CHKDSK/CHKDSK.COM",
    "CMD/DEBUG/DEBUG.COM",
    "CMD/EDLIN/EDLIN.COM",
    "CMD/RECOVER/RECOVER.COM",
    "CMD/PRINT/PRINT.COM",
    "CMD/BACKUP/BACKUP.COM",
    "CMD/RESTORE/RESTORE.COM",
)


def main() -> None:
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
        for output_name in CASES:
            source = SOURCE / Path(output_name).with_suffix(".EXE")
            output = temp / Path(output_name).name
            subprocess.run([CONVERT, f"{source} {output}"], check=True)
            if output.read_bytes() != (SOURCE / output_name).read_bytes():
                raise SystemExit(f"CONVERT output differs from {output_name}")
            if not output.read_bytes().endswith(loader_bytes):
                raise SystemExit(f"CONVERT loader source mismatch for {output_name}")

    print(f"native CONVERT parity tests passed ({len(CASES)} production cases)")


if __name__ == "__main__":
    main()
