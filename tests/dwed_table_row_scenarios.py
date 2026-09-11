"""Table continuation preserves bytes and alignment as one undoable edit."""

import time

from screen_expect import read_screen_text, send_keys
from test_compat_bpb_qemu import run

B = b"\xb3"
ROW = B + b"abc" + B + b"def" + B + b"  "
TABS = b"\t" + B + b"a\tbc" + B + b"z\t" + B + b"\t  "
KINDS = (
    "split",
    "double",
    "home",
    "tabs",
    "end",
    "full",
    "overflow",
    "border",
    "selection",
    "indent",
    "unindent",
)


def source(kind):
    row = ROW
    if kind == "double":
        row = ROW.replace(B, b"\xba")
    elif kind == "tabs":
        row = TABS
    elif kind == "full":
        row = B + b"r" * 253 + B
    elif kind == "overflow":
        row = B + b"\ta" + B + b"r" * 250 + B
    elif kind == "unindent":
        row = b"\t" + ROW
    return b"DWED_MARKER\r\n" + row + b"\r\n"


CASES = [
    ("table-row-" + kind + "-" + mode, mode, source(kind), False)
    for kind in KINDS
    for mode in ("low", "high")
]


def exercise(q, process, directory, spec, original, name):
    kind = name[len("table-row-") :].rsplit("-", 1)[0]

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

    keys("down+home")
    row = original.split(b"\r\n")[1]
    blank = B + b"   " + B + b"   " + B + b"  "
    if kind in ("split", "double"):
        keys("right+right+ret")
        rows = [
            B + b"a  " + B + b"def" + B + b"  ",
            B + b"bc " + B + b"   " + B + b"  ",
        ]
        if kind == "double":
            rows = [r.replace(B, b"\xba") for r in rows]
    elif kind == "home":
        keys("ret")
        rows = [row, blank]
    elif kind == "tabs":
        keys("right+right+right+right+ret")
        rows = [
            b"\t" + B + b"a\t  " + B + b"z\t" + B + b"\t  ",
            b"\t" + B + b"bc\t  " + B + b" \t" + B + b"\t  ",
        ]
    elif kind == "overflow":
        keys("right+right+ret")
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            screen = read_screen_text(q, str(directory / "vram.bin"))
            if "#1006:" in screen:
                (directory / "row-overflow.txt").write_text(screen)
                break
            time.sleep(0.2)
        else:
            raise AssertionError(screen)
        keys("ret")
        rows = [row]
    elif kind in ("end", "full"):
        keys("end+ret")
        rows = [row, B + b" " * 253 + B if kind == "full" else blank]
    elif kind == "border":
        keys("right+right+right+right+ret")
        rows = [row, blank]
    elif kind == "selection":
        keys("right")
        for _ in range(3):
            keys("hmp:sendkey shift-right 200")
        keys("ret")
        rows = [B, B + b"def" + B + b"  "]
    else:
        for _ in range(3):
            keys("hmp:sendkey shift-right 200")
        keys("tab" if kind == "indent" else "hmp:sendkey shift-tab 200")
        rows = [b" " * 8 + ROW if kind == "indent" else ROW]
    expected = b"DWED_MARKER\r\n" + b"\r\n".join(rows) + b"\r\n"
    editor("changed", kind != "overflow")
    keys("hmp:sendkey ctrl-z")
    editor("undone", False)
    keys("hmp:sendkey ctrl-shift-z 200")
    editor("redone", kind != "overflow")
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
        "table_row_flow": kind,
    }
