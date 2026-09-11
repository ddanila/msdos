"""Injected DOS failures through actual Save, Cancel, Retry and Discard flows."""

import struct
import time

from screen_expect import read_screen_text, send_keys
from test_compat_bpb_qemu import run

ORIGINAL = b"DWED_MARKER\r\nsecond line\r\n"
CASES = [
    ("save-error-" + kind + "-" + mode, mode, ORIGINAL, False)
    for kind in ("close", "rename")
    for mode in ("low", "high")
]


def exercise(q, process, directory, spec, original, name):
    pointer = run(["mtype", "-i", spec, "::SFAULT.PTR"]).stdout
    assert len(pointer) == 8 and pointer[:4] == b"DWSF", pointer
    offset, segment = struct.unpack("<HH", pointer[4:])

    def keys(value):
        send_keys(q, value)
        time.sleep(0.25)

    def expect(needle, label):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            text = read_screen_text(q, str(directory / "vram.bin"))
            (directory / (label + ".txt")).write_text(text)
            if needle in text:
                return text
            time.sleep(0.2)
        raise AssertionError(text)

    keys("home+z+f2")
    expect("Error", "failed-save")
    q.human_cmd(f'pmemsave {segment * 16 + offset} 6 "{directory / "fault.bin"}"')
    injected, renames, handle = struct.unpack(
        "<HHH", (directory / "fault.bin").read_bytes()
    )
    assert injected == 1 and handle != 0xFFFF, (injected, renames, handle)
    keys("ret")
    text = expect("zDWED_MARKER", "retained-buffer")
    assert "*" in text.splitlines()[-1], text
    keys("esc")
    expect("Unsaved changes", "exit-after-failure")
    keys("esc")
    expect("zDWED_MARKER", "cancelled-exit")
    if "-close-" in name:
        keys("f2")
        text = expect("zDWED_MARKER", "retried-save")
        assert "*" not in text.splitlines()[-1], text
        keys("esc")
        expected, backup = b"z" + original, original
    else:
        keys("esc")
        expect("Unsaved changes", "discard-prompt")
        keys("n")
        expected, backup = original, b"PREVIOUS_BACKUP\r\n"
    process.wait(timeout=15)
    assert process.returncode == 33, process.returncode
    assert run(["mtype", "-i", spec, "::SAMPLE.TXT"]).stdout == expected
    assert run(["mtype", "-i", spec, "::SAMPLE.BAK"]).stdout == backup
    listing = run(["mdir", "-b", "-i", spec, "::"]).stdout.upper()
    assert b"$EB" not in listing and b"$ED0001.TMP" not in listing, listing
    assert (
        run(["mtype", "-i", spec, "::$ED0000.TMP"]).stdout == b"OTHER_EDITOR_SAVE\r\n"
    )
    return {
        "completed": True,
        "exact_match": True,
        "backup_matches_expected": True,
        "fault_injected": injected,
        "rename_calls_at_failure": renames,
    }
