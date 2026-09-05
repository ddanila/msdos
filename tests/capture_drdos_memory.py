#!/usr/bin/env python3
"""Measure an OpenDOS/DR-DOS binary distribution without retaining its files."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time
from typing import Any
import zipfile


ROOT = Path(__file__).resolve().parents[1]
SCREEN_EXPECT = ROOT / "tests" / "screen_expect.py"
PUBLIC_PROBE_SOURCE = ROOT / "tests" / "drdos_public_memory_probe.asm"
QEMU_EXIT_SOURCE = ROOT / "tests" / "qemu_exit.asm"
WARM_REBOOT_SOURCE = ROOT / "tests" / "warm_reboot.asm"
FLOPPY_BYTES = 1_474_560
VC_ROW = re.compile(
    r"(?:^|║)\s*([0-9A-F]{4})\s+(\d+)\s+([0-9][0-9,]*)\s+"
    r"(.{1,15})",
    re.MULTILINE,
)
CEILING_ROW = re.compile(
    r"MEMORY_CEILING INT12=([0-9A-F]{4}) BDA=([0-9A-F]{4}) EBDA=([0-9A-F]{4})"
)
PUBLIC_RECORD = re.compile(
    r"^([A-Z0-9_]+) CF=([01]) AX=([0-9A-F]{4}) BX=([0-9A-F]{4}) "
    r"DX=([0-9A-F]{4})$",
    re.MULTILINE,
)
PUBLIC_RECORD_NAMES = {
    "DOS_VERSION", "DOS_ALLOC_STRATEGY", "DOS_UMB_LINK", "XMS_PRESENT",
    "XMS_VERSION", "A20_QUERY", "XMS_FREE", "XMS_UMB_LARGEST",
    "HMA_REQUEST", "HMA_RELEASE", "A20_FINAL",
    "EMS_STATUS", "EMS_VERSION", "EMS_FRAME", "EMS_PAGES",
}

KNOWN_MEDIA_SHA256 = {
    "Caldera OpenDOS 7.01": "4d25bb3f10cf13596c7b962ab7fdd4f9165e80bef318b72e22b450817b8ee151",
    "Digital Research DR-DOS 6.0": "8902dc7040ae08c2941c48ce0540277ae2f3005f8e564ea45a602f414286b40f",
}
KNOWN_DRDOS6_DISK_MD5 = "a01ecc2548744606c0d8baa74daa64ae"
KNOWN_VC_SHA256 = "b408f14da5bcba174f5e86107437b22b2863ee6ec72f79bdadf1b812607405fb"

KNOWN_DRDOS6_RESULTS = {
    "low": (571_328, 584_128, 62_240, 6_256, 0, 0, 639, 0x9FC0),
    "hidos-high": (611_808, 624_608, 26_752, 1_264, 0, 18_800, 639, 0x9FC0),
    "emm-high": (615_024, 717_936, 23_520, 1_264, 90_096, 18_800, 639, 0x9FC0),
    "emm-hidos": (627_824, 717_920, 10_720, 1_264, 77_280, 18_800, 639, 0x9FC0),
    "emm-hibuffers": (627_824, 725_328, 10_720, 1_264, 84_688, 10_880, 639, 0x9FC0),
    "emm-frame": (627_824, 656_208, 10_720, 1_264, 15_568, 10_880, 639, 0x9FC0),
    "emm-xbda": (627_824, 725_328, 10_720, 1_264, 84_688, 10_880, 639, 0x9FC0),
    "emm-lowmem": (627_824, 725_328, 10_720, 1_264, 84_688, 10_880, 639, 0x9FC0),
    "emm-video": (726_128, 823_632, 11_744, 1_264, 84_688, 10_880, 640, 0x02AC),
}
KNOWN_RESULT_FIELDS = (
    "largest", "total_free", "system_span", "command_span", "upper_free",
    "hma_free", "int12", "ebda",
)


OPENDOS_VARIANTS = {
    "low": ["DOS=LOW", "HIDOS=OFF", "BUFFERS=15"],
    "himem-high": ["DEVICE=HIMEM.SYS", "DOS=HIGH", "HIDOS=OFF", "BUFFERS=15"],
    "emm-high": [
        "DEVICE=EMM386.EXE /FRAME=NONE",
        "DOS=HIGH",
        "HIDOS=OFF",
        "BUFFERS=15",
    ],
    "emm-hidos": [
        "DEVICE=EMM386.EXE /FRAME=NONE",
        "DOS=HIGH",
        "HIDOS=ON",
        "BUFFERS=15",
    ],
    "emm-hibuffers": [
        "DEVICE=EMM386.EXE /FRAME=NONE",
        "DOS=HIGH",
        "HIDOS=ON",
        "HIBUFFERS=15",
    ],
}

DRDOS6_VARIANTS = {
    "low": ["HIDOS=OFF", "BUFFERS=15"],
    "hidos-high": [
        "DEVICE=HIDOS.SYS /BDOS=FFFF",
        "HIDOS=OFF",
        "BUFFERS=15",
    ],
    "emm-high": [
        "DEVICE=EMM386.SYS /FRAME=NONE /BDOS=FFFF",
        "HIDOS=OFF",
        "BUFFERS=15",
    ],
    "emm-hidos": [
        "DEVICE=EMM386.SYS /FRAME=NONE /BDOS=FFFF",
        "HIDOS=ON",
        "BUFFERS=15",
    ],
    "emm-hibuffers": [
        "DEVICE=EMM386.SYS /FRAME=NONE /BDOS=FFFF",
        "HIDOS=ON",
        "HIBUFFERS=15",
    ],
    "emm-frame": [
        "DEVICE=EMM386.SYS /FRAME=AUTO /BDOS=FFFF",
        "HIDOS=ON",
        "HIBUFFERS=15",
    ],
    "emm-xbda": [
        "DEVICE=EMM386.SYS /FRAME=NONE /BDOS=FFFF /XBDA",
        "HIDOS=ON",
        "HIBUFFERS=15",
    ],
    "emm-lowmem": [
        "DEVICE=EMM386.SYS /FRAME=NONE /BDOS=FFFF",
        "HIDOS=ON",
        "HIBUFFERS=15",
    ],
    "emm-video": [
        "DEVICE=EMM386.SYS /FRAME=NONE /BDOS=FFFF /VIDEO",
        "HIDOS=ON",
        "HIBUFFERS=15",
    ],
}

AUTOEXEC_COMMANDS = {
    "emm-lowmem": ["MEMMAX +L"],
    "emm-video": ["MEMMAX +V"],
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_tools() -> None:
    names = ("mcopy", "mdel", "mtype", "nasm", "qemu-system-i386")
    missing = [name for name in names if not shutil.which(name)]
    if missing:
        raise SystemExit("missing required tool(s): " + ", ".join(missing))


def partition_offset(image: Path) -> int:
    with image.open("rb") as stream:
        stream.seek(454)
        value = stream.read(4)
    if len(value) != 4:
        raise ValueError(f"cannot read partition table from {image}")
    return struct.unpack("<I", value)[0] * 512


def mtools_env() -> dict[str, str]:
    env = os.environ.copy()
    env.update({"MTOOLS_NO_VFAT": "1", "MTOOLS_SKIP_CHECK": "1"})
    return env


def extract_member(archive: Path, name: str, destination: Path) -> None:
    with zipfile.ZipFile(archive) as bundle:
        destination.write_bytes(bundle.read(name))


def image_copy(source: Path, dos_path: str, destination: Path) -> None:
    subprocess.run(
        ["mcopy", "-o", "-i", str(source), f"::{dos_path}", str(destination)],
        check=True,
        env=mtools_env(),
    )


def install_file(image: Path, source: Path, dos_path: str) -> None:
    subprocess.run(
        ["mcopy", "-o", "-i", str(image), str(source), f"::{dos_path}"],
        check=True,
        env=mtools_env(),
    )


def prepare_opendos(archive: Path, vc_image: Path, work: Path) -> tuple[Path, str]:
    disk1 = work / "disk1.ima"
    disk2 = work / "disk2.ima"
    disk3 = work / "disk3.ima"
    extract_member(archive, "LDISK01.144", disk1)
    extract_member(archive, "LDISK02.144", disk2)
    extract_member(archive, "LDISK03.144", disk3)
    for disk in (disk1, disk2, disk3):
        disk.write_bytes(disk.read_bytes()[:FLOPPY_BYTES])

    base = work / "base.ima"
    shutil.copyfile(disk1, base)
    removable = (
        "SETUP2.EX_", "DOSBOOK.EX_", "SECURITY.OVL", "SETUP.HL_", "INSTALL.EXE",
        "SETUP.INI", "KEYB.COM", "COUNTRY.SYS", "UNSECURE.EXE", "SETVER.EXE",
        "LICENSE.TXT", "FDISK.COM", "FORMAT.COM", "UNFORMAT.COM", "CHKDSK.EXE",
        "DISKCOPY.COM", "DISKCOMP.COM", "XCOPY.EXE", "DEBUG.EXE",
    )
    for name in removable:
        subprocess.run(
            ["mdel", "-i", str(base), f"::{name}"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=mtools_env(),
        )

    for source, name in ((disk2, "MEM.EXE"), (disk2, "MEMMAX.COM"), (disk3, "EMM386.EXE")):
        extracted = work / name
        image_copy(source, name, extracted)
        install_file(base, extracted, name)

    return base, add_common_tools(base, vc_image, work)


def pcjs_to_image(source: Path, destination: Path) -> str:
    document = json.loads(source.read_text(encoding="utf-8"))
    output = bytearray()
    for cylinder in document["diskData"]:
        for head in cylinder:
            for sector in head:
                values = sector.get("d", [])
                raw = b"".join(struct.pack("<I", value & 0xFFFFFFFF) for value in values)
                if len(raw) < sector["l"]:
                    fill = struct.pack("<I", (values[-1] if values else 0) & 0xFFFFFFFF)
                    raw += (fill * ((sector["l"] - len(raw) + 3) // 4))[:sector["l"] - len(raw)]
                output.extend(raw[:sector["l"]])
    destination.write_bytes(output)
    actual = hashlib.md5(output).hexdigest()
    expected = document["imageInfo"]["hash"]
    if actual != expected:
        raise ValueError(f"PCjs disk MD5 mismatch: expected {expected}, got {actual}")
    return actual


def add_common_tools(base: Path, vc_image: Path, work: Path) -> str:
    vc = work / "VC.COM"
    vc_spec = f"{vc_image}@@{partition_offset(vc_image)}"
    subprocess.run(
        ["mcopy", "-o", "-i", vc_spec, "::VC/VC.COM", str(vc)],
        check=True,
        env=mtools_env(),
    )
    install_file(base, vc, "VC.COM")
    ceiling = work / "CEILING.COM"
    subprocess.run(
        ["nasm", "-f", "bin", str(ROOT / "tests" / "memory_ceiling_probe.asm"), "-o", str(ceiling)],
        check=True,
    )
    install_file(base, ceiling, "CEILING.COM")
    return sha256(vc)


def build_public_probe(work: Path) -> tuple[Path, Path, Path, str]:
    probe = work / "DRPROBE.COM"
    qexit = work / "QEXIT.COM"
    warmboot = work / "WARMBOOT.COM"
    subprocess.run(
        ["nasm", "-f", "bin", str(PUBLIC_PROBE_SOURCE), "-o", str(probe)],
        check=True,
    )
    subprocess.run(
        ["nasm", "-f", "bin", str(QEMU_EXIT_SOURCE), "-o", str(qexit)],
        check=True,
    )
    subprocess.run(
        ["nasm", "-f", "bin", str(WARM_REBOOT_SOURCE), "-o", str(warmboot)],
        check=True,
    )
    return probe, qexit, warmboot, sha256(probe)


def prepare_drdos6(media: Path, vc_image: Path, work: Path) -> tuple[Path, str, str]:
    base = work / "base.img"
    disk_md5 = pcjs_to_image(media, base)
    removable = (
        "SUPERPCK.EXE", "SUPERPCK.SB1", "SUPERPCK.SB6", "SUPERPCK.SB7",
        "SUPERPCK.SB8", "UNDELETE.EXE", "DISKOPT.EXE", "SETUP.EXE",
        "INSTALL.EXE", "SECURITY.EXE",
    )
    for name in removable:
        subprocess.run(
            ["mdel", "-i", str(base), f"::{name}"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=mtools_env(),
        )
    return base, add_common_tools(base, vc_image, work), disk_md5


def write_startup(work: Path, lines: list[str], commands: list[str]) -> tuple[Path, Path]:
    config = work / "CONFIG.SYS"
    common = ["FILES=30", "FCBS=4,0", "LASTDRIVE=Z", "STACKS=9,256", "SHELL=COMMAND.COM /P /E:512"]
    config.write_bytes(("\r\n".join(lines + common) + "\r\n").encode("ascii"))
    autoexec = work / "AUTOEXEC.BAT"
    batch = ["@ECHO OFF", *commands, "MEM /A > MEMA.TXT", "CEILING.COM > CEIL.TXT", "VC.COM"]
    autoexec.write_bytes(("\r\n".join(batch) + "\r\n").encode("ascii"))
    return config, autoexec


def capture(image: Path, label: str, work: Path) -> tuple[Path, str, str]:
    qmp = work / f"{label}.qmp"
    screen = work / f"{label}-screen.log"
    command = [
        "qemu-system-i386", "-display", "none", "-monitor", "none",
        "-machine", "pc", "-cpu", "486", "-m", "8",
        "-drive", f"if=floppy,index=0,format=raw,file={image},cache=writethrough",
        "-boot", "a", "-qmp", f"unix:{qmp},server=on,wait=off", "-no-reboot",
    ]
    process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic() + 15
        while not qmp.exists() and time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError(process.stderr.read().decode(errors="replace"))
            time.sleep(0.1)
        subprocess.run(
            [sys.executable, str(SCREEN_EXPECT), str(qmp), str(screen),
             "1Help", "hmp:sendkey alt-f5", "Memory Info", "hmp:stop"],
            check=True,
            timeout=150,
        )
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    mem = subprocess.check_output(
        ["mtype", "-i", str(image), "::MEMA.TXT"], env=mtools_env()
    ).decode("cp437")
    ceiling = subprocess.check_output(
        ["mtype", "-i", str(image), "::CEIL.TXT"], env=mtools_env()
    ).decode("ascii", errors="replace")
    return screen, mem, ceiling


def capture_public_interfaces(
    configured_image: Path,
    label: str,
    work: Path,
    probe: Path,
    qexit: Path,
) -> str:
    image = work / f"{label}-interfaces.ima"
    autoexec = work / f"{label}-interfaces.bat"
    shutil.copyfile(configured_image, image)
    install_file(image, probe, "DRPROBE.COM")
    install_file(image, qexit, "QEXIT.COM")
    autoexec.write_bytes(
        b"@ECHO OFF\r\nDRPROBE.COM > PROBE.TXT\r\nQEXIT.COM\r\n"
    )
    install_file(image, autoexec, "AUTOEXEC.BAT")
    command = [
        "qemu-system-i386", "-display", "none", "-monitor", "none",
        "-machine", "pc", "-cpu", "486", "-m", "8",
        "-drive", f"if=floppy,index=0,format=raw,file={image},cache=writethrough",
        "-boot", "a", "-no-reboot",
        "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04",
    ]
    try:
        subprocess.run(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f"public-interface probe timed out for {label}") from error
    try:
        output = subprocess.check_output(
            ["mtype", "-i", str(image), "::PROBE.TXT"], env=mtools_env()
        ).decode("ascii", errors="replace")
    except subprocess.CalledProcessError as error:
        raise RuntimeError(f"public-interface output missing for {label}") from error
    if "DRDOS_PUBLIC_MEMORY_END" not in output:
        raise RuntimeError(f"public-interface probe incomplete for {label}")
    return output


def qmp_system_reset(socket_path: Path) -> None:
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    connection.settimeout(10)
    connection.connect(str(socket_path))
    stream = connection.makefile("rwb", buffering=0)

    def receive_response() -> dict[str, Any]:
        while True:
            line = stream.readline()
            if not line:
                raise RuntimeError("QMP connection closed")
            response = json.loads(line)
            if "return" in response or "error" in response:
                return response

    stream.readline()
    stream.write(b'{"execute":"qmp_capabilities"}\n')
    if "error" in receive_response():
        raise RuntimeError("QMP capability negotiation failed")
    stream.write(b'{"execute":"system_reset"}\n')
    if "error" in receive_response():
        raise RuntimeError("QMP system_reset failed")
    stream.close()
    connection.close()


def capture_warm_public_interfaces(
    configured_image: Path,
    label: str,
    work: Path,
    probe: Path,
    qexit: Path,
    warmboot: Path,
) -> tuple[str, str]:
    image = work / f"{label}-interfaces-warm.ima"
    autoexec = work / f"{label}-interfaces-warm.bat"
    qmp = Path("/tmp") / f"drwarm-{os.getpid()}-{label}.qmp"
    serial = work / f"{label}-interfaces-warm.log"
    shutil.copyfile(configured_image, image)
    for source, name in (
        (probe, "DRPROBE.COM"),
        (qexit, "QEXIT.COM"),
        (warmboot, "WARMBOOT.COM"),
    ):
        install_file(image, source, name)
    autoexec.write_bytes(
        b"@ECHO OFF\r\n"
        b"IF EXIST WARM.OK GOTO SECOND\r\n"
        b"DRPROBE.COM > BEFORE.TXT\r\n"
        b"ECHO READY>WARM.OK\r\n"
        b"CTTY AUX\r\n"
        b"WARMBOOT.COM\r\n"
        b":SECOND\r\n"
        b"DRPROBE.COM > AFTER.TXT\r\n"
        b"QEXIT.COM\r\n"
    )
    install_file(image, autoexec, "AUTOEXEC.BAT")
    qmp.unlink(missing_ok=True)
    command = [
        "qemu-system-i386", "-display", "none", "-monitor", "none",
        "-machine", "pc", "-cpu", "486", "-m", "8",
        "-drive", f"if=floppy,index=0,format=raw,file={image},cache=writethrough",
        "-boot", "a", "-qmp", f"unix:{qmp},server=on,wait=off",
        "-serial", f"file:{serial}",
        "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04",
    ]
    process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError(f"warm-reboot probe exited before reset for {label}")
            if qmp.exists() and serial.exists() and "WARM_RESET_READY" in serial.read_text(
                encoding="ascii", errors="replace"
            ):
                break
            time.sleep(0.1)
        else:
            raise RuntimeError(f"warm-reboot probe did not reach reset point for {label}")
        qmp_system_reset(qmp)
        try:
            process.wait(timeout=40)
        except subprocess.TimeoutExpired as error:
            raise RuntimeError(f"warm-reboot second boot timed out for {label}") from error
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        qmp.unlink(missing_ok=True)

    outputs = []
    for name in ("BEFORE.TXT", "AFTER.TXT"):
        try:
            value = subprocess.check_output(
                ["mtype", "-i", str(image), f"::{name}"], env=mtools_env()
            ).decode("ascii", errors="replace")
        except subprocess.CalledProcessError as error:
            raise RuntimeError(f"warm-reboot output {name} missing for {label}") from error
        if "DRDOS_PUBLIC_MEMORY_END" not in value:
            raise RuntimeError(f"warm-reboot output {name} incomplete for {label}")
        outputs.append(value)
    return outputs[0], outputs[1]


def parse_vc_rows(screen: str) -> list[tuple[int, int, int, str]]:
    rows = {
        (int(segment, 16), int(blocks), int(size.replace(",", "")), owner.strip())
        for segment, blocks, size, owner in VC_ROW.findall(screen)
    }
    return sorted(rows)


def parse_public_interfaces(output: str) -> dict[str, Any]:
    records: dict[str, dict[str, int]] = {}
    for name, carry, ax, bx, dx in PUBLIC_RECORD.findall(output.replace("\r", "")):
        if name not in PUBLIC_RECORD_NAMES:
            raise ValueError(f"unknown public-interface record: {name}")
        if name in records:
            raise ValueError(f"duplicate public-interface record: {name}")
        records[name] = {
            "cf": int(carry),
            "ax": int(ax, 16),
            "bx": int(bx, 16),
            "dx": int(dx, 16),
        }

    required = {"DOS_VERSION", "DOS_ALLOC_STRATEGY", "DOS_UMB_LINK", "XMS_PRESENT"}
    missing = required - records.keys()
    if missing:
        raise ValueError("missing public-interface record(s): " + ", ".join(sorted(missing)))

    xms_available = records["XMS_PRESENT"]["ax"] & 0xff == 0x80
    xms_records = {
        "XMS_VERSION", "A20_QUERY", "XMS_FREE", "XMS_UMB_LARGEST",
        "HMA_REQUEST", "A20_FINAL",
    }
    if xms_available:
        missing = xms_records - records.keys()
        if missing:
            raise ValueError("missing XMS record(s): " + ", ".join(sorted(missing)))
        hma_acquired = records["HMA_REQUEST"]["ax"] != 0
        if hma_acquired and "HMA_RELEASE" not in records:
            raise ValueError("missing HMA_RELEASE after successful request")
        if not hma_acquired and "HMA_RELEASE" in records:
            raise ValueError("unexpected HMA_RELEASE after failed request")
        if records["A20_QUERY"]["ax"] != records["A20_FINAL"]["ax"]:
            raise ValueError("HMA transaction changed A20 state")
    elif "XMS_UNAVAILABLE" not in output:
        raise ValueError("missing XMS_UNAVAILABLE record")

    ems_records = {"EMS_STATUS", "EMS_VERSION", "EMS_FRAME", "EMS_PAGES"}
    ems_available = ems_records <= records.keys()
    if not ems_available and "EMS_UNAVAILABLE" not in output:
        missing = ems_records - records.keys()
        raise ValueError("incomplete EMS record(s): " + ", ".join(sorted(missing)))

    return {
        "records": records,
        "xms_available": xms_available,
        "ems_available": ems_available,
        "sha256": hashlib.sha256(output.encode("ascii", errors="replace")).hexdigest(),
    }


def public_interface_semantics(parsed: dict[str, Any]) -> dict[str, tuple[int, ...]]:
    records = parsed["records"]
    semantics: dict[str, tuple[int, ...]] = {}
    for name, record in records.items():
        ax, bx, dx = record["ax"], record["bx"], record["dx"]
        if name in {"DOS_VERSION", "XMS_VERSION"}:
            semantics[name] = (ax, bx, dx)
        elif name in {"DOS_ALLOC_STRATEGY", "DOS_UMB_LINK"}:
            semantics[name] = (record["cf"], ax)
        elif name == "XMS_PRESENT":
            semantics[name] = (ax & 0xff,)
        elif name in {"A20_QUERY", "A20_FINAL"}:
            semantics[name] = (ax, bx & 0xff)
        elif name == "XMS_FREE":
            semantics[name] = (ax, dx, bx & 0xff)
        elif name in {"XMS_UMB_LARGEST", "HMA_REQUEST", "HMA_RELEASE"}:
            semantics[name] = (ax, bx & 0xff, dx)
        elif name in {"EMS_STATUS", "EMS_VERSION"}:
            semantics[name] = (ax,)
        elif name == "EMS_FRAME":
            semantics[name] = (ax >> 8, bx)
        elif name == "EMS_PAGES":
            semantics[name] = (ax >> 8, bx, dx)
    semantics["AVAILABILITY"] = (
        int(parsed["xms_available"]), int(parsed["ems_available"])
    )
    return semantics


def parse(screen_path: Path, mem: str, ceiling: str) -> dict[str, Any]:
    screen = screen_path.read_text(encoding="utf-8")
    rows = parse_vc_rows(screen)
    conventional = [row for row in rows if row[3] == "free memory" and row[0] < 0xA000]
    if not conventional:
        raise ValueError(f"no conventional VC row in {screen_path}")
    first = min(conventional)
    dos = min((row for row in rows if row[3].startswith("DOS ")), default=None)
    command = min((row for row in rows if row[3].startswith("COMMAND")), default=None)
    vc = min((row for row in rows if row[3] == "VC.COM"), default=None)
    upper_free = sum(row[2] for row in rows if row[3] == "free memory" and row[0] >= 0xA000)
    if not (dos and command and vc):
        raise ValueError(f"incomplete VC owner rows in {screen_path}")
    ceiling_match = CEILING_ROW.search(ceiling)
    if not ceiling_match:
        raise ValueError("ceiling probe output missing")

    def available(kind: str) -> int:
        match = re.search(
            rf"^│ {kind}\s+│\s*[0-9,]+\s+\([^)]*\)\s+│\s*([0-9,]+)",
            mem,
            re.MULTILINE,
        )
        return int(match.group(1).replace(",", "")) if match else 0

    return {
        "largest": first[2],
        "first_free": first[0],
        "dos_payload": dos[2],
        "system_span": (command[0] - dos[0]) * 16,
        "command_payload": command[2],
        "command_span": (vc[0] - command[0]) * 16,
        "vc_span": (first[0] - vc[0]) * 16,
        "upper_free": upper_free,
        "hma_free": available("High"),
        "total_free": available("Conventional") + available("Upper"),
        "int12": int(ceiling_match.group(1), 16),
        "bda": int(ceiling_match.group(2), 16),
        "ebda": int(ceiling_match.group(3), 16),
        "owners": [
            {"segment": segment, "blocks": blocks, "bytes": size, "owner": owner}
            for segment, blocks, size, owner in rows
        ],
        "mem_sha256": hashlib.sha256(mem.encode("cp437")).hexdigest(),
        "screen_sha256": hashlib.sha256(screen.encode("utf-8")).hexdigest(),
        "ceiling_sha256": hashlib.sha256(ceiling.encode("ascii", errors="replace")).hexdigest(),
    }


def qemu_identity() -> str:
    return subprocess.check_output(
        ["qemu-system-i386", "--version"], text=True
    ).splitlines()[0]


def comparison_identities_match(
    release: str, media_hash: str, vc_hash: str, disk_md5: str | None
) -> bool:
    return (
        media_hash == KNOWN_MEDIA_SHA256[release]
        and vc_hash == KNOWN_VC_SHA256
        and (disk_md5 is None or disk_md5 == KNOWN_DRDOS6_DISK_MD5)
    )


def validate_known_results(release: str, results: dict[str, dict[str, Any]]) -> None:
    if release != "Digital Research DR-DOS 6.0":
        return
    for name, result in results.items():
        expected = KNOWN_DRDOS6_RESULTS[name]
        actual = tuple(result[field] for field in KNOWN_RESULT_FIELDS)
        if actual != expected:
            differences = ", ".join(
                f"{field}={value!r} (expected {wanted!r})"
                for field, value, wanted in zip(KNOWN_RESULT_FIELDS, actual, expected)
                if value != wanted
            )
            raise RuntimeError(f"DR-DOS 6 baseline changed for {name}: {differences}")


def report(
    results: dict[str, dict[str, Any]],
    media: Path,
    vc_hash: str,
    release: str,
    variants: dict[str, list[str]],
    disk_md5: str | None,
    emulator: str,
    probe_hash: str,
) -> str:
    disk_identity = [f"- Decoded disk MD5: `{disk_md5}`"] if disk_md5 else []
    lines = [
        "# DR-DOS memory investigation", "",
        "Generated from user-supplied binary media; no DR-DOS source code is used.", "",
        f"- Release: {release}",
        f"- Binary media SHA-256: `{sha256(media)}`",
        *disk_identity,
        f"- VC 4.05 SHA-256: `{vc_hash}`",
        f"- Public memory probe SHA-256: `{probe_hash}`",
        f"- Emulator: `{emulator}`",
        "- Hardware: QEMU `pc`, 486 CPU, 8 MiB RAM; default firmware",
        "- Capture command fixes `-machine pc -cpu 486 -m 8`, floppy boot, "
        "writethrough caching, and no reboot", "",
        "| Variant | Largest block | Total free | System span | COMMAND span | Free UMB | Free HMA | INT 12h | EBDA |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for name, data in results.items():
        lines.append(
            f"| {name} | {data['largest']:,} | {data['total_free']:,} | "
            f"{data['system_span']:,} | {data['command_span']:,} | "
            f"{data['upper_free']:,} | {data['hma_free']:,} | {data['int12']} KiB | "
            f"{data['ebda']:04X}h |"
        )
    lines.extend([
        "", "Common settings: `FILES=30`, `FCBS=4,0`, `LASTDRIVE=Z`, "
        "`STACKS=9,256`, and a 512-byte shell environment.",
        "", "## Startup matrix", "",
    ])
    for name, config in variants.items():
        lines.extend([f"### {name}", "", "```ini", *config, "```", ""])
        commands = AUTOEXEC_COMMANDS.get(name)
        if commands:
            lines.extend(["Before measurement:", "", "```bat", *commands, "```", ""])
    lines.extend(["## Normalized ownership evidence", ""])
    for name, data in results.items():
        lines.extend([
            f"### {name}", "",
            f"Raw evidence SHA-256: VC screen `{data['screen_sha256']}`, "
            f"`MEM /A` `{data['mem_sha256']}`, ceiling `{data['ceiling_sha256']}`.", "",
            "| Segment | Blocks | Bytes | Owner |",
            "| ---: | ---: | ---: | --- |",
        ])
        for owner in data["owners"]:
            lines.append(
                f"| {owner['segment']:04X}h | {owner['blocks']} | "
                f"{owner['bytes']:,} | {owner['owner']} |"
            )
        lines.append("")
    lines.extend(["## Public memory interfaces", ""])
    for name, data in results.items():
        interfaces = data["interfaces"]
        lines.extend([
            f"### {name}", "",
            f"Raw probe output SHA-256: `{interfaces['sha256']}`.", "",
            "| Query | CF | AX | BX | DX |",
            "| --- | ---: | ---: | ---: | ---: |",
        ])
        for record_name, record in interfaces["records"].items():
            lines.append(
                f"| {record_name} | {record['cf']} | {record['ax']:04X}h | "
                f"{record['bx']:04X}h | {record['dx']:04X}h |"
            )
        if not interfaces["xms_available"]:
            lines.append("| XMS_UNAVAILABLE | — | — | — | — |")
        if not interfaces["ems_available"]:
            lines.append("| EMS_UNAVAILABLE | — | — | — | — |")
        lines.append("")
        warm = data.get("warm_reboot")
        if warm:
            lines.extend([
                "Warm-reset public-interface comparison: **stable**. "
                f"Before SHA-256 `{warm['before']['sha256']}`; after SHA-256 "
                f"`{warm['after']['sha256']}`.", "",
            ])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "media",
        type=Path,
        help="OpenDOS 7.01 DODL701.EXE archive or PCjs DR-DOS 6 disk JSON",
    )
    parser.add_argument("vc_image", type=Path, help="hard-disk image containing VC 4.05 in C:\\VC")
    parser.add_argument("report", type=Path)
    parser.add_argument(
        "--evidence-dir",
        type=Path,
        help="retain raw VC screen, MEM /A, and ceiling outputs for each variant",
    )
    parser.add_argument(
        "--allow-unknown-media",
        action="store_true",
        help="permit media or VC hashes other than the recorded comparison artifacts",
    )
    parser.add_argument(
        "--variant",
        action="append",
        help="capture only the named variant; repeat for multiple focused cases",
    )
    args = parser.parse_args()
    require_tools()
    with tempfile.TemporaryDirectory(prefix="drdos-memory-") as temporary:
        work = Path(temporary)
        public_probe, qexit, warmboot, probe_hash = build_public_probe(work)
        if zipfile.is_zipfile(args.media):
            release = "Caldera OpenDOS 7.01"
            variants = OPENDOS_VARIANTS
            base, vc_hash = prepare_opendos(args.media, args.vc_image, work)
            disk_md5 = None
        else:
            release = "Digital Research DR-DOS 6.0"
            variants = DRDOS6_VARIANTS
            base, vc_hash, disk_md5 = prepare_drdos6(args.media, args.vc_image, work)
        if args.variant:
            unknown = set(args.variant) - variants.keys()
            if unknown:
                raise SystemExit("unknown variant(s): " + ", ".join(sorted(unknown)))
            variants = {name: variants[name] for name in args.variant}
        media_hash = sha256(args.media)
        identities_match = comparison_identities_match(
            release, media_hash, vc_hash, disk_md5
        )
        if not identities_match and not args.allow_unknown_media:
            raise SystemExit(
                "comparison artifact hash mismatch; use --allow-unknown-media "
                "only for an intentional non-baseline capture"
            )
        if args.evidence_dir:
            args.evidence_dir.mkdir(parents=True, exist_ok=True)
        results: dict[str, dict[str, Any]] = {}
        for name, lines in variants.items():
            image = work / f"{name}.ima"
            shutil.copyfile(base, image)
            config, autoexec = write_startup(work, lines, AUTOEXEC_COMMANDS.get(name, []))
            install_file(image, config, "CONFIG.SYS")
            install_file(image, autoexec, "AUTOEXEC.BAT")
            configured_image = work / f"{name}-configured.ima"
            shutil.copyfile(image, configured_image)
            screen, mem, ceiling = capture(image, name, work)
            if args.evidence_dir:
                shutil.copyfile(screen, args.evidence_dir / f"{name}-vc.txt")
                (args.evidence_dir / f"{name}-mem.txt").write_text(mem, encoding="utf-8")
                (args.evidence_dir / f"{name}-ceiling.txt").write_text(
                    ceiling, encoding="ascii", errors="replace"
                )
            results[name] = parse(screen, mem, ceiling)
            interface_output = capture_public_interfaces(
                configured_image, name, work, public_probe, qexit
            )
            results[name]["interfaces"] = parse_public_interfaces(interface_output)
            if args.evidence_dir:
                (args.evidence_dir / f"{name}-interfaces.txt").write_text(
                    interface_output, encoding="ascii", errors="replace"
                )
            if name == "emm-hibuffers":
                before_output, after_output = capture_warm_public_interfaces(
                    configured_image, name, work, public_probe, qexit, warmboot
                )
                before = parse_public_interfaces(before_output)
                after = parse_public_interfaces(after_output)
                if public_interface_semantics(before) != public_interface_semantics(after):
                    raise RuntimeError(
                        f"public memory interfaces changed across warm reset for {name}"
                    )
                results[name]["warm_reboot"] = {"before": before, "after": after}
                if args.evidence_dir:
                    for suffix, value in (("before-reset", before_output), ("after-reset", after_output)):
                        (args.evidence_dir / f"{name}-interfaces-{suffix}.txt").write_text(
                            value, encoding="ascii", errors="replace"
                        )
        if identities_match:
            validate_known_results(release, results)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(
            report(
                results, args.media, vc_hash, release, variants, disk_md5,
                qemu_identity(), probe_hash,
            ),
            encoding="utf-8",
        )
    print(f"wrote {args.report}")


if __name__ == "__main__":
    main()
