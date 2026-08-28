#!/usr/bin/env python3
"""Compare native NOSRVBLD and MENUBLD with current production outputs."""

from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "MS-DOS/v4.0/src"
CATALOG = SOURCE / "MESSAGES/USA-MS.MSG"

NOSRV_CASES = {
    "BOOT/BOOT.CL1": "BOOT/BOOT.SKL",
    "BIOS/MSBIO.CL1": "BIOS/MSBIO.SKL",
    "BIOS/MSBIO.CL2": "BIOS/MSBIO.SKL",
    "BIOS/MSBIO.CL3": "BIOS/MSBIO.SKL",
    "BIOS/MSBIO.CL4": "BIOS/MSBIO.SKL",
    "BIOS/MSBIO.CL5": "BIOS/MSBIO.SKL",
    "DOS/MSDOS.CL1": "DOS/MSDOS.SKL",
    "DOS/MSDOS.CL3": "DOS/MSDOS.SKL",
    "CMD/FDISK/FDISK5.CL1": "CMD/FDISK/FDISK5.SKL",
    "DEV/XMA2EMS/XMA2EMS.CL1": "DEV/XMA2EMS/XMA2EMS.SKL",
    "DEV/XMAEM/XMAEM.CL1": "DEV/XMAEM/XMAEM.SKL",
}


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="msdos-message-tools-") as temp_name:
        temp = Path(temp_name)
        skeletons = sorted(set(NOSRV_CASES.values()))
        for skeleton in skeletons:
            subprocess.run(
                [ROOT / "bin/nosrvbld", str(SOURCE / skeleton), str(CATALOG)],
                cwd=temp,
                check=True,
            )
        for output_name in NOSRV_CASES:
            output = temp / Path(output_name).name
            if output.read_bytes() != (SOURCE / output_name).read_bytes():
                raise SystemExit(f"NOSRVBLD mismatch for {output_name}")

        subprocess.run(
            [
                ROOT / "bin/menubld",
                f"{SOURCE / 'CMD/FDISK/FDISK.MSG'} {CATALOG}",
            ],
            cwd=temp,
            check=True,
        )
        menu_name = "CMD/FDISK/FDISKM.C"
        if (temp / "FDISKM.C").read_bytes() != (SOURCE / menu_name).read_bytes():
            raise SystemExit(f"MENUBLD mismatch for {menu_name}")

    print("native NOSRVBLD and MENUBLD parity tests passed (12 outputs)")


if __name__ == "__main__":
    main()
