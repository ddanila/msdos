"""Stateful save/close/exit scenarios for test_dwed_qemu's private guests."""

import time

from screen_expect import read_screen_text, send_keys
from test_compat_bpb_qemu import put, run

ORIGINAL = b"DWED_MARKER\r\nsecond line\r\n"
OLD_BACKUP = b"PREVIOUS_BACKUP\r\n"
EXISTING = b"EXISTING_DESTINATION\r\n"
NAMES = (
    "exit-save",
    "exit-cancel",
    "close-discard",
    "close-cancel",
    "saveas-cancel",
    "unnamed-exit",
    "unnamed-close",
    "unnamed-saveall",
    "unnamed-cancel-name",
    "unnamed-cancel-all",
    "overwrite-no",
    "overwrite-yes",
)
CASES = [("dialog-" + name + "-low", "low", ORIGINAL, False) for name in NAMES]
CASES += [("dialog-startup-unnamed-low", "low", ORIGINAL, False)]
CASES += [("dialog-startup-command-low", "low", ORIGINAL, False)]
CASES += [
    ("dialog-" + name + "-high", "high", ORIGINAL, False)
    for name in ("exit-save", "unnamed-saveall")
]
CASES += [
    (
        "dialog-exit-full-low",
        "low",
        b"DWED_MARKER\r\n" + (b"0123456789" * 8 + b"\r\n") * 100,
        False,
    )
]


def prepare(spec, name):
    if name.startswith("dialog-startup-"):
        put(spec, "DWED/NONAME.TXT", b"EXISTING_UNNAMED_SENTINEL\r\n")
    if name.startswith("dialog-overwrite"):
        put(spec, "DWED/RESULT.TXT", EXISTING)
        put(spec, "DWED/RESULT.BAK", b"OLDER_RESULT_BACKUP\r\n")


