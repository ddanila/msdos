#!/usr/bin/env python3
"""Test the source-built DWED launcher and editor on private LOW/HIGH images.

Defaults to the built parent out/floppy.img; --boot-image accepts external media. An explicit launcher override supports
historical-binary negative controls; normal runs use only source-built programs.
"""

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--build", type=Path, default=ROOT / "dwed/out/build")
parser.add_argument("--boot-image", type=Path, default=ROOT / "out/floppy.img")
parser.add_argument(
    "--boot-files",
    type=Path,
    help="directory containing matching HIMEM.SYS and EMM386.EXE",
)
parser.add_argument("--package", type=Path, help="run the verified staged EDIT package")
parser.add_argument("--launcher", type=Path, help="override the source-built launcher")
parser.add_argument(
    "--case", action="append", help="run only the named case (repeatable)"
)
parser.add_argument(
    "--mouse-driver",
    type=Path,
    help="enable real CuteMouse cases with the pinned fixture",
)
args = parser.parse_args()
package_manifest = None
launcher_name = "DWED.COM"
if args.package:
    if args.launcher:
        parser.error("--package and --launcher are mutually exclusive")
    package_manifest = json.loads((args.package / "package.json").read_text())
    for name, expected in package_manifest["files"].items():
        if not all(
            re.fullmatch(r"[A-Z0-9_-]{1,8}(?:\.[A-Z0-9]{1,3})?", part)
            for part in name.split("/")
        ):
            parser.error("invalid DOS package path: " + name)
        data = (args.package / "files" / name).read_bytes()
        if (
            len(data) != expected["bytes"]
            or hashlib.sha256(data).hexdigest() != expected["sha256"]
        ):
            parser.error("package file does not match manifest: " + name)
    launcher_name = "EDIT.COM"
    overlay = args.package / "files/DWEDOVL.EXE"
    launcher = args.package / "files/EDIT.COM"
    configuration = args.package / "files/DWED.CFG"
else:
    overlay = args.build.resolve() / "DWEDOVL.exe"
    launcher = (args.launcher or args.build / "DWED.COM").resolve()
    configuration = args.build / "DWED.CFG"
for required in (overlay, launcher, args.boot_image):
    if not required.is_file():
        parser.error(f"missing input: {required}")
import screen_expect
from dwed_addon_scenarios import CASES as ADDON_CASES
from dwed_addon_scenarios import exercise as exercise_addon
from dwed_clipboard_scenarios import CASES as CLIPBOARD_CASES
from dwed_clipboard_scenarios import exercise as exercise_clipboard
from dwed_clipboard_scenarios import prepare as prepare_clipboard
from dwed_dialog_scenarios import (
    CASES as DIALOG_CASES,
)
from dwed_dialog_scenarios import (
    exercise as exercise_dialog,
)
from dwed_dialog_scenarios import (
    prepare as prepare_dialog,
)
from dwed_help_scenarios import CASES as HELP_CASES
from dwed_help_scenarios import exercise as exercise_help
from dwed_mono_scenarios import CASES as MONO_CASES
from dwed_mono_scenarios import exercise as exercise_mono
from dwed_mouse_scenarios import CASES as MOUSE_CASES
from dwed_mouse_scenarios import exercise as exercise_mouse
from dwed_mouse_scenarios import prepare as prepare_mouse
from dwed_mouse_scenarios import validate_driver
from dwed_recovery_scenarios import CASES as RECOVERY_CASES
from dwed_recovery_scenarios import FAULTS as RECOVERY_FAULTS
from dwed_recovery_scenarios import exercise as exercise_recovery
from dwed_recovery_scenarios import kind_of as recovery_kind
from dwed_recovery_scenarios import prepare as prepare_recovery
from dwed_save_cut_scenarios import CASES as SAVE_CUT_CASES
from dwed_save_cut_scenarios import exercise as exercise_save_cut
from dwed_save_fault_scenarios import CASES as SAVE_ERROR_CASES
from dwed_save_fault_scenarios import exercise as exercise_save_error
from dwed_save_lifecycle_scenarios import CASES as SAVE_LIFECYCLE_CASES
from dwed_save_lifecycle_scenarios import FAULTS as SAVE_LIFECYCLE_FAULTS
from dwed_save_lifecycle_scenarios import exercise as exercise_save_lifecycle
from dwed_search_scenarios import CASES as SEARCH_CASES
from dwed_search_scenarios import exercise as exercise_search
from dwed_tab_scenarios import CASES as TAB_CASES
from dwed_tab_scenarios import exercise as exercise_tabs
from dwed_tab_scenarios import prepare as prepare_tabs
from dwed_table_row_scenarios import CASES as TABLE_ROW_CASES
from dwed_table_row_scenarios import exercise as exercise_table_row
from dwed_table_scenarios import CASES as TABLE_CASES
from dwed_table_scenarios import exercise as exercise_table
from dwed_undo_scenarios import CASES as UNDO_CASES
from dwed_undo_scenarios import exercise as exercise_undo
from screen_expect import QMPConnection, read_screen_text, send_keys
from test_compat_bpb_qemu import disk, put, run

