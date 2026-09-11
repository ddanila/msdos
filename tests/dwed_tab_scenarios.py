"""Tab bytes, visual columns, selection attributes, and hardware cursor checks."""

import time

from screen_expect import read_screen_text, send_keys
from test_compat_bpb_qemu import put, run

ORIGINAL = b"DWED_MARKER\r\nA\tB\t\x80\xff\r\n0123456789ABC\r\nxy\r\n\t\tZ\r\n"
CASES = [
    ("tab-edit-" + kind + "-" + mode, mode, ORIGINAL, False)
    for kind in ("layout", "insert")
    for mode in ("low", "high")
]
CASES += [
    ("tab-edit-scroll-low", "low", b"DWED_MARKER\r\n" + b"\t" * 40 + b"Z\r\n", False),
    ("tab-edit-width-low", "low", ORIGINAL, False),
    ("tab-edit-zero-low", "low", ORIGINAL, False),
    ("tab-edit-overwrite-low", "low", ORIGINAL, False),
    ("tab-edit-limit-low", "low", b"DWED_MARKER\r\n" + b"A" * 255 + b"\r\n", False),
]
CASES += [
    (
        "tab-edit-indent-limit-low",
        "low",
        b"DWED_MARKER\r\n" + b"A" * 255 + b"\r\n",
        False,
    ),
    ("tab-edit-unindent-low", "low", b"DWED_MARKER\r\n  \tA\r\n", False),
]


def prepare(spec, name, config):
    if name in ("tab-edit-width-low", "tab-edit-zero-low"):
        value = b"3" if name == "tab-edit-width-low" else b"0"
        put(
            spec,
            "DWED/DWED.CFG",
            config.replace(b"tab_size = 8", b"tab_size = " + value),
        )


def exercise(q, process, directory, spec, original, name):
    kind = name.removeprefix("tab-edit-").rsplit("-", 1)[0]
    width = 3 if kind == "width" else 8

    def keys(value):
        send_keys(q, value)
        time.sleep(0.5 if value.endswith(" 200") else 0.25)

    def capture():
        text = read_screen_text(q, str(directory / "vram.bin"))
        (directory / "screen.txt").write_text(text)
        q.human_cmd(f'pmemsave 0x450 19 "{directory / "cursor.bin"}"')
        cursor = (directory / "cursor.bin").read_bytes()
        assert cursor[18] == 0, cursor  # The editor uses video page zero.
        return text, (directory / "vram.bin").read_bytes(), tuple(cursor[:2])

    def expect_cursor(x, y):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            text, raw, cursor = capture()
            if cursor == (x, y):
                return text, raw
            time.sleep(0.2)
        raise AssertionError((cursor, (x, y), text))

    keys("down+home")
    text, raw = expect_cursor(0, 2)
    expected = original
    saved = False
    if kind == "unindent":
        keys("right+right+right")
        expect_cursor(width, 2)
        keys("hmp:sendkey shift-tab 200")
        expect_cursor(0, 2)
        keys("hmp:sendkey ctrl-z")
        expect_cursor(width, 2)
        keys("hmp:sendkey ctrl-shift-z 200")
        expect_cursor(0, 2)
        expected = original.replace(b"  \tA", b"A")
        keys("f2")
        saved = True
    elif kind in ("limit", "indent-limit"):
        if kind == "indent-limit":
            keys("up+home")
            keys("hmp:sendkey shift-down 200")
            keys("hmp:sendkey shift-end 200")
            keys("tab")
        else:
            keys("end+tab")
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            text, _, _ = capture()
            if "Resulting line exceeds 255 bytes" in text:
                break
            time.sleep(0.2)
        assert "Resulting line exceeds 255 bytes" in text, text
        keys("ret")
        text, raw = expect_cursor(79, 2)
        assert "*" not in text.splitlines()[-1], text
    elif kind == "overwrite":
        keys("right+right+insert+tab")
        expect_cursor(width * 2, 2)
        keys("hmp:sendkey ctrl-z")
        expect_cursor(width, 2)
        keys("hmp:sendkey ctrl-shift-z 200")
        expect_cursor(width * 2, 2)
        expected = original.replace(b"A\tB", b"A\t\t")
        keys("f2")
        saved = True
    elif kind == "scroll":
        keys("end")
        text, raw = expect_cursor(79, 2)
        assert raw[(2 * 80 + 78) * 2] == ord("Z"), text
        assert "322" in text.splitlines()[-1], text
        keys("home")
        expect_cursor(0, 2)
    elif kind == "insert":
        keys("right+tab")
        expect_cursor(width, 2)
        keys("hmp:sendkey ctrl-z")
        expect_cursor(1, 2)
        keys("hmp:sendkey alt-e")
        keys("r")
        expect_cursor(width, 2)
        keys("backspace")
        expect_cursor(1, 2)
        keys("hmp:sendkey ctrl-z")
        expect_cursor(width, 2)
        expected = original.replace(b"A\tB", b"A\t\tB")
        keys("f2")
        saved = True
    else:
        row = raw[2 * 160 : 3 * 160 : 2]
        assert row.startswith(
            b"A" + b" " * (width - 1) + b"B" + b" " * (width - 1) + b"\x80\xff"
        ), row
        keys("right+right")
        expect_cursor(width, 2)
        keys("hmp:sendkey shift-left 200")
        text, raw = expect_cursor(1, 2)
        attrs = raw[2 * 160 + 1 : 3 * 160 : 2]
        assert attrs[1:width] == bytes([0x17]) * (width - 1), attrs
        assert attrs[width] == 0x07, attrs
        keys("right")
        expect_cursor(width, 2)
        keys("down")
        expect_cursor(width, 3)
        keys("down")
        expect_cursor(2, 4)
        keys("down")
        expect_cursor(width, 5)
        keys("up+up+up")
        expect_cursor(width, 2)
        keys("hmp:sendkey shift-down 200")
        text, raw = expect_cursor(width, 3)
        first_attrs = raw[2 * 160 + 1 : 3 * 160 : 2]
        last_attrs = raw[3 * 160 + 1 : 4 * 160 : 2]
        assert first_attrs[width:] == bytes([0x17]) * (80 - width), first_attrs
        assert last_attrs[:width] == bytes([0x17]) * width, last_attrs
        assert last_attrs[width] == 0x07, last_attrs
    keys("esc")
    process.wait(timeout=15)
    assert process.returncode == 33, process.returncode
    assert run(["mtype", "-i", spec, "::SAMPLE.TXT"]).stdout == expected
    assert run(["mtype", "-i", spec, "::SAMPLE.BAK"]).stdout == (
        original if saved else b"PREVIOUS_BACKUP\r\n"
    )
    return {
        "completed": True,
        "exact_match": True,
        "backup_matches_expected": True,
        "tab_flow": kind,
    }
