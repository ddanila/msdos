"""Startup discovery rejects damaged input and retains read-handle ownership."""

import struct
import subprocess
import time
import zlib

from screen_expect import read_screen_text, send_keys
from test_compat_bpb_qemu import put, run

ORIGINAL = b"DWED_MARKER\r\nsecond line\r\n"
KINDS = (
    "bad-crc",
    "short-record",
    "extra-record",
    "bad-path",
    "bad-payload",
    "readonly",
    "alias",
    "format",
    "record-read",
    "payload-read",
    "early-eof",
    "record-close",
)
CASES = [
    ("recover-" + kind + "-" + mode, mode, ORIGINAL, False)
    for kind in KINDS
    for mode in ("low", "high")
]
FAULTS = {"record-read": 1, "payload-read": 2, "early-eof": 3, "record-close": 4}


def kind_of(name):
    return name[len("recover-") :].rsplit("-", 1)[0]


def payload_for(kind):
    if kind == "format":
        return b"zDWED_MARKER\t\x80\xff\nlast"
    return b"z" + ORIGINAL


def prepare(spec, name):
    if not name.startswith("recover-"):
        return
    kind = kind_of(name)
    payload = payload_for(kind)
    prefix = b"C:\\.\\" if kind == "alias" else b"C:\\"
    paths = [
        prefix + base
        for base in (b"SAMPLE.TXT", b"$ED0001.TMP", b"SAMPLE.BAK", b"$EB0000.TMP")
    ]
    if kind == "bad-path":
        paths[0] = b"C:\\SAMPLE.TXT\x00OTHER"
    raw = struct.pack("<8sHH", b"DWEDSAVE", 1, 1048)
    raw += b"".join(
        bytes([len(path)]) + path + bytes(255 - len(path)) for path in paths
    )
    raw += struct.pack("<II", len(payload), zlib.crc32(payload))
    raw += struct.pack("<I", zlib.crc32(raw))
    if kind == "bad-crc":
        raw = raw[:-1] + bytes([raw[-1] ^ 1])
    if kind == "short-record":
        raw = raw[:-1]
    if kind == "extra-record":
        raw += b"x"
    put(spec, "$ER0000.REC", raw)
    put(spec, "$ED0001.TMP", b"x" + payload[1:] if kind == "bad-payload" else payload)
    if kind == "readonly":
        for path in ("::$ER0000.REC", "::$ED0001.TMP"):
            run(["mattrib", "-i", spec, "+r", path])


def exercise(q, process, directory, spec, original, name):
    kind = kind_of(name)
    record = run(["mtype", "-i", spec, "::$ER0000.REC"]).stdout
    payload = run(["mtype", "-i", spec, "::$ED0001.TMP"]).stdout

    def keys(value):
        send_keys(q, value)
        time.sleep(0.25)

    def expect(needle, label):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            text = read_screen_text(q, str(directory / "vram.bin"))
            (directory / (label + ".txt")).write_text(text)
            if needle in text:
                return text
            time.sleep(0.2)
        raise AssertionError(text)

    expect("Interrupted save", "discovery")
    recovered = kind in ("readonly", "alias", "format") or kind in FAULTS
    if kind in ("bad-crc", "short-record", "extra-record", "bad-path"):
        expect("Error #1013", "invalid-record")
        keys("s")
    elif kind == "bad-payload":
        keys("r")
        expect("Error #1014", "invalid-payload")
        keys("s")
    elif kind in FAULTS:
        if kind in ("payload-read", "early-eof"):
            keys("r")
        expect("Error #1012" if kind == "early-eof" else "Error #5", "read-error")
        if kind == "record-close":
            keys("s")
            text = expect("Read cleanup", "retained-handle")
            assert "C:\\$ER0000.REC" in text and "K Keep" not in text, text
            keys("r")
            expect("Read cleanup", "failed-close-retry")
            keys("esc+esc")
            expect("Read cleanup", "exit-held-read")
            keys("esc")
            expect("DWED_MARKER", "cancelled-exit")
            keys("caps_lock+f2")
            expect("Read cleanup", "save-held-read")
            keys("r")
            text = expect("DWED_MARKER", "closed-read-retried-save")
            assert "*" not in text.splitlines()[-1], text
            keys("esc")
            recovered = False
        else:
            keys("caps_lock+r")
            expect("R Recover", "retry-record")
            keys("r")
    else:
        keys("r")
    if recovered:
        text = expect("Recovered SAMPLE.TXT", "recovered")
        assert "zDWED_MARKER" in text and "*" in text.splitlines()[-1], text
        if kind == "format":
            keys("f2")
            text = expect("zDWED_MARKER", "saved-format")
            assert "*" not in text.splitlines()[-1], text
            keys("esc")
        else:
            keys("esc")
            expect("Unsaved changes", "unsaved-recovery")
            keys("n")
    elif kind != "record-close":
        text = expect("DWED_MARKER", "original-preserved")
        assert "Recovered" not in text and "*" not in text.splitlines()[-1], text
        keys("esc")
    try:
        process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        text = read_screen_text(q, str(directory / "vram.bin"))
        (directory / "exit-timeout.txt").write_text(text)
        raise AssertionError(text) from None
    assert process.returncode == 33, process.returncode
    assert run(["mtype", "-i", spec, "::SAMPLE.TXT"]).stdout == (
        payload if kind == "format" else original
    )
    assert run(["mtype", "-i", spec, "::SAMPLE.BAK"]).stdout == (
        original if kind in ("format", "record-close") else b"PREVIOUS_BACKUP\r\n"
    )
    assert run(["mtype", "-i", spec, "::$ER0000.REC"]).stdout == record
    assert run(["mtype", "-i", spec, "::$ED0001.TMP"]).stdout == payload
    return {
        "completed": True,
        "exact_match": True,
        "backup_matches_expected": True,
        "recovery_flow": kind,
        "recovered": recovered,
    }
