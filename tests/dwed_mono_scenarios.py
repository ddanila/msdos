"""BIOS mode 7 editor interaction through monochrome video memory."""

import time

from screen_expect import read_screen_text, send_keys
from test_compat_bpb_qemu import run

ORIGINAL = b"DWED_MARKER\r\nA\tB\r\n"
CASES = [("mono-edit-flow-" + mode, mode, ORIGINAL, False) for mode in ("low", "high")]
CASES += [("mono-edit-rows-low", "low", ORIGINAL, False)]


def exercise(q, process, directory, spec, original, name):
    def keys(value):
        send_keys(q, value)
        time.sleep(0.5 if value.endswith(" 200") else 0.25)

    def capture(label):
        text = read_screen_text(q, str(directory / "vram.bin"))
        (directory / (label + ".txt")).write_text(text)
        raw = (directory / "vram.bin").read_bytes()
        assert set(raw[1::2]) <= {0x07, 0x0F, 0x70}, set(raw[1::2])
        return text, raw

    def expect(needle, label):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            text, raw = capture(label)
            if needle in text:
                return text, raw
            time.sleep(0.2)
        raise AssertionError(text)

    text, raw = capture("initial")
    assert text.startswith(" File "), text
    assert raw[160:180:2] == b"DWED_MARKE", text
    assert raw[320:338:2] == b"A       B", text
    keys("hmp:sendkey alt-e")
    text, raw = expect("- Undo", "disabled")
    assert "- Redo" in text and "- Paste" in text, text
    keys("ret")
    expect("- Undo", "disabled-enter")
    keys("esc")
    keys("home+right")
    keys("hmp:sendkey shift-right 200")
    text, raw = capture("selection")
    assert raw[(80 + 1) * 2 + 1] == 0x70, text
    keys("hmp:sendkey alt-e")
    text, raw = expect("Copy", "selection-menu")
    assert "- Copy" not in text, text
    keys("c")
    keys("end")
    keys("hmp:sendkey ctrl-v")
    expect("DWED_MARKERW", "pasted")
    keys("hmp:sendkey ctrl-z")
    text, raw = capture("undone")
    assert "DWED_MARKERW" not in text, text
    keys("hmp:sendkey alt-e")
    keys("r")
    expect("DWED_MARKERW", "redone")
    keys("hmp:sendkey alt-f")
    keys("s")
    capture("saved")
    keys("hmp:sendkey alt-h")
    keys("a")
    expect("MS-DOS EDIT project", "about")
    keys("esc")
    keys("esc")
    process.wait(timeout=15)
    assert process.returncode == 33, process.returncode
    assert run(["mtype", "-i", spec, "::SAMPLE.TXT"]).stdout == original.replace(
        b"DWED_MARKER", b"DWED_MARKERW"
    )
    assert run(["mtype", "-i", spec, "::SAMPLE.BAK"]).stdout == original
    return {
        "completed": True,
        "exact_match": True,
        "backup_matches_expected": True,
        "display_flow": "mode7-missing-rows" if "rows" in name else "mode7",
    }
