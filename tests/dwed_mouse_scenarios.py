"""Real CuteMouse/PS2 menus, dialogs and clipboard with passive INT 33h telemetry."""

import hashlib
import struct
import time

from screen_expect import read_screen_text, send_keys
from test_compat_bpb_qemu import put, run

DRIVER_SHA256 = "822cf550c9e19a22785722d2306aa08ede10ff20bfe931d5a81a15f77c5f363e"
ORIGINAL = b"DWED_MARKER\r\nA\tB\r\n"
CASES = [
    ("mouse-edit-" + kind + "-" + mode, mode, ORIGINAL, False)
    for kind in ("menu", "drag")
    for mode in ("low", "high")
]
CASES += [("mouse-edit-mono-low", "low", ORIGINAL, False)]
CASES += [
    ("mouse-edit-dialog-" + kind + "-" + mode, mode, ORIGINAL, False)
    for kind in (
        "save",
        "discard",
        "cancel",
        "replace",
        "keep",
        "replace-cancel",
        "navigation",
    )
    for mode in ("low", "high")
]
CASES += [("mouse-edit-dialog-mono-low", "low", ORIGINAL, False)]
OTHER = b"OTHER DOCUMENT\r\n"
OTHER_BACKUP = b"OLDER OTHER DOCUMENT\r\n"


def prepare(spec, name):
    if name.startswith("mouse-edit-dialog-"):
        put(spec, "OTHER.TXT", OTHER)
        put(spec, "OTHER.BAK", OTHER_BACKUP)


def validate_driver(path):
    if hashlib.sha256(path.read_bytes()).hexdigest() != DRIVER_SHA256:
        raise ValueError("mouse fixture differs from the pinned CuteMouse executable")


