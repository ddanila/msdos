"""Checked addon insertion, calculator operations and document undo ownership."""

import time

from screen_expect import read_screen_text, send_keys
from test_compat_bpb_qemu import run

ORIGINAL = b"DWED_MARKER\r\nsecond line\r\n"
KINDS = (
    "ascii-byte",
    "ascii-tab",
    "ascii-hex",
    "ascii-control",
    "ascii-overflow",
    "ascii-selection",
    "ascii-cancel",
    "ascii-menu",
    "calc-value",
    "calc-hex",
    "calc-overflow",
    "calc-boundary",
    "calc-selection",
    "calc-negative",
    "calc-divzero",
    "calc-div-min",
    "calc-mod-min",
    "calc-add-wrap",
    "calc-binary",
    "calc-bitwise",
)


def source(kind):
    if kind in ("ascii-overflow", "calc-overflow", "calc-boundary", "calc-selection"):
        return (
            b"DWED_MARKER\r\n"
            + b"r" * (253 if kind == "calc-boundary" else 254)
            + b"\r\n"
        )
    return ORIGINAL


CASES = [
    ("addon-" + kind + "-" + mode, mode, source(kind), False)
    for kind in KINDS
    for mode in ("low", "high")
]
CASES += [
    ("addon-ascii-mono-low", "low", ORIGINAL, False),
    ("addon-calc-mono-low", "low", ORIGINAL, False),
]