WORK = Path(tempfile.mkdtemp(prefix="dwed-qemu-", dir=ROOT / "out"))
print(WORK, flush=True)
(WORK / "environment.json").write_text(
    json.dumps(
        {
            "package": package_manifest,
            "launcher_name": launcher_name,
            "boot_image_sha256": hashlib.sha256(
                args.boot_image.read_bytes()
            ).hexdigest(),
            "boot_file_sha256": {
                name: hashlib.sha256((args.boot_files / name).read_bytes()).hexdigest()
                for name in ("HIMEM.SYS", "EMM386.EXE")
            }
            if args.boot_files
            else {},
            "build": json.loads((args.build / "build.json").read_text()),
        },
        indent=2,
    )
    + "\n"
)
repo = ROOT / "dwed"
rows = []
cases = [
    ("edit-" + mode, mode, b"DWED_MARKER\r\nsecond line\r\n", True)
    for mode in ("low", "high")
]
cases += [
    (
        kind + "-" + mode,
        mode,
        b"DWED_MARKER\r\n" + (b"0123456789" * 8 + b"\r\n") * 100,
        True,
    )
    for kind in ("disk-full", "read-only", "media-readonly", "media-readonly-saveas")
    for mode in ("low", "high")
]
cases += [
    (kind + "-" + mode, mode, b"DWED_MARKER\r\nsecond line\r\n", True)
    for kind in ("memory-probe", "screen-memory", "list-memory", "dos-screen")
    for mode in ("low", "high")
]
cases += [
    ("indent-enter-" + mode, mode, b"DWED_MARKER\r\n \tA  B", False)
    for mode in ("low", "high")
]
cases += [
    (
        "list-ui-" + mode,
        mode,
        b"DWED_MARKER\r\nprocedure first;\r\nprocedure second;\r\n",
        True,
    )
    for mode in ("low", "high")
]
cases += HELP_CASES
cases.append(("backup-file-low", "low", b"DWED_MARKER\r\nbackup document\r\n", True))
cases += [
    (kind + "-" + mode, mode, b"DWED_MARKER\r\nsecond line\r\n", True)
    for kind in ("external", "recursive")
    for mode in ("low", "high")
]
cases.append(("outside-directory-low", "low", b"DWED_MARKER\r\nsecond line\r\n", True))
cases += [
    ("text-lf-low", "low", b"DWED_MARKER\nsecond line\n", True),
    ("text-cr-low", "low", b"DWED_MARKER\rsecond line\r", True),
    ("text-no-final-low", "low", b"DWED_MARKER\r\nsecond line", True),
    ("text-tabs-low", "low", b"DWED_MARKER\tend\r\n\tsecond\tline \t\r\n", True),
    (
        "text-codepage-low",
        "low",
        b"DWED_MARKER\r\n" + bytes(range(128, 256)) + b"\r\n",
        True,
    ),
    ("text-max-line-low", "low", b"DWED_MARKER" + b"x" * 244 + b"\r\n", False),
    ("text-empty-low", "low", b"", False),
    ("reject-long-low", "low", b"DWED_MARKER" + b"x" * 245 + b"\r\n", False),
    ("reject-mixed-low", "low", b"DWED_MARKER\r\nsecond line\n", False),
    ("reject-control-low", "low", b"DWED_MARKER\x00hidden\r\n", False),
]
cases += [
    (
        "reject-memory-" + mode,
        mode,
        b"DWED_MARKER\r\n" + b"0123456789abcdef\r\n" * 40000,
        False,
    )
    for mode in ("low", "high")
]
cases += [
    ("new-file-low", "low", b"", True),
    ("split-whitespace-low", "low", b"DWED_MARKER \t \r\n", False),
    ("remove-final-low", "low", b"DWED_MARKER\r\n", False),
]
cases += [
    ("keyboard-" + mode, mode, b"DWED_MARKER\r\n", True) for mode in ("low", "high")
]
cases += [
    ("menu-save-" + mode, mode, b"DWED_MARKER\r\nsecond line\r\n", True)
    for mode in ("low", "high")
]
cases += [
    ("menu-" + kind + "-low", "low", b"DWED_MARKER\r\nsecond line\r\n", True)
    for kind in ("alt", "copy", "cancel")
]
cases += [
    (kind + "-low", "low", b"DWED_MARKER\r\nsecond line\r\n", True)
    for kind in ("menu-open", "shortcut-open")
]
cases += [
    ("undo-journal-" + mode, mode, b"DWED_MARKER\r\n", True) for mode in ("low", "high")
]
cases += [
    ("undo-storage-" + mode, mode, b"DWED_MARKER\r\n", True) for mode in ("low", "high")
]
cases += [
    ("clipboard-probe-" + mode, mode, b"DWED_MARKER\r\n", True)
    for mode in ("low", "high")
]
cases += [
    ("tab-probe-" + mode, mode, b"DWED_MARKER\r\n", True) for mode in ("low", "high")
]
cases += [
    ("save-fault-" + mode, mode, b"DWED_MARKER\r\n", True) for mode in ("low", "high")
]
cases += [
    ("xms-probe-" + profile + "-" + mode, mode, b"DWED_MARKER\r\n", True)
    for profile in ("classic", "sxms")
    for mode in ("low", "high")
]
cases += [
    ("xfer-probe-" + profile + "-" + mode, mode, b"DWED_MARKER\r\n", True)
    for profile in ("classic", "sxms")
    for mode in ("low", "high")
]
cases += [
    ("real-transfer-" + profile + "-high", "high", b"DWED_MARKER\r\n", True)
    for profile in ("xms", "ems")
]
cases += [
    ("cache-probe-" + profile + "-high", "high", b"DWED_MARKER\r\n", True)
    for profile in ("full", "writeback")
]
cases += TABLE_ROW_CASES
cases += TABLE_CASES
cases += ADDON_CASES
cases += SEARCH_CASES
cases += DIALOG_CASES
cases += UNDO_CASES
cases += CLIPBOARD_CASES
cases += TAB_CASES
cases += MONO_CASES
cases += SAVE_ERROR_CASES
cases += SAVE_LIFECYCLE_CASES
cases += SAVE_CUT_CASES
cases += RECOVERY_CASES
if args.mouse_driver:
    validate_driver(args.mouse_driver)
    cases += MOUSE_CASES
if args.case:
    unknown = set(args.case) - {case[0] for case in cases}
    if unknown:
        parser.error(f"unknown cases: {sorted(unknown)}")
    cases = [case for case in cases if case[0] in args.case]
if (
    any(case[0].startswith("keyboard-") for case in cases)
    and not (args.build.resolve() / "KEYTEST.exe").is_file()
):
    parser.error("keyboard cases require an editor built with --tests")
if (
    any(case[0].startswith("undo-journal-") for case in cases)
    and not (args.build.resolve() / "UNDOTEST.exe").is_file()
):
    parser.error("undo journal cases require an editor built with --tests")
