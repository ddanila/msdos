"""Real editor undo/redo scenarios on the maintained QEMU boundary."""

import time

from screen_expect import read_screen_text, send_keys
from test_compat_bpb_qemu import run

ORIGINAL = b"DWED_MARKER\r\nsecond line\r\n"
CASES = [
    ("undo-edit-" + kind + "-low", "low", ORIGINAL, False)
    for kind in (
        "typing",
        "split",
        "merge",
        "cut",
        "paste",
        "multi-cut",
        "save",
        "windows",
        "branch",
        "indent",
        "move",
    )
]
CASES += [("undo-edit-typing-high", "high", ORIGINAL, False)]
CASES += [
    (
        "undo-edit-capacity-low",
        "low",
        b"DWED_MARKER\r\n" + (b"R" * 200 + b"\r\n") * 100,
        False,
    )
]


def exercise(q, process, directory, spec, original, name):
    kind = name.removeprefix("undo-edit-").rsplit("-", 1)[0]

    def keys(value):
        send_keys(q, value)
        time.sleep(0.5 if value.endswith(" 200") else 0.25)

    def screen(label):
        value = read_screen_text(q, str(directory / "vram.bin"))
        (directory / (label + ".txt")).write_text(value)
        return value

    def undo():
        if kind == "move":
            keys("hmp:sendkey alt-e")
            keys("u")
        else:
            keys("hmp:sendkey ctrl-z")

    def redo():
        keys("hmp:sendkey alt-e")
        keys("r")

    def clean(label):
        value = screen(label)
        assert "*" not in value.splitlines()[-1], value

    keys("home")
    expected = original
    saved = False
    if kind == "capacity":
        for _ in range(5):
            keys("hmp:sendkey shift-pgdn 200")
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            value = screen("capacity-selection")
            if "102/102" in value:
                break
            time.sleep(0.2)
        assert "102/102" in value, value
        time.sleep(0.3)
        keys("hmp:sendkey ctrl-x")
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            value = screen("capacity-error")
            if "Cannot record edit" in value:
                break
            time.sleep(0.2)
        assert "Cannot record edit" in value, value
        keys("ret")
        clean("capacity-restored")
    elif kind in ("typing", "save", "windows", "branch"):
        keys("z")
        if kind == "windows":
            keys("hmp:sendkey alt-f")
            keys("n")
            keys("b")
            undo()
            clean("other-document-clean")
            keys("hmp:sendkey alt-f4")
            assert "zDWED_MARKER" in screen("first-document-retained")
        if kind == "save":
            keys("f2")
            clean("saved")
            saved = True
        undo()
        value = screen("undone")
        assert "DWED_MARKER" in value and "zDWED_MARKER" not in value, value
        if kind == "save":
            assert "*" in value.splitlines()[-1], value
        else:
            clean("undone-clean")
        if kind == "branch":
            keys("x")
            keys("hmp:sendkey ctrl-shift-z 200")
            value = screen("branch-redo-invalidated")
            assert "xDWED_MARKER" in value and "zDWED_MARKER" not in value, value
            expected = b"x" + original
        elif kind == "typing":
            # Exercise the shortcut separately from the menu path.
            keys("hmp:sendkey ctrl-shift-z 200")
        else:
            redo()
        if kind != "branch":
            assert "zDWED_MARKER" in screen("redone")
        if kind == "save":
            clean("redo-to-save")
        if kind != "branch":
            expected = b"z" + original
    else:
        if kind == "indent":
            keys("hmp:sendkey shift-down 200")
            keys("tab")
            expected = b" " * 8 + original
        elif kind == "move":
            keys("hmp:sendkey ctrl-shift-pgdn 200")
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                value = screen("line-moved")
                if value.splitlines()[1] == "second line":
                    break
                time.sleep(0.2)
            assert value.splitlines()[1] == "second line", value
            time.sleep(0.3)
            # Retain coverage of Ctrl-Z immediately after a completed move,
            # then independently exercise the menu pair below.
            keys("hmp:sendkey ctrl-z")
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                value = screen("move-shortcut-undone")
                if (
                    value.splitlines()[1] == "DWED_MARKER"
                    and "*" not in value.splitlines()[-1]
                ):
                    break
                time.sleep(0.2)
            assert value.splitlines()[1] == "DWED_MARKER", value
            clean("move-shortcut-clean")
            redo()
            expected = b"second line\r\nDWED_MARKER\r\n"
        elif kind == "split":
            keys("right+ret")
            expected = b"D\r\n" + original[1:]
        elif kind == "merge":
            keys("down+home+backspace")
            expected = original.replace(b"\r\n", b"", 1)
        elif kind in ("cut", "paste", "multi-cut"):
            if kind == "multi-cut":
                keys("hmp:sendkey shift-down 200")
                for _ in range(3):
                    keys("hmp:sendkey shift-right 200")
                expected = b"ond line\r\n"
            else:
                for _ in range(2):
                    keys("hmp:sendkey shift-right 200")
                expected = original[2:]
            if kind == "paste":
                keys("hmp:sendkey ctrl-c")
                keys("end")
                keys("hmp:sendkey ctrl-v")
                expected = original.replace(b"DWED_MARKER", b"DWED_MARKERDW")
            else:
                keys("hmp:sendkey ctrl-x")
        undo()
        clean("undone-clean")
        value = screen("undone")
        assert "DWED_MARKER" in value and "second line" in value, value
        if kind == "cut":
            # Undo must restore the selected range, not just the bytes.
            keys("backspace")
        else:
            redo()
    if kind != "capacity" and not saved:
        keys("f2")
    keys("esc")
    process.wait(timeout=15)
    assert process.returncode == 33, process.returncode
    actual = run(["mtype", "-i", spec, "::SAMPLE.TXT"]).stdout
    backup = run(["mtype", "-i", spec, "::SAMPLE.BAK"]).stdout
    expected_backup = b"PREVIOUS_BACKUP\r\n" if kind == "capacity" else original
    assert actual == expected, (actual, expected)
    assert backup == expected_backup, backup
    return {
        "completed": True,
        "exact_match": True,
        "backup_matches_expected": True,
        "undo_flow": kind,
    }
