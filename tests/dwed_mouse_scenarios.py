"""Real CuteMouse/PS2 menu and clipboard tests with passive INT 33h telemetry."""

import hashlib
import struct
import time

from screen_expect import read_screen_text, send_keys
from test_compat_bpb_qemu import run

DRIVER_SHA256 = "822cf550c9e19a22785722d2306aa08ede10ff20bfe931d5a81a15f77c5f363e"
ORIGINAL = b"DWED_MARKER\r\nA\tB\r\n"
CASES = [
    ("mouse-edit-" + kind + "-" + mode, mode, ORIGINAL, False)
    for kind in ("menu", "drag")
    for mode in ("low", "high")
]
CASES += [("mouse-edit-mono-low", "low", ORIGINAL, False)]


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
    if "-menu-" in name:
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
    keys("esc")
    process.wait(timeout=15)
    assert process.returncode == 33, process.returncode
    assert run(["mtype", "-i", spec, "::SAMPLE.TXT"]).stdout == expected
    assert run(["mtype", "-i", spec, "::SAMPLE.BAK"]).stdout == original
    return {
        "completed": True,
        "exact_match": True,
        "backup_matches_expected": True,
        "mouse_driver_sha256": DRIVER_SHA256,
        "mouse_positions": moves,
    }