if (
    any(case[0].startswith("undo-storage-") for case in cases)
    and not (args.build.resolve() / "STORTEST.exe").is_file()
):
    parser.error("undo storage cases require an editor built with --tests")
if (
    any(case[0].startswith("clipboard-probe-") for case in cases)
    and not (args.build.resolve() / "CLIPTEST.exe").is_file()
):
    parser.error("clipboard probes require an editor built with --tests")
if (
    any(case[0].startswith("cache-probe-") for case in cases)
    and not (args.build.resolve() / "CACHETEST.exe").is_file()
):
    parser.error("cache probes require an editor built with --tests")
if (
    any(case[0].startswith("real-transfer-") for case in cases)
    and not (args.build.resolve() / "MEMXFER.exe").is_file()
):
    parser.error("real transfer probes require an editor built with --tests")
if (
    any(case[0].startswith("xfer-probe-") for case in cases)
    and not (args.build.resolve() / "XFERTEST.exe").is_file()
):
    parser.error("transfer probes require an editor built with --tests")
if (
    any(case[0].startswith("xms-probe-") for case in cases)
    and not (args.build.resolve() / "XMSTEST.exe").is_file()
):
    parser.error("XMS probes require an editor built with --tests")
if (
    any(case[0].startswith("tab-probe-") for case in cases)
    and not (args.build.resolve() / "TABTEST.exe").is_file()
):
    parser.error("tab probes require an editor built with --tests")
if (
    any(case[0].startswith("save-fault-") for case in cases)
    and not (args.build / "SAVETEST.exe").is_file()
):
    parser.error("save fault probes require an editor built with --tests")
if (
    any(case[0].startswith("save-cut-") for case in cases)
    and not (args.build / "RECVTEST.exe").is_file()
):
    parser.error("restart probes require an editor built with --tests")
