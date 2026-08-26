#!/usr/bin/env python3
"""Compare native MKCNTRY extraction with the DOS-generated COUNTRY.SYS."""

from __future__ import annotations

import hashlib
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COUNTRY = ROOT / "MS-DOS/v4.0/src/DEV/COUNTRY"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="msdos-mkcntry-") as temporary:
        output = Path(temporary) / "COUNTRY.SYS"
        subprocess.run(
            [ROOT / "bin/mkcntry", COUNTRY / "MKCNTRY.EXE", output], check=True
        )
        assert digest(output) == digest(COUNTRY / "COUNTRY.SYS")
    print("native MKCNTRY parity test passed")


if __name__ == "__main__":
    main()
