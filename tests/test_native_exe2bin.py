#!/usr/bin/env python3
"""Check native EXE2BIN against hashes captured from the Microsoft tool."""

from __future__ import annotations

import hashlib
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "MS-DOS/v4.0/src"
EXE2BIN = ROOT / "bin/exe2bin"

CASES = {
    "BOOT/MSBOOT.BIN": ("BOOT/MSBOOT.EXE", None),
    "CMD/COMMAND/COMMAND.COM": ("CMD/COMMAND/COMMAND.EXE", None),
    "CMD/SYS/SYS.COM": ("CMD/SYS/SYS.EXE", None),
    "CMD/MORE/MORE.COM": ("CMD/MORE/MORE.EXE", None),
    "CMD/LABEL/LABEL.COM": ("CMD/LABEL/LABEL.EXE", None),
    "CMD/TREE/TREE.COM": ("CMD/TREE/TREE.EXE", None),
    "CMD/COMP/COMP.COM": ("CMD/COMP/COMP.EXE", None),
    "CMD/ASSIGN/ASSIGN.COM": ("CMD/ASSIGN/ASSIGN.EXE", None),
    "CMD/DISKCOMP/DISKCOMP.COM": ("CMD/DISKCOMP/DISKCOMP.EXE", None),
    "CMD/DISKCOPY/DISKCOPY.COM": ("CMD/DISKCOPY/DISKCOPY.EXE", None),
    "CMD/GRAFTABL/GRAFTABL.COM": ("CMD/GRAFTABL/GRAFTABL.EXE", None),
    "CMD/KEYB/KEYB.COM": ("CMD/KEYB/KEYB.EXE", None),
    "CMD/GRAPHICS/GRAPHICS.COM": ("CMD/GRAPHICS/GRAPHICS.EXE", None),
    "CMD/MODE/MODE.COM": ("CMD/MODE/MODE.EXE", None),
    "DOS/MSDOS.SYS": ("DOS/MSDOS.EXE", None),
    "DEV/DRIVER/DRIVER.SYS": ("DEV/DRIVER/DRIVER.EXE", None),
    "DEV/ANSI/ANSI.SYS": ("DEV/ANSI/ANSI.EXE", None),
    "DEV/VDISK/VDISK.SYS": ("DEV/VDISK/VDISK.EXE", None),
    "DEV/RAMDRIVE/RAMDRIVE.SYS": ("DEV/RAMDRIVE/RAMDRIVE.EXE", None),
    "DEV/KEYBOARD/KEYBOARD.SYS": ("DEV/KEYBOARD/KEYBOARD.EXE", None),
    "DEV/PRINTER/PRINTER.SYS": ("DEV/PRINTER/PRINTER.EXE", "0\n"),
    "DEV/DISPLAY/DISPLAY.SYS": ("DEV/DISPLAY/DISPLAY.EXE", "0\n"),
    "DEV/DISPLAY/EGA/EGA.CPI": ("DEV/DISPLAY/EGA/CPI-HEAD.EXE", None),
    "DEV/SMARTDRV/SMARTDRV.SYS": ("DEV/SMARTDRV/SMARTDRV.EXE", None),
    "DEV/XMA2EMS/XMA2EMS.SYS": ("DEV/XMA2EMS/XMA2EMS.EXE", None),
    "SELECT/SELECT.COM": ("SELECT/SSTUB.EXE", None),
    "CMD/FDISK/FDBOOT.BIN": ("CMD/FDISK/FDBOOT.EXE", None),
    "SELECT/SEL-PAN.DAT": ("SELECT/SEL-PAN.EXE", None),
    "BIOS/MSLOAD.COM": ("BIOS/MSLOAD.EXE", None),
    "BIOS/MSBIO.BIN": ("BIOS/MSBIO.EXE", "70\n"),
}


def load_hashes() -> dict[str, str]:
    result = {}
    for line in (ROOT / "tests/native_exe2bin.sha256").read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        result[name] = digest
    return result


def main() -> None:
    expected = load_hashes()
    if expected.keys() != CASES.keys():
        raise SystemExit("EXE2BIN case list and reference hash list differ")

    with tempfile.TemporaryDirectory(prefix="msdos-exe2bin-") as temp_name:
        temp = Path(temp_name)
        for output_name, (input_name, load_segment) in CASES.items():
            output = temp / Path(output_name).name
            command_tail = f"{SOURCE / input_name} {output}"
            subprocess.run(
                [EXE2BIN, command_tail],
                input=load_segment,
                text=True,
                check=True,
            )
            actual = hashlib.sha256(output.read_bytes()).hexdigest()
            if actual != expected[output_name]:
                raise SystemExit(
                    f"EXE2BIN mismatch for {output_name}: {actual} != {expected[output_name]}"
                )
    print(f"native EXE2BIN parity tests passed ({len(CASES)} production cases)")


if __name__ == "__main__":
    main()
