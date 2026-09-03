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
import struct
import subprocess
import sys
import tempfile
import time
import zipfile


ROOT = Path(__file__).resolve().parents[1]
SCREEN_EXPECT = ROOT / "tests" / "screen_expect.py"
FLOPPY_BYTES = 1_474_560
VC_ROW = re.compile(
    r"(?:^|║)\s*([0-9A-F]{4})\s+(\d+)\s+([0-9][0-9,]*)\s+"
    r"(DOS (?:3\.31|6\.00)|COMMAND(?:\.COM)?|VC\.COM|free memory|system)(?:\s|║)",
    re.MULTILINE,
)
CEILING_ROW = re.compile(
    r"MEMORY_CEILING INT12=([0-9A-F]{4}) BDA=([0-9A-F]{4}) EBDA=([0-9A-F]{4})"
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


def parse(screen_path: Path, mem: str, ceiling: str) -> dict[str, int]:
    screen = screen_path.read_text(encoding="utf-8")
    rows = {
        (int(segment, 16), int(blocks), int(size.replace(",", "")), owner)
        for segment, blocks, size, owner in VC_ROW.findall(screen)
    }
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
    }


def report(
    results: dict[str, dict[str, int]],
    media: Path,
    vc_hash: str,
    release: str,
    variants: dict[str, list[str]],
    disk_md5: str | None,
) -> str:
    disk_identity = [f"- Decoded disk MD5: `{disk_md5}`"] if disk_md5 else []
    lines = [
        "# DR-DOS memory investigation", "",
        "Generated from user-supplied binary media; no DR-DOS source code is used.", "",
        f"- Release: {release}",
        f"- Binary media SHA-256: `{sha256(media)}`",
        *disk_identity,
        f"- VC 4.05 SHA-256: `{vc_hash}`",
        "- Hardware: QEMU `pc`, 486 CPU, 8 MiB RAM", "",
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
    args = parser.parse_args()
    require_tools()
    with tempfile.TemporaryDirectory(prefix="drdos-memory-") as temporary:
        work = Path(temporary)
        if zipfile.is_zipfile(args.media):
            release = "Caldera OpenDOS 7.01"
            variants = OPENDOS_VARIANTS
            base, vc_hash = prepare_opendos(args.media, args.vc_image, work)
            disk_md5 = None
        else:
            release = "Digital Research DR-DOS 6.0"
            variants = DRDOS6_VARIANTS
            base, vc_hash, disk_md5 = prepare_drdos6(args.media, args.vc_image, work)
        results: dict[str, dict[str, int]] = {}
        for name, lines in variants.items():
            image = work / f"{name}.ima"
            shutil.copyfile(base, image)
            config, autoexec = write_startup(work, lines, AUTOEXEC_COMMANDS.get(name, []))
            install_file(image, config, "CONFIG.SYS")
            install_file(image, autoexec, "AUTOEXEC.BAT")
            screen, mem, ceiling = capture(image, name, work)
            results[name] = parse(screen, mem, ceiling)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(
            report(results, args.media, vc_hash, release, variants, disk_md5),
            encoding="utf-8",
        )
    print(f"wrote {args.report}")


if __name__ == "__main__":
    main()
