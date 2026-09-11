"""Literal search and checked replacement through real editor commands."""

import re
import time

from screen_expect import read_screen_text, send_keys
from test_compat_bpb_qemu import run

ORIGINAL = b"DWED_MARKER\r\nxx XX xx\r\n last xx \r\n"
KINDS = (
    "find",
    "find-case",
    "find-next",
    "find-spaces",
    "find-cancel",
    "find-empty",
    "find-missing",
    "find-menu",
    "find-selection-limit",
    "replace-all",
    "replace-case",
    "replace-skip",
    "replace-stop",
    "replace-empty",
    "replace-spaces",
    "replace-self",
    "replace-overflow",
    "replace-boundary",
    "replace-capacity",
    "replace-menu",
    "replace-next",
    "replace-noop",
)


def source(kind):
    if kind == "find-selection-limit":
        return b"DWED_MARKER\r\n" + (b"x" * 80 + b"\r\n") * 2
    if kind in ("replace-overflow", "replace-boundary"):
        return (
            b"DWED_MARKER\r\nxx\r\n"
            + b"b" * (253 if kind.endswith("overflow") else 252)
            + b"xx\r\n"
        )
    if kind == "replace-capacity":
        return b"DWED_MARKER\r\n" + b"xx\r\n" * 1000
    return ORIGINAL


CASES = [
    ("search-" + kind + "-" + mode, mode, source(kind), False)
    for kind in KINDS
    for mode in ("low", "high")
]


def exercise(q, process, directory, spec, original, name):
    kind = name[len("search-") :].rsplit("-", 1)[0]

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

    expected = original
    if kind == "find-empty":
        keys("hmp:sendkey ctrl-k")
        editor("empty-repeat", False)
    else:
        if kind == "find-selection-limit":
            keys("down+home")
            keys("hmp:sendkey shift-end 200")
        replacing = kind.startswith("replace-")
        sensitive = kind in ("find-case", "replace-case", "replace-noop")
        if kind.endswith("-menu"):
            keys("hmp:sendkey alt-s")
            expect("Replace...", "search-menu")
            keys("r" if replacing else "f")
        elif kind == "replace-overflow":
            # F7 supplies the same two input fields in the historical build,
            # allowing a negative control for silent short-string truncation.
            keys("f7")
        else:
            keys(
                "hmp:sendkey ctrl-"
                + ("shift-" if sensitive else "")
                + ("r" if replacing else "f")
                + " 200"
            )
        expect("Search (case-sens)" if sensitive else "Search (case-insens)", "query")
        if kind == "find-selection-limit":
            keys("backspace+ret")
        elif kind == "find-case":
            keys("hmp:sendkey shift-x")
            keys("hmp:sendkey shift-x")
            keys("ret")
        elif kind == "find-spaces":
            keys("spc+l+a+s+t+spc+ret")
        elif kind == "find-missing":
            keys("z+z+z+ret")
        else:
            keys("x+x+ret")
        if replacing:
            expect("Replace with", "replacement")
            replacement = b"q"
            if kind == "replace-noop":
                replacement = b"xx"
            elif kind == "replace-empty":
                replacement = b""
            elif kind == "replace-spaces":
                replacement = b" q "
            elif kind == "replace-self":
                replacement = b"xxx"
            elif kind in ("replace-overflow", "replace-boundary"):
                replacement = b"qqq"
            for c in replacement.decode():
                keys("spc" if c == " " else c)
            keys("ret")
            expect("Replace it?", "first-match")
            if kind in ("replace-skip", "replace-next"):
                keys("n")
                expect("Replace it?", "skipped")
                keys("y")
                expect("Replace it?", "accepted-one")
                keys("esc")
                expected = original.replace(b"XX", b"q")
            elif kind == "replace-stop":
                keys("esc")
            else:
                if kind == "replace-overflow":
                    keys("y")
                    expect("Replace it?", "accepted-before-overflow")
                keys("a")
                if kind in ("replace-overflow", "replace-capacity"):
                    expect(
                        "#1006" if kind.endswith("overflow") else "#1004",
                        "replacement-refused",
                    )
                    keys("ret")
                else:
                    expect("Replaced ", "replacement-count")
                    keys("ret")
                    expected = re.sub(
                        b"xx",
                        lambda _: replacement,
                        original,
                        flags=0 if sensitive else re.IGNORECASE,
                    )
            editor("replaced", expected != original)
            if expected != original:
                keys("hmp:sendkey ctrl-z")
                editor("undo-clean", False)
                keys("hmp:sendkey ctrl-shift-z 200")
                editor("redo-dirty", True)
            if kind == "replace-next":
                keys("hmp:sendkey ctrl-k")
                editor("find-after-replacement", True)
                keys("hmp:sendkey ctrl-c")
                keys("hmp:sendkey ctrl-end")
                keys("hmp:sendkey ctrl-v")
                expected += b"xx"
        elif kind == "find-missing":
            expect("Substring not found", "not-found")
            keys("ret")
            editor("missing-clean", False)
        else:
            editor("found", False)
            if kind == "find-next":
                keys("hmp:sendkey ctrl-k")
                editor("next", False)
            if kind == "find-cancel":
                keys("hmp:sendkey ctrl-f")
                expect("Search (case-insens)", "cancel-query")
                keys("esc")
                editor("cancel-retains-selection", False)
            keys("hmp:sendkey ctrl-c")
            keys("hmp:sendkey ctrl-end")
            keys("hmp:sendkey ctrl-v")
            expected = original + (
                b"x" * 63
                if kind == "find-selection-limit"
                else b"XX"
                if kind in ("find-case", "find-next")
                else b" last "
                if kind == "find-spaces"
                else b"xx"
            )
    keys("f2")
    editor("saved", False)
    keys("esc")
    process.wait(timeout=15)
    assert process.returncode == 33
    assert run(["mtype", "-i", spec, "::SAMPLE.TXT"]).stdout == expected
    assert run(["mtype", "-i", spec, "::SAMPLE.BAK"]).stdout == original
    return {
        "completed": True,
        "exact_match": True,
        "backup_matches_expected": True,
        "search_flow": kind,
        "changed": expected != original,
    }
