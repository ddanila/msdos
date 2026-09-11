"""Startup discovery rejects damaged input and retains read-handle ownership."""

import struct
import subprocess
import time
import zlib

from screen_expect import read_screen_text, send_keys
from test_compat_bpb_qemu import put, run

ORIGINAL = b"DWED_MARKER\r\nsecond line\r\n"
KINDS = (
    "edited-cleanup",
    "edited-read-failure",
    "edited-saved-mismatch",
    "edited-save-failure",
    "edited-keep",
    "edited-saveas",
    "edited-saveas-alias",
    "edited-readonly-record",
    "edited-readonly-temp",
    "edited-legacy-backup",
    "cleanup",
    "cleanup-v2-backup",
    "cleanup-v2-changed-backup",
    "cleanup-v2-readonly-backup",
    "cleanup-large",
    "cleanup-cancel",
    "cleanup-missing-temp",
    "cleanup-changed-dest",
    "cleanup-changed-temp",
    "cleanup-retained-backup",
    "cleanup-readonly-record",
    "cleanup-readonly-temp",
    "cleanup-read-failure",
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
FAULTS = {
    "edited-read-failure": 1,
    "edited-saved-mismatch": 5,
    "cleanup-read-failure": 1,
    "record-read": 1,
    "payload-read": 2,
    "early-eof": 3,
    "record-close": 4,
}


def kind_of(name):
    return name[len("recover-") :].rsplit("-", 1)[0]


def payload_for(kind):
    if kind == "cleanup-large":
        return b"z" + ORIGINAL + b"long payload line\r\n" * 200
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
    v2 = kind.startswith("cleanup-v2-") or (
        kind.startswith("edited-") and kind != "edited-legacy-backup"
    )
    raw = struct.pack("<8sHH", b"DWEDSAVE", 2 if v2 else 1, 1058 if v2 else 1048)
    raw += b"".join(
        bytes([len(path)]) + path + bytes(255 - len(path)) for path in paths
    )
    raw += struct.pack("<II", len(payload), zlib.crc32(payload))
    if v2:
        older = b"VERIFIED OLDER BACKUP\r\n"
        raw += struct.pack("<IIH", len(older), zlib.crc32(older), 1)
        put(
            spec,
            "$EB0000.TMP",
            b"CHANGED OLDER BACKUP\r\n"
            if kind == "cleanup-v2-changed-backup"
            else older,
        )
    raw += struct.pack("<I", zlib.crc32(raw))
    if kind == "bad-crc":
        raw = raw[:-1] + bytes([raw[-1] ^ 1])
    if kind == "short-record":
        raw = raw[:-1]
    if kind == "extra-record":
        raw += b"x"
    put(spec, "$ER0000.REC", raw)
    put(spec, "$ED0001.TMP", b"x" + payload[1:] if kind == "bad-payload" else payload)
    if kind.startswith("cleanup"):
        if kind != "cleanup-changed-dest":
            put(spec, "SAMPLE.TXT", payload)
        if kind == "cleanup-changed-temp":
            put(spec, "$ED0001.TMP", b"changed temporary\r\n")
        if kind == "cleanup-retained-backup":
            put(spec, "$EB0000.TMP", b"UNVERIFIED OLDER BACKUP\r\n")
        if kind == "cleanup-missing-temp":
            run(["mdel", "-i", spec, "::$ED0001.TMP"])
        if kind == "cleanup-readonly-record":
            run(["mattrib", "-i", spec, "+r", "::$ER0000.REC"])
        if kind == "cleanup-readonly-temp":
            run(["mattrib", "-i", spec, "+r", "::$ED0001.TMP"])
        if kind == "cleanup-v2-readonly-backup":
            run(["mattrib", "-i", spec, "+r", "::$EB0000.TMP"])
    if kind == "edited-save-failure":
        run(["mattrib", "-i", spec, "+r", "::SAMPLE.TXT"])
    if kind == "edited-legacy-backup":
        put(spec, "$EB0000.TMP", b"UNVERIFIED OLDER BACKUP\r\n")
    if kind in ("edited-readonly-record", "edited-readonly-temp"):
        path = "$ER0000.REC" if kind.endswith("record") else "$ED0001.TMP"
        run(["mattrib", "-i", spec, "+r", "::" + path])
    if kind == "readonly":
        for path in ("::$ER0000.REC", "::$ED0001.TMP"):
            run(["mattrib", "-i", spec, "+r", path])


def exercise(q, process, directory, spec, original, name):
    kind = kind_of(name)
    if kind.startswith("edited-"):
        return exercise_edited(q, process, directory, spec, original, kind)
    if kind.startswith("cleanup"):
        return exercise_cleanup(q, process, directory, spec, original, kind)
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
            expect("Saved recovered document", "saved-cleanup")
            keys("esc")
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


def exercise_cleanup(q, process, directory, spec, original, kind):
    def read(name):
        return run(["mtype", "-i", spec, "::" + name]).stdout

    def keys(value):
        send_keys(q, value)
        time.sleep(0.25)

    def expect(needle, label):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            screen = read_screen_text(q, str(directory / "vram.bin"))
            (directory / (label + ".txt")).write_text(screen)
            if needle in screen:
                return screen
            time.sleep(0.2)
        raise AssertionError(screen)

    record = read("$ER0000.REC")
    destination = read("SAMPLE.TXT")
    backup = read("SAMPLE.BAK")
    expect("Interrupted save", "discovery")
    if kind == "cleanup-read-failure":
        expect("Error #5", "initial-read-failure")
        keys("caps_lock+r")
        expect("R Recover", "read-retried")
    keys("c")
    blocked = kind in (
        "cleanup-changed-dest",
        "cleanup-changed-temp",
        "cleanup-v2-changed-backup",
        "cleanup-retained-backup",
    )
    if blocked:
        expect(
            "Error #1015" if kind == "cleanup-retained-backup" else "Error #1014",
            "cleanup-blocked",
        )
        keys("s")
    else:
        text = expect("D Remove listed files", "cleanup-confirm")
        assert "$ER0000.REC" in text and "$ED0001.TMP" in text, text
        if kind == "cleanup-cancel":
            keys("esc")
            expect("C Check cleanup", "cleanup-cancelled")
            keys("s")
        else:
            keys("caps_lock+d" if kind == "cleanup-read-failure" else "d")
            if kind in (
                "cleanup-readonly-record",
                "cleanup-v2-readonly-backup",
                "cleanup-readonly-temp",
                "cleanup-read-failure",
            ):
                expect("Cleanup unavailable. Error #5", "cleanup-delete-failed")
                keys("caps_lock+c" if kind == "cleanup-read-failure" else "c")
                expect("D Remove listed files", "cleanup-retry")
                keys("esc+s")
    expect("DWED_MARKER", "editor-return")
    keys("esc")
    process.wait(timeout=15)
    assert process.returncode == 33
    assert read("SAMPLE.TXT") == destination
    assert read("SAMPLE.BAK") == backup
    assert read("$ED0000.TMP") == b"OTHER_EDITOR_SAVE\r\n"
    listing = run(["mdir", "-b", "-i", spec, "::"]).stdout.upper()
    removed = kind in (
        "cleanup",
        "cleanup-large",
        "cleanup-missing-temp",
        "cleanup-v2-backup",
    )
    if removed:
        assert b"$ER0000.REC" not in listing and b"$ED0001.TMP" not in listing, listing
    else:
        assert read("$ER0000.REC") == record
        if kind in ("cleanup-readonly-record", "cleanup-v2-readonly-backup"):
            assert b"$ED0001.TMP" not in listing, listing
        else:
            assert read("$ED0001.TMP") == (
                b"changed temporary\r\n"
                if kind == "cleanup-changed-temp"
                else payload_for(kind)
            )
    if kind == "cleanup-retained-backup":
        assert read("$EB0000.TMP") == b"UNVERIFIED OLDER BACKUP\r\n"
    if kind == "cleanup-v2-backup":
        assert b"$EB0000.TMP" not in listing, listing
    if kind in ("cleanup-v2-changed-backup", "cleanup-v2-readonly-backup"):
        assert read("$EB0000.TMP") == (
            b"CHANGED OLDER BACKUP\r\n"
            if kind == "cleanup-v2-changed-backup"
            else b"VERIFIED OLDER BACKUP\r\n"
        )
    return {
        "completed": True,
        "exact_match": True,
        "backup_matches_expected": True,
        "recovery_flow": kind,
        "resolved": removed,
    }


def exercise_edited(q, process, directory, spec, original, kind):
    def read(name):
        return run(["mtype", "-i", spec, "::" + name]).stdout

    def keys(value):
        send_keys(q, value)
        time.sleep(0.25)

    def expect(needle, label):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            screen = read_screen_text(q, str(directory / "vram.bin"))
            (directory / (label + ".txt")).write_text(screen)
            if needle in screen:
                return screen
            time.sleep(0.2)
        raise AssertionError(screen)

    record = read("$ER0000.REC")
    older = read("$EB0000.TMP")
    expect("Interrupted save", "discovery")
    if kind == "edited-read-failure":
        expect("Error #5", "initial-read-failure")
        keys("caps_lock+r")
        expect("R Recover", "read-retried")
    keys("r")
    expect("Recovered SAMPLE.TXT", "recovered")
    if kind != "edited-saveas-alias":
        keys("hmp:sendkey shift-x" if kind == "edited-read-failure" else "x")
        expect("xzDWED_MARKER", "further-edited")
    if kind in ("edited-saveas", "edited-saveas-alias"):
        keys("hmp:sendkey shift-f2")
        expect("Save file to", "save-as")
        keys("hmp:sendkey ctrl-a")
        if kind == "edited-saveas-alias":
            # Save the unchanged recovered payload over an aliased cleanup target.
            # Matching CRCs must not permit deleting the newly saved document.
            keys("dot+dot+backslash")
            keys("hmp:sendkey shift-4")
            keys("e+d+0+0+0+1+dot+t+m+p+ret")
            expect("Replace file", "replace-recovery-temporary")
            keys("y")
        else:
            keys("n+e+w+dot+t+x+t+ret")
    else:
        keys("f2")
    if kind == "edited-save-failure":
        screen = expect("Error", "save-failed")
        assert "Saved recovered document" not in screen, screen
        keys("ret")
        screen = expect("Recovered SAMPLE.TXT", "still-unsaved")
        assert "*" in screen.splitlines()[-1], screen
        keys("esc")
        expect("Unsaved changes", "unsaved-exit")
        keys("n")
        process.wait(timeout=15)
        assert process.returncode == 33
        assert read("SAMPLE.TXT") == original
        assert read("SAMPLE.BAK") == b"PREVIOUS_BACKUP\r\n"
        assert read("$ER0000.REC") == record
        assert read("$ED0001.TMP") == payload_for(kind)
        assert read("$EB0000.TMP") == older
        return {
            "completed": True,
            "exact_match": True,
            "backup_matches_expected": True,
            "recovery_flow": kind,
            "resolved": False,
        }
    expect("Saved recovered document", "saved-cleanup")
    if kind in ("edited-legacy-backup", "edited-saveas-alias"):
        expect(
            "Error #1014" if kind == "edited-saveas-alias" else "Error #1015",
            "cleanup-blocked",
        )
        keys("esc")
    else:
        screen = expect("D Remove listed files", "confirm")
        assert "$ER0000.REC" in screen and "$EB0000.TMP" in screen, screen
        if kind == "edited-keep":
            keys("esc")
            expect("xzDWED_MARKER", "kept")
            # Association survives cancellation and further edits in the same session.
            keys("y+f2")
            expect("D Remove listed files", "second-save-confirm")
            keys("esc")
        else:
            keys(
                "caps_lock+d"
                if kind in ("edited-read-failure", "edited-saved-mismatch")
                else "d"
            )
            if kind in ("edited-read-failure", "edited-saved-mismatch"):
                expect(
                    "Error #1014" if kind == "edited-saved-mismatch" else "Error #5",
                    "revalidation-failed",
                )
                keys("caps_lock+r")
                expect("D Remove listed files", "revalidated")
                keys("esc")
            if kind.startswith("edited-readonly-"):
                expect("Error #5", "deletion-failed")
                keys("r")
                expect("D Remove listed files", "retry-checked")
                keys("esc")
    screen = expect("zDWED_MARKER", "saved-editor")
    assert "*" not in screen.splitlines()[-1], screen
    keys("esc")
    process.wait(timeout=15)
    assert process.returncode == 33
    expected = (
        b"xy"
        if kind == "edited-keep"
        else b""
        if kind == "edited-saveas-alias"
        else b"x"
    ) + payload_for(kind)
    saved_path = (
        "DWED/NEW.TXT"
        if kind == "edited-saveas"
        else "$ED0001.TMP"
        if kind == "edited-saveas-alias"
        else "SAMPLE.TXT"
    )
    assert read(saved_path) == expected
    assert read("SAMPLE.BAK") == (
        b"PREVIOUS_BACKUP\r\n"
        if kind in ("edited-saveas", "edited-saveas-alias")
        else b"x" + payload_for(kind)
        if kind == "edited-keep"
        else original
    )
    if kind in ("edited-saveas", "edited-saveas-alias"):
        assert read("SAMPLE.TXT") == original
    if kind == "edited-saveas-alias":
        assert read("$ED0001.BAK") == payload_for(kind)
    assert read("$ED0000.TMP") == b"OTHER_EDITOR_SAVE\r\n"
    listing = run(["mdir", "-b", "-i", spec, "::"]).stdout.upper()
    removed = kind in ("edited-cleanup", "edited-saveas")
    if removed:
        for path in (b"$ER0000.REC", b"$ED0001.TMP", b"$EB0000.TMP"):
            assert path not in listing, listing
    else:
        assert read("$ER0000.REC") == record
        if kind == "edited-readonly-record":
            assert b"$ED0001.TMP" not in listing and b"$EB0000.TMP" not in listing
        else:
            assert read("$ED0001.TMP") == payload_for(kind)
            assert read("$EB0000.TMP") == older
    return {
        "completed": True,
        "exact_match": True,
        "backup_matches_expected": True,
        "recovery_flow": kind,
        "resolved": removed,
    }