def exercise(q, process, directory, spec, original, name):
    kind = name[len("addon-") :].rsplit("-", 1)[0]

    def keys(value):
        send_keys(q, value)
        time.sleep(0.5 if value.endswith(" 200") else 0.25)

    def expect(needle, label):
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            screen = read_screen_text(q, str(directory / "vram.bin"))
            (directory / (label + ".txt")).write_text(screen)
            if needle in screen:
                return screen
            time.sleep(0.2)
        raise AssertionError(screen)

    def editor(label, dirty):
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            screen = read_screen_text(q, str(directory / "vram.bin"))
            (directory / (label + ".txt")).write_text(screen)
            if "File   Edit" in screen and ("*" in screen.splitlines()[-1]) == dirty:
                return screen
            time.sleep(0.2)
        raise AssertionError(screen)

    def shift_enter():
        keys("hmp:sendkey shift-ret 200")

    expected = original
    attributes = None
    if kind in ("ascii-overflow", "calc-overflow", "calc-boundary", "calc-selection"):
        keys("down+end")
        if kind == "calc-selection":
            keys("hmp:sendkey shift-left 200")
    elif kind in ("ascii-selection", "ascii-cancel"):
        keys("hmp:sendkey shift-right 200")
        keys("hmp:sendkey shift-right 200")
    if kind.startswith("ascii-"):
        if kind == "ascii-menu":
            keys("f12")
            expect("ASCII-Table", "addons-menu")
            keys("ret")
        else:
            keys("hmp:sendkey ctrl-alt-a 200")
        expect("Enter symbol", "ascii-picker")
        if kind == "ascii-cancel":
            keys("esc")
            editor("cancelled", False)
            keys("hmp:sendkey ctrl-c")
            keys("hmp:sendkey ctrl-end")
            keys("hmp:sendkey ctrl-v")
            expected = original + b"DW"
        else:
            code = (
                "01"
                if kind == "ascii-control"
                else "09"
                if kind == "ascii-tab"
                else "80"
            )
            keys("+".join(code))
            expect("Hex: " + code, "chosen-byte")
            if kind == "ascii-mono":
                # Selected cell padding versus an ordinary cell's padding.
                path = directory / "ascii-attributes.bin"
                q.human_cmd(
                    f'pmemsave {0xB0000 + ((4 + 8) * 80 + 16) * 2 + 1} 7 "{path}"'
                )
                data = path.read_bytes()
                attributes = [data[0], data[6]]
                assert attributes[0] != attributes[1], attributes
            if kind in ("ascii-hex", "ascii-overflow"):
                shift_enter()
            else:
                keys("ret")
            if kind in ("ascii-control", "ascii-overflow"):
                expect(
                    "#1007" if kind == "ascii-control" else "#1006", "insertion-refused"
                )
                keys("ret")
                expect("Enter symbol", "picker-retained")
                keys("esc")
            elif kind == "ascii-selection":
                expected = b"\x80" + original[2:]
            else:
                expected = (
                    b"80"
                    if kind == "ascii-hex"
                    else b"\t"
                    if kind == "ascii-tab"
                    else b"\x80"
                ) + original
    else:
        keys("hmp:sendkey ctrl-alt-c 200")
        expect("Enter value", "calculator")
        if kind == "calc-mono":
            path = directory / "calculator-attributes.bin"
            q.human_cmd(f'pmemsave {0xB0000 + (8 * 80 + 20) * 2 + 1} 11 "{path}"')
            data = path.read_bytes()
            attributes = [data[0], data[10]]
            assert attributes[0] != attributes[1], attributes
        if kind == "calc-add-wrap":
            keys("tab+7+f+f+f+f+f+f+f")
            keys("hmp:sendkey shift-equal 200")
            keys("1+ret")
            value = b"80000000"
        elif kind == "calc-binary":
            keys("tab+tab+1+0+1+backspace")
            value = b"0" * 30 + b"10"
        elif kind == "calc-bitwise":
            keys("9")
            keys("hmp:sendkey shift-7 200")
            keys("3+ret")
            keys("hmp:sendkey shift-backslash 200")
            keys("4+ret")
            keys("hmp:sendkey shift-6 200")
            keys("1+ret")
            keys("hmp:sendkey shift-1 200")
            keys("n")
            value = b"5"
        elif kind == "calc-hex":
            keys("tab+1+2+3+4+backspace")
            expect("00000123", "hex-digit-removed")
            value = b"00000123"
        elif kind in ("calc-div-min", "calc-mod-min"):
            keys("tab+8+0+0+0+0+0+0+0")
            keys("slash" if kind == "calc-div-min" else "m")
            keys("f+f+f+f+f+f+f+f+ret")
            value = b"80000000" if kind == "calc-div-min" else b"00000000"
            expect(value.decode(), "signed-edge-result")
        elif kind == "calc-divzero":
            keys("1+2+slash+0+ret")
            expect("#200", "division-refused")
            keys("ret")
            expect("Enter value", "calculator-retained")
            keys("spc+3+ret")
            value = b"4"
        elif kind == "calc-negative":
            keys("1+2+n")
            value = b"-12"
        else:
            keys("1+2")
            keys("hmp:sendkey shift-equal 200")
            keys("3+4+ret")
            value = b"46"
        shift_enter()
        if kind == "calc-overflow":
            expect("#1006", "value-refused")
            keys("ret")
            expect("Enter value", "calculator-retained")
            keys("esc")
        elif kind == "calc-selection":
            expected = original[:-3] + value + b"\r\n"
        elif kind == "calc-boundary":
            expected = original[:-2] + value + b"\r\n"
        else:
            expected = value + original
    editor("result", expected != original)
    if expected != original:
        keys("hmp:sendkey ctrl-z")
        editor("undone", False)
        keys("hmp:sendkey ctrl-shift-z 200")
        editor("redone", True)
    keys("f2")
    editor("saved", False)
    reopened = kind in ("ascii-byte", "ascii-tab")
    if reopened:
        keys("f3")
        expect("Load file", "reopen-input")
        keys("dot+dot+backslash+s+a+m+p+l+e+dot+t+x+t+ret")
        editor("reopened", False)
    keys("esc")
    process.wait(timeout=15)
    assert process.returncode == 33
    assert run(["mtype", "-i", spec, "::SAMPLE.TXT"]).stdout == expected
    assert run(["mtype", "-i", spec, "::SAMPLE.BAK"]).stdout == original
    return {
        "completed": True,
        "exact_match": True,
        "backup_matches_expected": True,
        "addon_flow": kind,
        "addon_attributes": attributes,
        "reopened": reopened,
    }
