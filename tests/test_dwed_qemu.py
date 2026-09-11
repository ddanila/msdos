#!/usr/bin/env python3
"""Test the source-built DWED launcher and editor on private LOW/HIGH images.

Requires a built parent out/floppy.img. An explicit launcher override supports
historical-binary negative controls; normal runs use only source-built programs.
"""

import argparse
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
parser.add_argument("--launcher", type=Path, help="override the source-built launcher")
parser.add_argument(
    "--case", action="append", help="run only the named case (repeatable)"
)
args = parser.parse_args()
overlay = args.build.resolve() / "DWEDOVL.exe"
launcher = (args.launcher or args.build / "DWED.COM").resolve()
for required in (overlay, launcher, ROOT / "out/floppy.img"):
    if not required.is_file():
        parser.error(f"missing input: {required}")
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
from dwed_tab_scenarios import CASES as TAB_CASES
from dwed_tab_scenarios import exercise as exercise_tabs
from dwed_tab_scenarios import prepare as prepare_tabs
from dwed_undo_scenarios import CASES as UNDO_CASES
from dwed_undo_scenarios import exercise as exercise_undo
from screen_expect import QMPConnection, read_screen_text, send_keys
from test_compat_bpb_qemu import disk, put, run

WORK = Path(tempfile.mkdtemp(prefix="dwed-qemu-", dir=ROOT / "out"))
print(WORK, flush=True)
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
    for kind in ("disk-full", "read-only")
    for mode in ("low", "high")
]
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
cases += DIALOG_CASES
cases += UNDO_CASES
cases += CLIPBOARD_CASES
cases += TAB_CASES
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
    any(case[0].startswith("tab-probe-") for case in cases)
    and not (args.build.resolve() / "TABTEST.exe").is_file()
):
    parser.error("tab probes require an editor built with --tests")
for name, mode, original, edit in cases:
    startup = name.startswith("dialog-startup-")
    keyboard = name.startswith("keyboard-")
    undo_journal = name.startswith("undo-journal-")
    undo_storage = name.startswith("undo-storage-")
    clipboard_probe = name.startswith("clipboard-probe-")
    tab_probe = name.startswith("tab-probe-")
    rejected = name.startswith("reject-")
    failure = name.startswith(("disk-full", "read-only"))
    filename = "SAMPLE.BAK" if name.startswith("backup-file") else "SAMPLE.TXT"
    backup_name = "SAMPLE.BK!" if name.startswith("backup-file") else "SAMPLE.BAK"
    d = WORK / name
    d.mkdir()
    floppy = d / "boot.img"
    shutil.copyfile(ROOT / "out/floppy.img", floppy)
    hdd, _, _ = disk(d, {})
    spec = f"{hdd}@@32256"
    run(["mmd", "-i", spec, "::DWED"])
    for file, dos_name in (
        (launcher, "DWED.COM"),
        (overlay, "DWEDOVL.EXE"),
        (repo / "BIN/DWED.CFG", "DWED.CFG"),
    ):
        run(["mcopy", "-o", "-i", spec, file, "::DWED/" + dos_name])
    if not name.startswith("new-file"):
        put(spec, filename, original)
    external = name.startswith(("external", "recursive"))
    if external:
        cfg = (
            (repo / "BIN/DWED.CFG")
            .read_bytes()
            .replace(b"usr.def.f5=dir", b"usr.def.f5=C:\\RUNTEST.BAT")
        )
        put(spec, "DWED/DWED.CFG", cfg)
        batch = b"@ECHO OFF\r\n"
        if name.startswith("recursive"):
            batch += b"C:\\DWED\\DWED.COM\r\nIF NOT ERRORLEVEL 1 GOTO FAIL\r\n"
        batch += b"ECHO EXTERNAL_COMMAND_OK>C:\\COMMAND.TXT\r\nCD \\\r\nA:\r\nECHO EXTERNAL_COMMAND_DONE\r\n:FAIL\r\n"
        put(spec, "RUNTEST.BAT", batch)
    previous_backup = b"PREVIOUS_BACKUP\r\n"
    put(spec, backup_name, previous_backup)
    put(spec, "$ED0000.TMP", b"OTHER_EDITOR_SAVE\r\n")
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
    put(floppy, "CONFIG.SYS", config)
    probe_command = ""
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
    invocation = "CD \\DWED\r\nDWED.COM"
    if name.startswith("outside-directory"):
        invocation = "CD \\\r\nC:\\DWED\\DWED.COM"
    put(
        floppy,
        "AUTOEXEC.BAT",
        (
            "@ECHO OFF\r\n"
            + probe_command
            + "C:\r\n"
            + invocation
            + ("" if startup else " C:\\" + filename)
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
    process = subprocess.Popen(
        argv, stdout=subprocess.DEVNULL, stderr=(d / "qemu.log").open("wb")
    )
    row = {"case": name, "mode": mode, "original_hex": original.hex()}
    try:
        q = QMPConnection(str(socket))
        end = time.monotonic() + 30
        screen = ""
        while time.monotonic() < end and process.poll() is None:
            screen = read_screen_text(q, str(d / "vram.bin"))
            if (
                (rejected and "file was not opened" in screen)
                or (startup and "Untitled" in screen)
                or (not original and "SAMPLE.TXT" in screen)
                or "DWED_MARKER" in screen
            ):
                break
            time.sleep(0.2)
        (d / "opened.txt").write_text(screen)
        if rejected:
            assert "file was not opened" in screen, screen
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
        q.human_cmd(f'screendump "{d}/opened.ppm"')
        if name.startswith("menu-"):
            assert all(
                label in screen.splitlines()[0]
                for label in ("File", "Edit", "Search", "Options", "Help")
            ), screen
        if name.startswith("tab-edit-"):
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
            send_keys(q, "esc")
            if failure:
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
            if tab_probe:
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
            if name.startswith("menu-copy"):
                expected = b"z" + original.replace(b"DWED_MARKER", b"DWED_MARKERzD")
            if name.startswith("menu-cancel"):
                expected = original[1:]
            if name.startswith("split-whitespace"):
                expected = original + b"\r\n"
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
