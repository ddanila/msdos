"""Stop after replacement operations, then reboot DOS to inspect recovery data."""

import hashlib
import struct
import subprocess
import time
import zlib

from screen_expect import QMPConnection, read_screen_text, send_keys
from test_compat_bpb_qemu import put, run

ORIGINAL = b"DWED_MARKER\r\nsecond line\r\n"
CASES = [
    (f"save-cut-{stage}-{mode}", mode, ORIGINAL, False)
    for stage in range(5)
    for mode in ("low", "high")
]


def decode_record(raw):
    assert len(raw) == 8 + 4 + 4 * 256 + 3 * 4, len(raw)
    assert raw[:8] == b"DWEDSAVE"
    version, size = struct.unpack_from("<HH", raw, 8)
    assert version == 1 and size == len(raw), (version, size)
    count, checksum, record_checksum = struct.unpack_from("<III", raw, len(raw) - 12)
    assert zlib.crc32(raw[:-4]) == record_checksum
    paths = [raw[pos + 1 : pos + 1 + raw[pos]] for pos in range(12, 12 + 4 * 256, 256)]
    return paths, count, checksum


def exercise(q, process, directory, spec, original, name, argv, floppy):
    stage = int(name.split("-")[2])
    send_keys(q, "home+z+f2")
    process.wait(timeout=20)
    assert process.returncode == 65, process.returncode
    raw = run(["mtype", "-i", spec, "::$ER0000.REC"]).stdout
    (directory / "recovery-record.bin").write_bytes(raw)
    paths, count, checksum = decode_record(raw)
    assert paths == [
        b"C:\\SAMPLE.TXT",
        b"C:\\$ED0001.TMP",
        b"C:\\SAMPLE.BAK",
        b"C:\\$EB0000.TMP",
    ], paths
    assert count == len(b"z" + original) and checksum == zlib.crc32(b"z" + original)
    expected = {
        "SAMPLE.TXT": original
        if stage < 2
        else None
        if stage == 2
        else b"z" + original,
        "SAMPLE.BAK": b"PREVIOUS_BACKUP\r\n"
        if stage == 0
        else None
        if stage == 1
        else original,
        "$ED0001.TMP": b"z" + original if stage < 3 else None,
        "$EB0000.TMP": b"PREVIOUS_BACKUP\r\n" if stage in (1, 2, 3) else None,
    }
    for path, body in expected.items():
        actual = subprocess.run(
            ["mtype", "-i", spec, "::" + path], capture_output=True, check=False
        )
        if body is None:
            assert actual.returncode != 0 and b"not found" in actual.stderr.lower(), (
                path
            )
        else:
            assert actual.returncode == 0 and actual.stdout == body, path
    put(
        floppy,
        "AUTOEXEC.BAT",
        f"@ECHO OFF\r\nA:\\RECVTEST.EXE {stage}\r\nA:\\QEXIT.COM\r\n".encode(),
    )
    restart = list(argv)
    restart[restart.index("-qmp") + 1] = (
        f"unix:{directory / 'restart.qmp'},server=on,wait=off"
    )
    restart[restart.index("-serial") + 1] = f"file:{directory / 'restart-serial.log'}"
    with (directory / "restart-qemu.log").open("wb") as log:
        resumed = subprocess.run(
            restart, stdout=subprocess.DEVNULL, stderr=log, timeout=40, check=False
        )
    assert resumed.returncode == 33, resumed.returncode
    probe_log = run(["mtype", "-i", floppy, "::RECOVER.LOG"]).stdout
    (directory / "recover.log").write_bytes(probe_log)
    assert b"PASS " in probe_log and b"FAIL" not in probe_log, probe_log
    assert (
        run(["mtype", "-i", floppy, "::RECOVER.OK"]).stdout.strip()
        == b"RESTART RECORD PASS"
    )
    assert run(["mtype", "-i", spec, "::$ER0000.REC"]).stdout == raw
    put(
        floppy,
        "AUTOEXEC.BAT",
        b"@ECHO OFF\r\nC:\r\nCD \\DWED\r\nDWED.COM C:\\SAMPLE.TXT\r\nA:\\QEXIT.COM\r\n",
    )
    restart[restart.index("-qmp") + 1] = (
        f"unix:{directory / 'editor-restart.qmp'},server=on,wait=off"
    )
    restart[restart.index("-serial") + 1] = (
        f"file:{directory / 'editor-restart-serial.log'}"
    )
    with (directory / "editor-restart-qemu.log").open("wb") as log:
        editor = subprocess.Popen(restart, stdout=subprocess.DEVNULL, stderr=log)
        try:
            recovery = QMPConnection(str(directory / "editor-restart.qmp"))

            def keys(value):
                send_keys(recovery, value)
                time.sleep(0.25)

            def expect(needle, label):
                deadline = time.monotonic() + 20
                while time.monotonic() < deadline:
                    text = read_screen_text(
                        recovery, str(directory / "recovery-vram.bin")
                    )
                    (directory / (label + ".txt")).write_text(text)
                    if needle in text:
                        return text
                    time.sleep(0.2)
                raise AssertionError(text)

            expect("Interrupted save", "startup-discovery")
            keys("r")
            text = expect("Recovered SAMPLE.TXT", "recovered-document")
            assert "zDWED_MARKER" in text and "*" in text.splitlines()[-1], text
            keys("x")
            expect("xzDWED_MARKER", "edited-recovery")
            keys("hmp:sendkey ctrl-z")
            text = expect("zDWED_MARKER", "undone-recovery")
            assert "xzDWED_MARKER" not in text and "*" in text.splitlines()[-1], text
            if stage == 2:
                keys("f2")
                text = expect("zDWED_MARKER", "saved-recovery")
                assert "*" not in text.splitlines()[-1], text
                expected["SAMPLE.TXT"] = b"z" + original
                keys("esc")
            else:
                keys("esc")
                expect("Unsaved changes", "discard-recovery")
                keys("n")
            editor.wait(timeout=15)
            assert editor.returncode == 33, editor.returncode
        finally:
            if editor.poll() is None:
                editor.terminate()
                editor.wait(timeout=5)
    for path, body in expected.items():
        actual = subprocess.run(
            ["mtype", "-i", spec, "::" + path], capture_output=True, check=False
        )
        if body is None:
            assert actual.returncode != 0 and b"not found" in actual.stderr.lower(), (
                path
            )
        else:
            assert actual.returncode == 0 and actual.stdout == body, path
    assert run(["mtype", "-i", spec, "::$ER0000.REC"]).stdout == raw
    return {
        "completed": True,
        "exact_match": True,
        "backup_matches_expected": True,
        "cut_stage": stage,
        "rebooted": True,
        "editor_recovered": True,
        "recovery_saved": stage == 2,
        "undo_retains_unsaved_state": True,
        "record_sha256": hashlib.sha256(raw).hexdigest(),
        "record_bytes": len(raw),
        "payload_crc32": checksum,
        "restart_probe": probe_log.decode("ascii").strip(),
    }