def exercise(q, process, directory, spec, original, name):
    pointer = run(["mtype", "-i", spec, "::MOUSE.PTR"]).stdout
    assert len(pointer) == 8 and pointer[:4] == b"DWMP", pointer
    offset, segment = struct.unpack("<HH", pointer[4:])
    address = segment * 16 + offset
    moves = []

    def state():
        q.human_cmd(f'pmemsave {address} 6 "{directory / "mouse.bin"}"')
        return struct.unpack("<HHH", (directory / "mouse.bin").read_bytes())

    def move(x, y):
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            buttons, px, py = state()
            if (px // 8, py // 8) == (x, y):
                time.sleep(0.15)
                moves.append([x, y, buttons])
                return

            def step(delta):
                if delta == 0:
                    return 0
                return (1 if delta > 0 else -1) * min(4, max(1, abs(delta) // 8))

            dx = step(x * 8 + 4 - px)
            dy = step(y * 8 + 4 - py)
            q.human_cmd(f"mouse_move {dx} {dy}")
            time.sleep(0.06)
        raise AssertionError(("mouse target", (x, y), state()))

    def button(value):
        q.human_cmd(f"mouse_button {value}")
        time.sleep(0.25)

    def click(x, y, value=1):
        move(x, y)
        button(value)
        button(0)

    def keys(value):
        send_keys(q, value)
        time.sleep(0.5 if value.endswith(" 200") else 0.25)

    def expect(needle, label):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            text = read_screen_text(q, str(directory / "vram.bin"))
            (directory / (label + ".txt")).write_text(text)
            if needle in text:
                return text
            time.sleep(0.2)
        raise AssertionError(text)

    expected = original
    expected_backup = original
    expected_other, expected_other_backup = OTHER, OTHER_BACKUP
    focus_attributes = {}
    exited = False
    if "-dialog-" in name:
        kind = name[len("mouse-edit-dialog-") :].rsplit("-", 1)[0]

        def control(label):
            screen = expect(label, "control-" + label[1])
            for y, line in enumerate(screen.splitlines()):
                if label in line:
                    return line.index(label) + len(label) // 2, y
            raise AssertionError(screen)

        def choose(label):
            click(*control(label))

        def attribute(label):
            x, y = control(label)
            base = 0xB0000 if kind == "mono" else 0xB8000
            path = directory / "button-attribute.bin"
            q.human_cmd(f'pmemsave {base + (y * 80 + x) * 2 + 1} 1 "{path}"')
            return path.read_bytes()[0]

        keys("home+z")
        if kind == "cancel":
            keys("hmp:sendkey shift-left")
        if kind in ("replace", "keep", "replace-cancel"):
            keys("hmp:sendkey shift-f2")
            expect("Save file to", "save-as")
            keys("hmp:sendkey ctrl-a")
            keys("dot+dot+backslash+o+t+h+e+r+dot+t+x+t+ret")
            expect("Replace file", "replace-prompt")
            label = {
                "replace": "[Y Replace]",
                "keep": "[N Keep]",
                "replace-cancel": "[C Cancel]",
            }[kind]
            choose(label)
            if kind == "replace":
                screen = expect("other.txt", "replaced")
                assert "*" not in screen.splitlines()[-1], screen
                expected_other, expected_other_backup = b"z" + original, OTHER
            else:
                screen = expect("zDWED_MARKER", "replacement-kept")
                assert "*" in screen.splitlines()[-1], screen
                keys("esc")
                choose("[N Discard]")
                exited = True
            expected_backup = b"PREVIOUS_BACKUP\r\n"
        else:
            keys("esc")
            expect("Unsaved changes", "unsaved-prompt")
            focused_color = attribute("[Y Save]")
            ordinary_color = attribute("[C Cancel]")
            assert focused_color != ordinary_color
            focus_attributes = {"focused": focused_color, "ordinary": ordinary_color}
            if kind in ("save", "mono"):
                save = control("[Y Save]")
                cancel = control("[C Cancel]")
                # Ignore blank areas and the right button.
                click(0, 24)
                click(*save, value=2)
                expect("Unsaved changes", "ignored-clicks")
                # Releasing over another button must not activate either one.
                move(*save)
                button(1)
                move(*cancel)
                button(0)
                expect("Unsaved changes", "drag-cancelled")
                choose("[Y Save]")
                expected = b"z" + original
                exited = True
            elif kind == "discard":
                choose("[N Discard]")
                expected_backup = b"PREVIOUS_BACKUP\r\n"
                exited = True
            elif kind == "cancel":
                choose("[C Cancel]")
                screen = expect("zDWED_MARKER", "cancelled")
                assert "*" in screen.splitlines()[-1], screen
                # The selected z survives the dialog and can still be copied.
                keys("hmp:sendkey ctrl-c")
                keys("end")
                keys("hmp:sendkey ctrl-v")
                expect("zDWED_MARKERz", "selection-preserved")
                keys("f2")
                expected = b"zDWED_MARKERz\r\nA\tB\r\n"
            elif kind == "navigation":
                # Left wraps from Save to Cancel; Enter activates focus.
                keys("left")
                assert attribute("[C Cancel]") == focused_color
                assert attribute("[Y Save]") == ordinary_color
                keys("ret")
                expect("zDWED_MARKER", "keyboard-cancelled")
                keys("esc+right+left+tab")
                keys("hmp:sendkey shift-tab")
                keys("spc")
                expected = b"z" + original
                exited = True
    elif "-menu-" in name:
        keys("home+z")
        click(2, 0)
        expect("Save", "file-menu")
        click(3, 4)
        click(10, 0)
        expect("Undo", "edit-menu")
        click(9, 2)
        text = expect("DWED_MARKER", "undone")
        assert "zDWED_MARKER" not in text, text
        click(10, 0)
        click(9, 3)
        expect("zDWED_MARKER", "redone")
        expected = b"z" + original
    else:
        click(1, 2)
        button(1)
        move(8, 2)
        button(0)
        click(8, 2, 2)
        expect("Cut", "popup-cancel")
        keys("esc")
        click(8, 2, 2)
        expect("Cut", "popup-cut")
        keys("ret")
        expect("\nAB", "cut")
        keys("hmp:sendkey ctrl-z")
        expect("A       B", "cut-undone")
        keys("hmp:sendkey ctrl-shift-z 200")
        expect("\nAB", "cut-redone")
        click(1, 2, 2)
        expect("Paste", "popup-paste")
        keys("ret")
        expect("A       B", "pasted")
        keys("hmp:sendkey ctrl-z")
        expect("\nAB", "paste-undone")
        keys("hmp:sendkey ctrl-shift-z 200")
        expect("A       B", "paste-redone")
        keys("f2")
    if not exited:
        keys("esc")
    process.wait(timeout=15)
    assert process.returncode == 33, process.returncode
    if "-dialog-" in name:
        assert run(["mtype", "-i", spec, "::OTHER.TXT"]).stdout == expected_other
        assert run(["mtype", "-i", spec, "::OTHER.BAK"]).stdout == expected_other_backup
    assert run(["mtype", "-i", spec, "::SAMPLE.TXT"]).stdout == expected
    assert run(["mtype", "-i", spec, "::SAMPLE.BAK"]).stdout == expected_backup
    return {
        "completed": True,
        "exact_match": True,
        "backup_matches_expected": True,
        "mouse_driver_sha256": DRIVER_SHA256,
        "mouse_positions": moves,
        "button_attributes": focus_attributes,
    }
