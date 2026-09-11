"""Stop after replacement operations, then reboot DOS to inspect recovery data."""

import hashlib
import struct
import subprocess
import zlib

from screen_expect import send_keys
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
    return {
        "completed": True,
        "exact_match": True,
        "backup_matches_expected": True,
        "cut_stage": stage,
        "rebooted": True,
        "record_sha256": hashlib.sha256(raw).hexdigest(),
        "record_bytes": len(raw),
        "payload_crc32": checksum,
        "restart_probe": probe_log.decode("ascii").strip(),
    }
