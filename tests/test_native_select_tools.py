#!/usr/bin/env python3
"""Check native ASC2HLP and COMPRESS against SELECT's reference files."""

from __future__ import annotations

import hashlib
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SELECT = ROOT / "src/v4.0/src/SELECT"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="msdos-select-tools-") as temporary:
        output = Path(temporary)
        subprocess.run(
            [ROOT / "bin/asc2hlp", SELECT / "USA.TXT", output / "SELECT.HLP"],
            check=True,
        )
        assert digest(output / "SELECT.HLP") == digest(SELECT / "SELECT.HLP")

        shutil.copyfile(SELECT / "SEL-PAN.DAT", output / "SEL-PAN.DAT")
        subprocess.run([ROOT / "bin/compress"], cwd=output, check=True)
        assert digest(output / "SELECT.DAT") == digest(SELECT / "SELECT.DAT")

    print("native ASC2HLP and COMPRESS parity tests passed (2 production outputs)")


if __name__ == "__main__":
    main()