for name, mode, original, edit in cases:
    mouse = name.startswith("mouse-edit-")
    monochrome = name.startswith(("mono-edit-", "help-mono-")) or name in (
        "mouse-edit-mono-low",
        "addon-ascii-mono-low",
        "addon-calc-mono-low",
        "mouse-edit-dialog-mono-low",
        "save-error-pending-close-mono-low",
    )
    screen_expect.VRAM_PHYS = 0xB0000 if monochrome else 0xB8000
    startup = name.startswith("dialog-startup-")
    keyboard = name.startswith("keyboard-")
    undo_journal = name.startswith("undo-journal-")
    undo_storage = name.startswith("undo-storage-")
    clipboard_probe = name.startswith("clipboard-probe-")
    cache_probe = name.startswith("cache-probe-")
    real_transfer = name.startswith("real-transfer-")
    xfer_probe = name.startswith("xfer-probe-")
    xms_probe = name.startswith("xms-probe-")
    tab_probe = name.startswith("tab-probe-")
    save_probe = name.startswith("save-fault-")
    rejected = name.startswith("reject-")
    failure = name.startswith(("disk-full", "read-only", "media-readonly"))
    filename = "SAMPLE.BAK" if name.startswith("backup-file") else "SAMPLE.TXT"
    if name.startswith("list-ui-"):
        filename = "SAMPLE.PAS"
    backup_name = "SAMPLE.BK!" if name.startswith("backup-file") else "SAMPLE.BAK"
    d = WORK / name
    d.mkdir()
    floppy = d / "boot.img"
    shutil.copyfile(args.boot_image, floppy)
    if args.boot_files:
        for boot_file in ("HIMEM.SYS", "EMM386.EXE"):
            put(floppy, boot_file, (args.boot_files / boot_file).read_bytes())
    hdd, _, _ = disk(d, {})
    spec = f"{hdd}@@32256"
    run(["mmd", "-i", spec, "::DWED"])
    if package_manifest:
        directories = set()
        for relative in package_manifest["files"]:
            parent = Path(relative).parent
            if str(parent) != ".":
                directories.add(parent)
                directories.update(p for p in parent.parents if str(p) != ".")
        for parent in sorted(directories, key=lambda p: (len(p.parts), str(p))):
            run(["mmd", "-i", spec, "::DWED/" + str(parent)])
        for relative in package_manifest["files"]:
            put(
                spec,
                "DWED/" + relative,
                (args.package / "files" / relative).read_bytes(),
            )
    else:
        for file, dos_name in (
            (launcher, launcher_name),
            (overlay, "DWEDOVL.EXE"),
            (configuration, "DWED.CFG"),
        ):
            run(["mcopy", "-o", "-i", spec, file, "::DWED/" + dos_name])
    if not name.startswith("new-file"):
        put(spec, filename, original)
    external = name.startswith(("external", "recursive"))
    if external:
        cfg = configuration.read_bytes().replace(
            b"usr.def.f5=dir", b"usr.def.f5=C:\\RUNTEST.BAT"
        )
        put(spec, "DWED/DWED.CFG", cfg)
        batch = b"@ECHO OFF\r\n"
        if name.startswith("recursive"):
            batch += (
                "C:\\DWED\\" + launcher_name + "\r\nIF NOT ERRORLEVEL 1 GOTO FAIL\r\n"
            ).encode()
        batch += b"ECHO EXTERNAL_COMMAND_OK>C:\\COMMAND.TXT\r\nCD \\\r\nA:\r\nECHO EXTERNAL_COMMAND_DONE\r\n:FAIL\r\n"
        put(spec, "RUNTEST.BAT", batch)
    previous_backup = b"PREVIOUS_BACKUP\r\n"
    put(spec, backup_name, previous_backup)
    put(spec, "$ED0000.TMP", b"OTHER_EDITOR_SAVE\r\n")
    prepare_recovery(spec, name)
    prepare_mouse(spec, name)
    prepare_dialog(spec, name)
    prepare_clipboard(spec, name)
    prepare_tabs(spec, name, (repo / "BIN/DWED.CFG").read_bytes())
    if name.startswith("disk-full") or name in (
        "dialog-exit-full-low",
        "clip-edit-export-full-low",
    ):
        listing = run(["mdir", "-i", spec, "::"]).stdout.decode()
        free = int(re.search(r"([\d ]+) bytes free", listing).group(1).replace(" ", ""))
        put(spec, "FILLER.BIN", bytes(free - 1024))
    if name.startswith("read-only"):
        run(["mattrib", "-i", spec, "+r", "::SAMPLE.TXT"])
    asm = d / "exit.asm"
    asm.write_text("bits 16\norg 100h\nmov dx,0f4h\nmov ax,10h\nout dx,ax\nhlt\n")
    run(["nasm", "-f", "bin", asm, "-o", d / "EXIT.COM"])
    put(floppy, "QEXIT.COM", (d / "EXIT.COM").read_bytes())
    config = b"FILES=40\r\nBUFFERS=15\r\nDOS=LOW\r\n"
    if mode == "high":
        config = b"DEVICE=A:\\HIMEM.SYS\r\nDEVICE=A:\\EMM386.EXE NOEMS\r\nDOS=HIGH,UMB\r\nFILES=40\r\nBUFFERS=15\r\n"
    if name == "real-transfer-ems-high":
        config = config.replace(b"EMM386.EXE NOEMS", b"EMM386.EXE RAM 1024")
    put(floppy, "CONFIG.SYS", config)
    probe_command = ""
    if name.startswith(("memory-probe-", "screen-memory-", "list-memory-")):
        put(spec, "HUGE.TXT", b"0123456789abcdef\r\n" * 40000)
        put(floppy, "MEMTEST.EXE", (args.build / "MEMTEST.exe").read_bytes())
        probe_command = (
            "A:\\MEMTEST.EXE"
            + (
                " /SCREEN"
                if name.startswith("screen-memory-")
                else " /LIST"
                if name.startswith("list-memory-")
                else ""
            )
            + "\r\n"
        )
    if keyboard:
        probe = args.build.resolve() / "KEYTEST.exe"
        put(floppy, "KEYTEST.EXE", probe.read_bytes())
        probe_command = "A:\\KEYTEST.EXE\r\n"
    if undo_journal:
        put(
            floppy, "UNDOTEST.EXE", (args.build.resolve() / "UNDOTEST.exe").read_bytes()
        )
        probe_command = "A:\\UNDOTEST.EXE\r\n"
    if undo_storage:
        put(
            floppy, "STORTEST.EXE", (args.build.resolve() / "STORTEST.exe").read_bytes()
        )
        probe_command = "A:\\STORTEST.EXE\r\n"
    if clipboard_probe:
        put(
            floppy, "CLIPTEST.EXE", (args.build.resolve() / "CLIPTEST.exe").read_bytes()
        )
        probe_command = "A:\\CLIPTEST.EXE\r\n"
    if tab_probe:
        put(floppy, "TABTEST.EXE", (args.build.resolve() / "TABTEST.exe").read_bytes())
        probe_command = "A:\\TABTEST.EXE\r\n"
    if save_probe:
        put(floppy, "SAVETEST.EXE", (args.build / "SAVETEST.exe").read_bytes())
        probe_command = "A:\\SAVETEST.EXE\r\n"
    if cache_probe:
        put(floppy, "CACHTEST.EXE", (args.build / "CACHETEST.exe").read_bytes())
        profile = " /WRITEBACK" if "-writeback-" in name else ""
        probe_command = "A:\\CACHTEST.EXE" + profile + " >C:\\CACHERUN.LOG\r\n"
    if real_transfer:
        put(floppy, "MEMXFER.EXE", (args.build / "MEMXFER.exe").read_bytes())
        profile = " /EMS" if "-ems-" in name else ""
        probe_command = "A:\\MEMXFER.EXE" + profile + " >C:\\MXFERRUN.LOG\r\n"
    if xfer_probe:
        put(floppy, "XFERTEST.EXE", (args.build / "XFERTEST.exe").read_bytes())
        profile = " /CLASSIC" if "-classic-" in name else ""
        probe_command = "A:\\XFERTEST.EXE" + profile + " >C:\\XFERRUN.LOG\r\n"
    if xms_probe:
        put(floppy, "XMSTEST.EXE", (args.build / "XMSTEST.exe").read_bytes())
        profile = " /CLASSIC" if "-classic-" in name else ""
        probe_command = "A:\\XMSTEST.EXE" + profile + " >C:\\XMSRUN.LOG\r\n"
    if monochrome:
        mode_source = "bits 16\norg 100h\nmov ax,7\nint 10h\n"
        if "rows" in name:
            mode_source += "mov ax,40h\nmov ds,ax\nmov byte [84h],0\n"
        mode_source += "int 20h\n"
        (d / "mono.asm").write_text(mode_source)
        run(["nasm", "-f", "bin", d / "mono.asm", "-o", d / "MONO.COM"])
        put(floppy, "MONO.COM", (d / "MONO.COM").read_bytes())
        probe_command += "A:\\MONO.COM\r\n"
    if mouse:
        put(floppy, "CTMOUSE.EXE", args.mouse_driver.read_bytes())
        run(
            [
                "nasm",
                "-f",
                "bin",
                ROOT / "tests/dwed_mouse_telemetry.asm",
                "-o",
                d / "MTRACE.COM",
            ]
        )
        put(floppy, "MTRACE.COM", (d / "MTRACE.COM").read_bytes())
        probe_command += "A:\\CTMOUSE.EXE\r\nA:\\MTRACE.COM\r\n"
    if name.startswith("save-error-"):
        fault = SAVE_LIFECYCLE_FAULTS.get(name, 1 if "-close-" in name else 2)
        run(
            [
                "nasm",
                "-f",
                "bin",
                f"-DFAULT={fault}",
                ROOT / "tests/dwed_save_fault.asm",
                "-o",
                d / "SFAULT.COM",
            ]
        )
        put(floppy, "SFAULT.COM", (d / "SFAULT.COM").read_bytes())
        probe_command += "A:\\SFAULT.COM\r\n"
    if name.startswith("save-cut-"):
        stage = int(name.split("-")[2])
        run(
            [
                "nasm",
                "-f",
                "bin",
                f"-DSTAGE={stage}",
                ROOT / "tests/dwed_save_cut.asm",
                "-o",
                d / "SCUT.COM",
            ]
        )
        put(floppy, "SCUT.COM", (d / "SCUT.COM").read_bytes())
        put(floppy, "RECVTEST.EXE", (args.build / "RECVTEST.exe").read_bytes())
        probe_command += "A:\\SCUT.COM\r\n"
    if name.startswith("recover-") and recovery_kind(name) in RECOVERY_FAULTS:
        fault = RECOVERY_FAULTS[recovery_kind(name)]
        run(
            [
                "nasm",
                "-f",
                "bin",
                f"-DFAULT={fault}",
                ROOT / "tests/dwed_read_fault.asm",
                "-o",
                d / "RFAULT.COM",
            ]
        )
        put(floppy, "RFAULT.COM", (d / "RFAULT.COM").read_bytes())
        probe_command += "A:\\RFAULT.COM\r\n"
    invocation = "CD \\DWED\r\n" + launcher_name
    if name.startswith("outside-directory"):
        invocation = "CD \\\r\nC:\\DWED\\" + launcher_name
    control_spec = spec
    protected_media = None
    save_elsewhere = name.startswith("media-readonly-saveas")
    if name.startswith("media-readonly"):
        protected_media = d / "protected.img"
        run(["mformat", "-C", "-f", "1440", "-i", protected_media, "::"])
        put(protected_media, filename, original)
        put(protected_media, backup_name, previous_backup)
        put(protected_media, "$ED0000.TMP", b"OTHER_EDITOR_SAVE\r\n")
        (d / "vec.asm").write_text(
            "bits 16\norg 100h\nmov ax,3524h\nint 21h\nmov [vec],bx\nmov [vec+2],es\nmov dx,vec\nmov cx,4\nmov bx,1\nmov ah,40h\nint 21h\nmov ax,4c00h\nint 21h\nvec: dd 0\n"
        )
        run(["nasm", "-f", "bin", d / "vec.asm", "-o", d / "VEC.COM"])
        put(floppy, "VEC.COM", (d / "VEC.COM").read_bytes())
        probe_command += "A:\\VEC.COM >A:\\VECBEF.BIN\r\n"
        protected_before = hashlib.sha256(protected_media.read_bytes()).hexdigest()
        spec = str(protected_media)
    put(
        floppy,
        "AUTOEXEC.BAT",
        (
            "@ECHO OFF\r\nVER >C:\\DOSVER.TXT\r\n"
            + probe_command
            + "C:\r\n"
            + invocation
            + ("" if startup else (" B:\\" if protected_media else " C:\\") + filename)
            + (" C:\\.\\SAMPLE.TXT" if name.startswith("recover-alias-") else "")
            + ("\r\nA:\\VEC.COM >A:\\VECAFT.BIN" if protected_media else "")
            + "\r\nCD >C:\\CWD.TXT\r\nA:\\QEXIT.COM\r\n"
        ).encode(),
    )
    socket = d / "qmp"
    argv = [
        "qemu-system-i386",
        "-machine",
        "pc",
        "-cpu",
        "486",
        "-m",
        "16",
        "-accel",
        "tcg,thread=single",
        "-d",
        "nochain",
        "-display",
        "none",
        "-monitor",
        "none",
        "-serial",
        f"file:{d}/serial.log",
        "-qmp",
        f"unix:{socket},server=on,wait=off",
        "-no-reboot",
        "-nic",
        "none",
        "-boot",
        "a",
        "-drive",
        f"if=floppy,format=raw,file={floppy}",
        "-drive",
        f"if=ide,format=raw,file={hdd}",
        "-device",
        "isa-debug-exit,iobase=0xf4,iosize=0x04",
    ]
    (d / "command.json").write_text(json.dumps(argv, indent=2))
    if protected_media:
        argv += [
            "-drive",
            f"if=floppy,index=1,format=raw,readonly=on,file={protected_media}",
        ]
    process = subprocess.Popen(
        argv, stdout=subprocess.DEVNULL, stderr=(d / "qemu.log").open("wb")
    )
    row = {"case": name, "mode": mode, "original_hex": original.hex()}
    try:
        q = QMPConnection(str(socket))
        end = time.monotonic() + 30
        screen = ""
        memory_notices = 0
        table_refusals = 0
        while time.monotonic() < end and process.poll() is None:
            screen = read_screen_text(q, str(d / "vram.bin"))
            if tab_probe and "#1004:" in screen:
                table_refusals += 1
                assert table_refusals <= 2, screen
                (d / f"table-refusal-{table_refusals}.txt").write_text(screen)
                send_keys(q, "ret")
                time.sleep(0.5)
                continue
            if (
                name.startswith(("screen-memory-", "list-memory-"))
                and "Not enough memory for this window" in screen
            ):
                memory_notices += 1
                send_keys(q, "esc")
                time.sleep(0.2)
                continue
            if (
                (name.startswith("recover-") and "Interrupted save" in screen)
                or (
                    rejected
                    and (
                        "file was not opened" in screen or "Not enough memory" in screen
                    )
                )
                or (startup and "Untitled" in screen)
                or (not original and "SAMPLE.TXT" in screen)
                or "DWED_MARKER" in screen
            ):
                break
            time.sleep(0.2)
        (d / "opened.txt").write_text(screen)
        if name.startswith("recover-"):
            assert "Interrupted save" in screen, screen
        elif rejected:
            assert (
                "Not enough memory"
                if name.startswith("reject-memory-")
                else "file was not opened"
            ) in screen, screen
            assert "DWED_MARKER" not in screen, screen
            send_keys(q, "ret")
            time.sleep(0.25)
            screen = read_screen_text(q, str(d / "vram.bin"))
            assert "SAMPLE.TXT" not in screen, screen
        else:
            assert (
                (not original and "SAMPLE.TXT" in screen)
                or (startup and "Untitled" in screen)
                or "DWED_MARKER" in screen
            ), screen
        if name.startswith("list-memory-"):
            assert memory_notices == 4, (memory_notices, screen)
            row["list_memory_notices"] = memory_notices
        if name.startswith("screen-memory-"):
            assert memory_notices == 1, (memory_notices, screen)
            row["screen_memory_notice"] = True
        q.human_cmd(f'screendump "{d}/opened.ppm"')
        if name.startswith("menu-"):
            assert all(
                label in screen.splitlines()[0]
                for label in ("File", "Edit", "Search", "Options", "Help")
            ), screen
        if name.startswith("table-row-"):
            row.update(exercise_table_row(q, process, d, spec, original, name))
        elif name.startswith("table-"):
            row.update(exercise_table(q, process, d, spec, original, name))
        elif name.startswith("addon-"):
            row.update(exercise_addon(q, process, d, spec, original, name))
        elif name.startswith("search-"):
            row.update(exercise_search(q, process, d, spec, original, name))
        elif name.startswith("help-"):
            row.update(exercise_help(q, process, d, spec, original, name))
        elif name.startswith("recover-"):
            row.update(exercise_recovery(q, process, d, spec, original, name))
        elif name.startswith("save-cut-"):
            row.update(
                exercise_save_cut(
                    q, process, d, spec, original, name, argv, floppy, launcher_name
                )
            )
        elif name in SAVE_LIFECYCLE_FAULTS:
            row.update(exercise_save_lifecycle(q, process, d, spec, original, name))
        elif name.startswith("save-error-"):
            row.update(exercise_save_error(q, process, d, spec, original, name))
        elif mouse:
            row.update(exercise_mouse(q, process, d, spec, original, name))
        elif monochrome:
            row.update(exercise_mono(q, process, d, spec, original, name))
        elif name.startswith("tab-edit-"):
            row.update(exercise_tabs(q, process, d, spec, original, name))
        elif name.startswith("clip-edit-"):
            row.update(exercise_clipboard(q, process, d, spec, original, name))
        elif name.startswith("undo-edit-"):
            row.update(exercise_undo(q, process, d, spec, original, name))
        elif name.startswith("dialog-"):
            row.update(exercise_dialog(q, process, d, spec, original, name))
        else:
            if edit:
                send_keys(q, "home+z")
                time.sleep(0.25)
            if name.startswith("list-ui-"):
                send_keys(q, "hmp:sendkey alt-f6")
                time.sleep(0.25)
                listing = read_screen_text(q, str(d / "vram.bin"))
                assert "Opened files" in listing and "SAMPLE.PAS" in listing, listing
                send_keys(q, "esc")
                send_keys(q, "hmp:sendkey ctrl-o")
                time.sleep(0.25)
                listing = read_screen_text(q, str(d / "vram.bin"))
                (d / "source-tree.txt").write_text(listing)
                assert all(
                    label in listing for label in ("Source tree", "first", "second")
                ), listing
                send_keys(q, "down+ret+home+x")
                row["source_tree_navigation"] = True
            if name.startswith("dos-screen-"):
                for _ in range(3):
                    send_keys(q, "hmp:sendkey alt-f5")
                    time.sleep(0.25)
                    console = read_screen_text(q, str(d / "vram.bin"))
                    assert "zDWED_MARKER" not in console, console
                    send_keys(q, "ret")
                    time.sleep(0.25)
                    restored = read_screen_text(q, str(d / "vram.bin"))
                    assert "zDWED_MARKER" in restored, restored
                    assert "*" in restored.splitlines()[-1], restored
                row["console_roundtrips"] = 3
            if name.startswith("indent-enter-"):
                send_keys(q, "down+home+right+right+right+ret+x")
                time.sleep(0.25)
            if name.startswith("split-whitespace"):
                send_keys(q, "end+ret")
                time.sleep(0.25)
            if name.startswith("remove-final"):
                send_keys(q, "down+home+backspace")
                time.sleep(0.25)
            if rejected:
                send_keys(q, "home+z")
                time.sleep(0.25)
            if name.startswith(("menu-open", "shortcut-open")):
                if name.startswith("menu-open"):
                    send_keys(q, "hmp:sendkey alt-f")
                    time.sleep(0.25)
                    send_keys(q, "o")
                else:
                    send_keys(q, "f3")
                time.sleep(0.25)
                dialog = read_screen_text(q, str(d / "vram.bin"))
                assert "Load file" in dialog, dialog
                send_keys(q, "esc")
                time.sleep(0.25)
                restored = read_screen_text(q, str(d / "vram.bin"))
                assert all(
                    label in restored.splitlines()[0]
                    for label in ("File", "Edit", "Search", "Options", "Help")
                ), restored
            if name.startswith(("menu-copy", "menu-cancel")):
                send_keys(q, "home")
                for _ in range(2):
                    send_keys(q, "hmp:sendkey shift-right 200")
                    time.sleep(0.3)
                send_keys(q, "hmp:sendkey alt-e")
                time.sleep(0.25)
                (d / "menu.txt").write_text(read_screen_text(q, str(d / "vram.bin")))
                if name.startswith("menu-copy"):
                    send_keys(q, "c")
                    time.sleep(0.25)
                    send_keys(q, "end")
                    send_keys(q, "hmp:sendkey alt-e")
                    time.sleep(0.25)
                    send_keys(q, "p")
                else:
                    send_keys(q, "esc+backspace")
                time.sleep(0.25)
            if name.startswith(("menu-save", "menu-alt")):
                send_keys(
                    q, "f10" if name.startswith("menu-save") else "hmp:sendkey alt-f"
                )
                time.sleep(0.25)
                menu_screen = read_screen_text(q, str(d / "vram.bin"))
                (d / "menu.txt").write_text(menu_screen)
                assert "Save as..." in menu_screen and "Windows..." in menu_screen, (
                    menu_screen
                )
                q.human_cmd(f'screendump "{d}/menu.ppm"')
                send_keys(q, "down+down+ret" if name.startswith("menu-save") else "s")
            elif keyboard:
                send_keys(q, "hmp:sendkey ctrl-end")
                time.sleep(0.25)
                send_keys(q, "backspace")
                send_keys(q, "hmp:sendkey ctrl-s")
            else:
                send_keys(q, "f2")
            time.sleep(0.5)
            if rejected:
                prompt = read_screen_text(q, str(d / "vram.bin"))
                assert "Save file to" in prompt, prompt
                send_keys(q, "r+e+j+e+c+t+e+d+dot+t+x+t+ret")
                time.sleep(0.5)
            saved_screen = read_screen_text(q, str(d / "vram.bin"))
            (d / "saved.txt").write_text(saved_screen)
            if external:
                send_keys(q, "f5")
                deadline = time.monotonic() + 15
                while time.monotonic() < deadline:
                    screen = read_screen_text(q, str(d / "vram.bin"))
                    if "Press any key to return to the editor." in screen:
                        break
                    time.sleep(0.2)
                (d / "command.txt").write_text(screen)
                assert "EXTERNAL_COMMAND_DONE" in screen, screen
                if name.startswith("recursive"):
                    assert "recursive editor launch refused" in screen, screen
                send_keys(q, "ret")
                deadline = time.monotonic() + 15
                while time.monotonic() < deadline:
                    screen = read_screen_text(q, str(d / "vram.bin"))
                    if "zDWED_MARKER" in screen:
                        break
                    time.sleep(0.2)
                (d / "resumed.txt").write_text(screen)
                assert "zDWED_MARKER" in screen, screen
            if failure:
                assert "Error" in saved_screen, saved_screen
                send_keys(q, "ret")
                time.sleep(0.25)
            if save_elsewhere:
                send_keys(q, "hmp:sendkey shift-f2")
                time.sleep(0.25)
                screen = read_screen_text(q, str(d / "vram.bin"))
                assert "Save file to" in screen, screen
                send_keys(q, "home+delete+c+ret")
                time.sleep(0.25)
                screen = read_screen_text(q, str(d / "vram.bin"))
                assert "Replace file" in screen, screen
                send_keys(q, "y")
                time.sleep(0.5)
                screen = read_screen_text(q, str(d / "vram.bin"))
                assert (
                    "zDWED_MARKER" in screen and "*" not in screen.splitlines()[-1]
                ), screen
            send_keys(q, "esc")
            if failure and not save_elsewhere:
                time.sleep(0.25)
                dirty_screen = read_screen_text(q, str(d / "vram.bin"))
                (d / "dirty.txt").write_text(dirty_screen)
                assert "Save changes to" in dirty_screen, dirty_screen
                assert "zDWED_MARKER" in dirty_screen, dirty_screen
                send_keys(q, "n")
            process.wait(timeout=15)
            assert process.returncode == 33, process.returncode
            actual = run(["mtype", "-i", spec, "::" + filename]).stdout
            backup = run(["mtype", "-i", spec, "::" + backup_name]).stdout
            if name.startswith(("memory-probe-", "screen-memory-", "list-memory-")):
                probe_log = run(["mtype", "-i", floppy, "::MEM.LOG"]).stdout
                (d / "memory.log").write_bytes(probe_log)
                assert b"PASS " in probe_log and b"FAIL" not in probe_log, probe_log
                assert (
                    run(["mtype", "-i", floppy, "::MEM.OK"]).stdout.strip()
                    == b"MEMORY PASS"
                )
                row["memory_probe"] = probe_log.decode("ascii").strip()
            if keyboard:
                assert (
                    run(["mtype", "-i", floppy, "::KEY.OK"]).stdout.strip()
                    == b"KEYBOARD PASS 13"
                )
            if undo_journal:
                probe_log = run(["mtype", "-i", floppy, "::UNDO.LOG"]).stdout
                (d / "undo.log").write_bytes(probe_log)
                assert b"PASS " in probe_log and b"FAIL" not in probe_log, probe_log
                assert (
                    run(["mtype", "-i", floppy, "::UNDO.OK"]).stdout.strip()
                    == b"UNDO JOURNAL PASS"
                )
                row["journal_probe"] = probe_log.decode("ascii").strip()
            if undo_storage:
                probe_log = run(["mtype", "-i", floppy, "::STORE.LOG"]).stdout
                (d / "store.log").write_bytes(probe_log)
                assert b"PASS " in probe_log and b"FAIL" not in probe_log, probe_log
                assert (
                    run(["mtype", "-i", floppy, "::STORE.OK"]).stdout.strip()
                    == b"ATOMIC STORAGE PASS"
                )
                row["storage_probe"] = probe_log.decode("ascii").strip()
            if save_probe:
                probe_log = run(["mtype", "-i", floppy, "::SAVE.LOG"]).stdout
                (d / "save.log").write_bytes(probe_log)
                assert b"PASS " in probe_log and b"FAIL" not in probe_log, probe_log
                assert (
                    run(["mtype", "-i", floppy, "::SAVE.OK"]).stdout.strip()
                    == b"SAVE FAULTS PASS"
                )
                row["save_probe"] = probe_log.decode("ascii").strip()
            if cache_probe:
                diagnostic = run(["mtype", "-i", spec, "::CACHERUN.LOG"]).stdout
                (d / "cache-runtime.log").write_bytes(diagnostic)
                assert not diagnostic.strip(), diagnostic
                probe_log = run(["mtype", "-i", floppy, "::CACHE.LOG"]).stdout
                (d / "cache.log").write_bytes(probe_log)
                assert b"PASS " in probe_log and b"FAIL" not in probe_log, probe_log
                assert (
                    run(["mtype", "-i", floppy, "::CACHE.OK"]).stdout.strip()
                    == b"CACHE SAFETY PASS"
                )
                row["cache_probe"] = probe_log.decode("ascii").strip()
            if real_transfer:
                diagnostic = run(["mtype", "-i", spec, "::MXFERRUN.LOG"]).stdout
                (d / "memxfer-runtime.log").write_bytes(diagnostic)
                assert not diagnostic.strip(), diagnostic
                probe_log = run(["mtype", "-i", floppy, "::MXFER.LOG"]).stdout
                (d / "memxfer.log").write_bytes(probe_log)
                assert b"PASS " in probe_log and b"FAIL" not in probe_log, probe_log
                assert (
                    run(["mtype", "-i", floppy, "::MXFER.OK"]).stdout.strip()
                    == b"REAL TRANSFER PASS"
                )
                row["real_transfer_probe"] = probe_log.decode("ascii").strip()
            if xfer_probe:
                diagnostic = run(["mtype", "-i", spec, "::XFERRUN.LOG"]).stdout
                (d / "xfer-runtime.log").write_bytes(diagnostic)
                assert not diagnostic.strip(), diagnostic
                probe_log = run(["mtype", "-i", floppy, "::XFER.LOG"]).stdout
                (d / "xfer.log").write_bytes(probe_log)
                assert b"PASS " in probe_log and b"FAIL" not in probe_log, probe_log
                assert (
                    run(["mtype", "-i", floppy, "::XFER.OK"]).stdout.strip()
                    == b"TRANSFER PASS"
                )
                row["transfer_probe"] = probe_log.decode("ascii").strip()
            if xms_probe:
                diagnostic = run(["mtype", "-i", spec, "::XMSRUN.LOG"]).stdout
                (d / "xms-runtime.log").write_bytes(diagnostic)
                assert not diagnostic.strip(), diagnostic
                probe_log = run(["mtype", "-i", floppy, "::XMS.LOG"]).stdout
                (d / "xms.log").write_bytes(probe_log)
                assert b"PASS " in probe_log and b"FAIL" not in probe_log, probe_log
                expected = b"CLASSIC XMS PASS" if "-classic-" in name else b"SXMS PASS"
                assert (
                    run(["mtype", "-i", floppy, "::XMS.OK"]).stdout.strip() == expected
                )
                row["xms_probe"] = probe_log.decode("ascii").strip()
            if tab_probe:
                assert table_refusals == 2, table_refusals
                row["table_refusals"] = table_refusals
                probe_log = run(["mtype", "-i", floppy, "::TAB.LOG"]).stdout
                (d / "tab.log").write_bytes(probe_log)
                assert b"PASS " in probe_log and b"FAIL" not in probe_log, probe_log
                assert (
                    run(["mtype", "-i", floppy, "::TAB.OK"]).stdout.strip()
                    == b"TAB DISPLAY PASS"
                )
                row["tab_probe"] = probe_log.decode("ascii").strip()
            if clipboard_probe:
                probe_log = run(["mtype", "-i", floppy, "::CLIP.LOG"]).stdout
                (d / "clip.log").write_bytes(probe_log)
                assert b"PASS " in probe_log and b"FAIL" not in probe_log, probe_log
                assert (
                    run(["mtype", "-i", floppy, "::CLIP.OK"]).stdout.strip()
                    == b"CLIPBOARD PASS"
                )
                row["clipboard_probe"] = probe_log.decode("ascii").strip()
            if external:
                assert (
                    run(["mtype", "-i", spec, "::COMMAND.TXT"]).stdout.strip()
                    == b"EXTERNAL_COMMAND_OK"
                )
                assert (
                    run(["mtype", "-i", spec, "::CWD.TXT"]).stdout.strip()
                    == b"C:\\DWED"
                )
            expected = original if failure else b"z" + original if edit else original
            if keyboard:
                expected = b"z" + original[:-2]
            if name.startswith("list-ui-"):
                expected = b"z" + original.replace(
                    b"procedure second;", b"xprocedure second;"
                )
            if name.startswith("menu-copy"):
                expected = b"z" + original.replace(b"DWED_MARKER", b"DWED_MARKERzD")
            if name.startswith("menu-cancel"):
                expected = original[1:]
            if name.startswith("split-whitespace"):
                expected = original + b"\r\n"
            if name.startswith("indent-enter-"):
                expected = b"DWED_MARKER\r\n \tA\r\n \tx  B"
            if name.startswith("remove-final"):
                expected = original[:-2]
            row.update(
                completed=True,
                actual_hex=actual.hex(),
                backup_matches_expected=backup
                == (
                    previous_backup
                    if failure or rejected or name.startswith("new-file")
                    else original
                ),
                exact_match=actual == expected,
            )
            assert (
                run(["mtype", "-i", spec, "::$ED0000.TMP"]).stdout
                == b"OTHER_EDITOR_SAVE\r\n"
            )
            listing = run(["mdir", "-b", "-i", spec, "::"]).stdout
            assert b"$ED0001.TMP" not in listing.upper(), listing
            (d / "original.bin").write_bytes(original)
            (d / "saved.bin").write_bytes(actual)
        row["dos_version"] = (
            run(["mtype", "-i", control_spec, "::DOSVER.TXT"])
            .stdout.decode("ascii")
            .strip()
        )
        if protected_media:
            before_vector = run(["mtype", "-i", floppy, "::VECBEF.BIN"]).stdout
            after_vector = run(["mtype", "-i", floppy, "::VECAFT.BIN"]).stdout
            assert len(before_vector) == 4 and after_vector == before_vector
            row["critical_vector_restored"] = True
            if save_elsewhere:
                assert (
                    run(["mtype", "-i", control_spec, "::SAMPLE.TXT"]).stdout
                    == b"z" + original
                )
                row["saved_to_writable_drive"] = True
            assert (
                hashlib.sha256(protected_media.read_bytes()).hexdigest()
                == protected_before
            )
            row["write_protected_image_unchanged"] = True
    except Exception as error:  # noqa: BLE001 -- record diagnostics, then fail the suite below
        row.update(completed=False, error=str(error))
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
    rows.append(row)
    (WORK / "results.json").write_text(json.dumps(rows, indent=2) + "\n")
    print(
        {key: value for key, value in row.items() if not key.endswith("_hex")},
        flush=True,
    )
print("Finished", flush=True)

assert all(
    r.get("completed") and r.get("exact_match") and r.get("backup_matches_expected")
    for r in rows
), [
    {key: value for key, value in row.items() if not key.endswith("_hex")}
    for row in rows
]
