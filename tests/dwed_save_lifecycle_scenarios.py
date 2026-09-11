"""Persistent DOS failures exercise recovery ownership across editor actions."""

import struct
import subprocess
import time

from screen_expect import read_screen_text, send_keys
from test_compat_bpb_qemu import run

ORIGINAL = b"DWED_MARKER\r\nsecond line\r\n"
FAULTS = {
    "save-error-pending-" + kind + "-" + mode: fault
    for kind, fault in (
        ("close", 3),
        ("rollback", 4),
        ("cleanup", 5),
        ("keep", 4),
        ("jclose", 6),
        ("backup-close", 7),
    )
    for mode in ("low", "high")
}
FAULTS["save-error-pending-close-mono-low"] = 3
CASES = [(name, name.rsplit("-", 1)[1], ORIGINAL, False) for name in FAULTS]


def exercise(q, process, directory, spec, original, name):
    pointer = run(["mtype", "-i", spec, "::SFAULT.PTR"]).stdout
    assert len(pointer) == 8 and pointer[:4] == b"DWSF", pointer
    offset, segment = struct.unpack("<HH", pointer[4:])

    def telemetry():
        target = directory / "fault.bin"
        q.human_cmd(f'pmemsave {segment * 16 + offset} 10 "{target}"')
        return struct.unpack("<HHHHH", target.read_bytes())

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

    def editor(dirty, label):
        text = expect("zDWED_MARKER", label)
        assert ("*" in text.splitlines()[-1]) == dirty, text

    def contents(path):
        return run(["mtype", "-i", spec, "::" + path]).stdout

    cleanup = "-cleanup-" in name
    journal_close = "-jclose-" in name
    backup_close = "-backup-close-" in name
    close = "-close-" in name or journal_close
    keep = "-keep-" in name
    title = "Saved; cleanup pending" if cleanup else "Save recovery"
    keys("home+z+f2")
    if not cleanup:
        expect("Error", "primary-error")
        keys("ret")
    text = expect(title, "retained-files")
    assert "C:\\SAMPLE.TXT" in text, text
    assert "#5" in text, text
    if close:
        assert (
            "Backup verification handle is still open."
            if backup_close
            else "Recovery record is still open."
            if journal_close
            else "Temporary file is still open."
        ) in text, text
        if journal_close:
            assert "C:\\$ER0000.REC" in text, text
        assert "C:\\$ED0001.TMP" in text, text
    else:
        assert "C:\\$EB0000.TMP" in text, text
    first = telemetry()
    assert first[0] == 1 and first[3] == 1 and first[4] > 0, first
    keys("ret")
    editor(not cleanup, "returned-editor")

    if close:
        keys("hmp:sendkey alt-f")
        keys("n")
        text = expect("File", "another-document")
        assert "zDWED_MARKER" not in text, text
        keys("f2")
        expect(title, "other-document-save-blocked")
        assert telemetry()[3] == 1, telemetry()
        keys("esc")
        keys("hmp:sendkey alt-f4")
        editor(True, "closed-other-document")

    if keep:
        keys("esc")
        expect("Unsaved changes", "keep-discard")
        keys("n")
        expect(title, "keep-recovery")
        keys("k")
    elif cleanup:
        assert contents("SAMPLE.TXT") == b"z" + original
        keys("f5")
        expect(title, "external-command-transaction")
        keys("esc")
        editor(False, "cancelled-external-command")
        assert process.poll() is None
        keys("esc")
        expect(title, "exit-recovery")
        keys("k")
    else:
        keys("f2")
        expect(title, "next-save-blocked")
        assert telemetry()[3] == 1, telemetry()
        keys("r")
        expect(title, "retry-still-failing")
        assert telemetry()[4] > first[4] and telemetry()[3] == 1, telemetry()
        keys("esc+esc")
        expect("Unsaved changes", "exit-discard")
        keys("n")
        text = expect(title, "exit-transaction")
        if close:
            assert "K Keep files and leave" not in text, text
            keys("k")
            expect(title, "open-handle-cannot-leave")
            assert process.poll() is None
        keys("esc")
        editor(True, "cancelled-exit")
        keys("hmp:sendkey alt-f4")
        expect("Unsaved changes", "close-last-document")
        keys("n")
        expect(title, "close-last-transaction")
        keys("esc")
        editor(True, "cancelled-close")
        keys("caps_lock+f2")
        expect(title, "recovery-after-release")
        keys("r")
        editor(False, "retry-save-complete")
        assert telemetry()[3] == 2, telemetry()
        keys("esc")

    process.wait(timeout=15)
    assert process.returncode == 33, process.returncode
    if keep:
        missing = subprocess.run(
            ["mtype", "-i", spec, "::SAMPLE.TXT"], capture_output=True, check=False
        )
        assert missing.returncode != 0 and b"not found" in missing.stderr.lower()
        assert contents("$ED0001.TMP") == b"z" + original
    else:
        assert contents("SAMPLE.TXT") == b"z" + original
    assert contents("SAMPLE.BAK") == original
    listing = run(["mdir", "-b", "-i", spec, "::"]).stdout.upper()
    if not keep:
        assert b"$ED0001.TMP" not in listing, listing
    if cleanup or keep:
        assert contents("$EB0000.TMP") == b"PREVIOUS_BACKUP\r\n"
    else:
        assert b"$EB" not in listing, listing
    assert contents("$ED0000.TMP") == b"OTHER_EDITOR_SAVE\r\n"
    return {
        "completed": True,
        "exact_match": True,
        "backup_matches_expected": True,
        "lifecycle_flow": name,
        "initial_fault": list(first),
        "kept_previous_backup": cleanup or keep,
        "kept_unpublished_payload": keep,
    }