def exercise(q, process, directory, spec, original, name):
    kind = name.removeprefix("dialog-").rsplit("-", 1)[0]
    startup = kind.startswith("startup-")
    startup_command = kind == "startup-command"
    if startup:
        kind = "unnamed-exit"

    def wait_for(text, stage):
        deadline = time.monotonic() + 10
        screen = ""
        while time.monotonic() < deadline and process.poll() is None:
            screen = read_screen_text(q, str(directory / "vram.bin"))
            if text in screen:
                (directory / (stage + ".txt")).write_text(screen)
                return screen
            time.sleep(0.1)
        raise AssertionError(f"{stage}: expected {text!r}\n{screen}")

    def key(sequence):
        send_keys(q, sequence)
        time.sleep(0.25)

    def file_menu(letter):
        key("hmp:sendkey alt-f")
        key(letter)

    def enter_name():
        wait_for("Save file to", "name")
        key("r+e+s+u+l+t+dot+t+x+t+ret")

    def prompt(answer, stage):
        wait_for("Save changes to", stage)
        key(answer)

    unnamed = kind.startswith(("unnamed", "overwrite"))
    batch = kind in ("unnamed-saveall", "unnamed-cancel-all")
    if not unnamed or batch:
        key("home+z")
    if unnamed:
        if not startup:
            file_menu("n")
        wait_for("Untitled", "new")
        if startup_command:
            key("f5")
            wait_for("Press any key to return to the editor.", "external")
            key("ret")
            wait_for("Untitled", "resumed-unnamed")
        key("n+e+w+b+u+f+f+e+r")

    expected = original
    backup_expected = OLD_BACKUP
    new_saved = False
    if kind == "exit-save":
        key("esc")
        prompt("y", "exit")
        expected = b"z" + original
        backup_expected = original
    elif kind in ("exit-cancel", "close-cancel"):
        key("esc" if kind.startswith("exit") else "hmp:sendkey alt-f4")
        prompt("c", "cancel")
        screen = wait_for("zDWED_MARKER", "retained")
        assert "*" in screen.splitlines()[-1], screen
        key("esc")
        prompt("n", "discard-after-cancel")
    elif kind == "close-discard":
        key("hmp:sendkey alt-f4")
        prompt("n", "discard")
    elif kind == "saveas-cancel":
        file_menu("a")
        wait_for("Save file to", "name")
        key("esc")
        screen = wait_for("zDWED_MARKER", "retained")
        assert "*" in screen.splitlines()[-1], screen
        key("f2")
        key("esc")
        expected = b"z" + original
        backup_expected = original
    elif kind == "exit-full":
        key("esc")
        prompt("y", "exit")
        wait_for("Error", "write-error")
        key("ret")
        screen = wait_for("zDWED_MARKER", "retained")
        assert "*" in screen.splitlines()[-1], screen
        key("esc")
        prompt("n", "discard-after-error")
    elif kind in ("unnamed-exit", "unnamed-close", "unnamed-cancel-name"):
        key("hmp:sendkey alt-f4" if kind == "unnamed-close" else "esc")
        prompt("y", "unnamed-save")
        if kind == "unnamed-cancel-name":
            wait_for("Save file to", "name")
            key("esc")
            screen = wait_for("newbuffer", "retained")
            assert "Untitled" in screen and "*" in screen.splitlines()[-1], screen
            key("esc")
            prompt("n", "discard-unnamed")
        else:
            enter_name()
            new_saved = True
            if kind == "unnamed-close":
                wait_for("SAMPLE.TXT", "previous-document")
                key("esc")
    elif batch:
        file_menu("l")
        wait_for("Save file to", "name")
        if kind == "unnamed-cancel-all":
            key("esc")
            wait_for("newbuffer", "retained")
            key("esc")
            prompt("n", "discard-new")
            prompt("n", "discard-original")
        else:
            enter_name()
            wait_for("result.txt", "saved-all")
            key("esc")
            new_saved = True
            expected = b"z" + original
            backup_expected = original
    elif kind.startswith("overwrite"):
        key("f2")
        enter_name()
        wait_for("Replace existing", "replace")
        key("y" if kind == "overwrite-yes" else "n")
        if kind == "overwrite-yes":
            new_saved = True
            key("esc")
        else:
            screen = wait_for("newbuffer", "retained")
            assert "Untitled" in screen and "*" in screen.splitlines()[-1], screen
            key("esc")
            prompt("n", "discard-after-refusal")
    else:
        raise AssertionError(kind)

    process.wait(timeout=15)
    assert process.returncode == 33, process.returncode
    actual = run(["mtype", "-i", spec, "::SAMPLE.TXT"]).stdout
    backup = run(["mtype", "-i", spec, "::SAMPLE.BAK"]).stdout
    assert (
        run(["mtype", "-i", spec, "::$ED0000.TMP"]).stdout == b"OTHER_EDITOR_SAVE\r\n"
    )
    if startup:
        assert (
            run(["mtype", "-i", spec, "::DWED/NONAME.TXT"]).stdout
            == b"EXISTING_UNNAMED_SENTINEL\r\n"
        )
    assert actual == expected, (actual, expected)
    assert backup == backup_expected, (backup, backup_expected)
    if new_saved or kind.startswith("overwrite"):
        result = run(["mtype", "-i", spec, "::DWED/RESULT.TXT"]).stdout
        assert result == (b"newbuffer" if new_saved else EXISTING), result
    else:
        listing = run(["mdir", "-b", "-i", spec, "::DWED"]).stdout.upper()
        assert b"RESULT.TXT" not in listing, listing
    if kind == "overwrite-yes":
        assert run(["mtype", "-i", spec, "::DWED/RESULT.BAK"]).stdout == EXISTING
    if kind == "overwrite-no":
        assert (
            run(["mtype", "-i", spec, "::DWED/RESULT.BAK"]).stdout
            == b"OLDER_RESULT_BACKUP\r\n"
        )
    return {
        "completed": True,
        "actual_hex": actual.hex(),
        "exact_match": True,
        "backup_matches_expected": True,
        "dialog_flow": kind,
    }
