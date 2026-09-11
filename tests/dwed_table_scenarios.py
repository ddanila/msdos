"""Exercise table navigation through byte-exact edits at the destination."""

import time

from screen_expect import read_screen_text, send_keys
from test_compat_bpb_qemu import run

ROW = b"\xb3abc\xb3def\xb3  "
LONG = b"\xb3" + b"r" * 253 + b"\xb3"
KINDS = (
    "previous-row",
    "next-row",
    "end-boundary",
    "empty-field",
    "last-row",
    "previous-border",
    "next-field",
)


def source(kind):
    rows = [ROW, ROW]
    if kind == "end-boundary":
        rows = [LONG]
    elif kind == "empty-field":
        rows = [b"\xb3\xb3abc\xb3def\xb3"]
    return b"DWED_MARKER\r\n" + b"\r\n".join(rows) + b"\r\n"


CASES = [
    ("table-" + kind + "-" + mode, mode, source(kind), False)
    for kind in KINDS
    for mode in ("low", "high")
]


def exercise(q, process, directory, spec, original, name):
    kind = name[len("table-") :].rsplit("-", 1)[0]

    def keys(value):
        send_keys(q, value)
        time.sleep(0.5 if value.endswith(" 200") else 0.25)

    def editor(label, dirty):
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            screen = read_screen_text(q, str(directory / "vram.bin"))
            (directory / (label + ".txt")).write_text(screen)
            if "File   Edit" in screen and ("*" in screen.splitlines()[-1]) == dirty:
                return
            time.sleep(0.2)
        raise AssertionError(screen)

    rows = original.split(b"\r\n")
    if kind == "previous-row":
        keys("down+down+home+right")
        keys("hmp:sendkey shift-tab 200")
        row, column = 1, 5
    elif kind == "next-row":
        keys("down+end+tab")
        row, column = 2, 1
    elif kind == "end-boundary":
        keys("down+end")
        keys("hmp:sendkey shift-tab 200")
        # A full line cannot grow; delete the destination byte before typing.
        keys("delete")
        rows[1] = rows[1][:1] + rows[1][2:]
        row, column = 1, 1
    elif kind == "previous-border":
        keys("down+home+right+right+right+right")
        keys("hmp:sendkey shift-tab 200")
        row, column = 1, 1
    elif kind == "next-field":
        keys("down+home+right+right+tab")
        row, column = 1, 5
    elif kind == "empty-field":
        keys("down+home+tab")
        row, column = 1, 2
    else:
        keys("down+down+end+tab")
        row, column = 2, len(ROW)
    keys("x")
    rows[row] = rows[row][:column] + b"x" + rows[row][column:]
    expected = b"\r\n".join(rows)
    editor("typed-at-destination", True)
    keys("hmp:sendkey ctrl-z")
    if kind == "end-boundary":
        keys("hmp:sendkey ctrl-z")
    editor("undone", False)
    keys("hmp:sendkey ctrl-shift-z 200")
    if kind == "end-boundary":
        keys("hmp:sendkey ctrl-shift-z 200")
    editor("redone", True)
    keys("f2")
    editor("saved", False)
    keys("esc")
    process.wait(timeout=15)
    assert process.returncode == 33
    actual = run(["mtype", "-i", spec, "::SAMPLE.TXT"]).stdout
    assert actual == expected, (actual, expected)
    assert run(["mtype", "-i", spec, "::SAMPLE.BAK"]).stdout == original
    return {
        "completed": True,
        "exact_match": True,
        "backup_matches_expected": True,
        "table_flow": kind,
    }
