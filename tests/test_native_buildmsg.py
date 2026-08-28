#!/usr/bin/env python3
"""Compare native BUILDMSG with all current production outputs."""

from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "MS-DOS/v4.0/src"
BUILDMSG = ROOT / "bin/buildmsg"
CATALOG = SRC / "MESSAGES/USA-MS"
SKELETONS = (
    "CMD/COMMAND/COMMAND.SKL", "CMD/SYS/SYS.SKL",
    "CMD/FORMAT/FORMAT.SKL", "CMD/CHKDSK/CHKDSK.SKL",
    "CMD/DEBUG/DEBUG.SKL", "CMD/MEM/MEM.SKL", "CMD/FDISK/FDISK.SKL",
    "CMD/MORE/MORE.SKL", "CMD/SORT/SORT.SKL", "CMD/LABEL/LABL.SKL",
    "CMD/FIND/FIND.SKL", "CMD/TREE/TREE.SKL", "CMD/COMP/COMP.SKL",
    "CMD/ATTRIB/ATTRIB.SKL", "CMD/EDLIN/EDLIN.SKL",
    "CMD/NLSFUNC/NLSFUNC.SKL", "CMD/ASSIGN/ASSIGN.SKL",
    "CMD/XCOPY/XCOPY.SKL", "CMD/DISKCOMP/DISKCOMP.SKL",
    "CMD/DISKCOPY/DISKCOPY.SKL", "CMD/APPEND/APPEND.SKL",
    "CMD/RECOVER/RECOVER.SKL", "CMD/FASTOPEN/FASTOPEN.SKL",
    "CMD/PRINT/PRINT.SKL", "CMD/FILESYS/FILESYS.SKL",
    "CMD/REPLACE/REPLACE.SKL", "CMD/JOIN/JOIN.SKL",
    "CMD/SUBST/SUBST.SKL", "CMD/BACKUP/BACKUP.SKL",
    "CMD/RESTORE/RESTORE.SKL", "CMD/GRAFTABL/GRAFTABL.SKL",
    "CMD/KEYB/KEYB.SKL", "CMD/SHARE/SHARE.SKL",
    "CMD/EXE2BIN/EXE2BIN.SKL", "CMD/GRAPHICS/GRAPHICS.SKL",
    "CMD/IFSFUNC/IFSFUNC.SKL", "CMD/MODE/MODE.SKL",
    "DEV/DRIVER/DRIVER.SKL", "DEV/ANSI/ANSI.SKL", "DEV/VDISK/VDISK.SKL",
    "DEV/PRINTER/PRINTER.SKL", "DEV/DISPLAY/DISPLAY.SKL",
    "SELECT/SELECT.SKL",
)


def main() -> None:
    checked = 0
    with tempfile.TemporaryDirectory(prefix="msdos-buildmsg-") as temporary:
        temporary_root = Path(temporary)
        for index, relative in enumerate(SKELETONS):
            skeleton = Path(relative)
            output = temporary_root / str(index)
            output.mkdir()
            subprocess.run(
                [BUILDMSG, CATALOG, SRC / skeleton], cwd=output, check=True
            )
            actual_files = list(output.iterdir())
            assert actual_files, skeleton
            for generated in actual_files:
                production = SRC / skeleton.parent / generated.name
                assert production.is_file(), (skeleton, generated.name)
                assert generated.read_bytes() == production.read_bytes(), (
                    skeleton, generated.name
                )
                checked += 1

    assert len(SKELETONS) == 43, len(SKELETONS)
    assert checked == 204, checked
    print(
        f"native BUILDMSG parity tests passed "
        f"({len(SKELETONS)} cases, {checked} outputs)"
    )


if __name__ == "__main__":
    main()
