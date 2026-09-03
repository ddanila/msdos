#!/usr/bin/env python3
"""Capture and compare VC 4.05 and MEM /D memory views from two DOS images."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
SCREEN_EXPECT = ROOT / "tests" / "screen_expect.py"


def require_tools() -> None:
    missing = [name for name in ("mcopy", "mtype", "nasm", "qemu-system-i386") if not shutil.which(name)]
    if missing:
        raise SystemExit("missing required tool(s): " + ", ".join(missing))


def partition_offset(image: Path) -> int:
    with image.open("rb") as stream:
        stream.seek(446 + 8)
        data = stream.read(4)
    if len(data) != 4:
        raise ValueError(f"cannot read first partition from {image}")
    lba = struct.unpack("<I", data)[0]
    if not lba:
        raise ValueError(f"first partition has a zero start LBA in {image}")
    return lba * 512


def image_file(image: Path, dos_path: str) -> bytes:
    spec = f"{image}@@{partition_offset(image)}"
    env = os.environ.copy()
    env.update({"MTOOLS_NO_VFAT": "1", "MTOOLS_SKIP_CHECK": "1"})
    return subprocess.check_output(["mtype", "-i", spec, dos_path], env=env)


def install_autoexec(image: Path, ceiling_probe: Path) -> None:
    spec = f"{image}@@{partition_offset(image)}"
    autoexec = (
        "@ECHO OFF\r\n"
        "PATH C:\\DOS;C:\\VC\r\n"
        "PROMPT $P$G\r\n"
        "CTTY AUX\r\n"
        "CEILING.COM\r\n"
        "ECHO PARITY_MEM_BEGIN\r\n"
        "MEM /D\r\n"
        "ECHO PARITY_MEM_END\r\n"
        "CTTY CON\r\n"
        "CD \\VC\r\n"
        "VC.COM\r\n"
    ).encode("ascii")
    env = os.environ.copy()
    env.update({"MTOOLS_NO_VFAT": "1", "MTOOLS_SKIP_CHECK": "1"})
    subprocess.run(
        ["mcopy", "-o", "-i", spec, str(ceiling_probe), "::CEILING.COM"],
        env=env,
        check=True,
    )
    subprocess.run(
        ["mcopy", "-o", "-i", spec, "-", "::AUTOEXEC.BAT"],
        input=autoexec,
        env=env,
        check=True,
    )


def capture(label: str, source: Path, directory: Path, ceiling_probe: Path) -> tuple[Path, Path]:
    image = directory / f"{label}.img"
    serial_log = directory / f"{label}-serial.log"
    screen_log = directory / f"{label}-screen.log"
    qmp_socket = directory / f"{label}.qmp"
    shutil.copyfile(source, image)
    install_autoexec(image, ceiling_probe)

    command = [
        "qemu-system-i386",
        "-display", "none",
        "-monitor", "none",
        "-machine", "pc",
        "-cpu", "486",
        "-m", "8",
        "-drive", f"if=ide,index=0,media=disk,format=raw,file={image},cache=writethrough",
        "-boot", "c",
        "-serial", f"file:{serial_log}",
        "-qmp", f"unix:{qmp_socket},server=on,wait=off",
        "-no-reboot",
    ]
    process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic() + 15
        while not qmp_socket.exists() and time.monotonic() < deadline:
            if process.poll() is not None:
                error = process.stderr.read().decode(errors="replace")
                raise RuntimeError(f"QEMU exited before QMP became ready: {error}")
            time.sleep(0.1)
        subprocess.run(
            [
                sys.executable,
                str(SCREEN_EXPECT),
                str(qmp_socket),
                str(screen_log),
                "1Help", "hmp:sendkey alt-f5",
                "Memory Info", "hmp:stop",
            ],
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
    return serial_log, screen_log


VC_ROW = re.compile(
    r"(?:^|\u2551)\s*([0-9A-F]{4})\s+(\d+)\s+([0-9][0-9,]*)\s+"
    r"(DOS 6\.22|COMMAND|VC\.COM|free memory|system)(?:\s|\u2551)",
    re.MULTILINE,
)
MEM_ROW = re.compile(
    r"^\s{2}([0-9A-F]{4}):0000\s+(\S+)\s+([0-9]+)\s+(\S+)",
    re.MULTILINE,
)
RETAIL_MEM_ROW = re.compile(
    r"^[ \t]+0([0-9A-F]{4})[ \t]+([0-9][0-9,]*)[ \t]+"
    r"\([^\r\n)]*\)[ \t]+([^\r\n]+)$",
    re.MULTILINE,
)
MEM_COMPONENT = re.compile(
    r"^\s+(HIMEM|EMM386|MSDOS)\s+([0-9]+)\s+(.+?)\s*$",
    re.MULTILINE,
)
CEILING_ROW = re.compile(
    r"^MEMORY_CEILING INT12=([0-9A-F]{4}) BDA=([0-9A-F]{4}) EBDA=([0-9A-F]{4})$",
    re.MULTILINE,
)


def parse_capture(serial_log: Path, screen_log: Path) -> dict[str, object]:
    serial = serial_log.read_text(encoding="latin-1", errors="replace").replace("\r", "")
    screen = screen_log.read_text(encoding="utf-8", errors="replace")
    if "PARITY_MEM_END" not in serial:
        raise ValueError(f"MEM /D did not complete in {serial_log}")
    ceiling_match = CEILING_ROW.search(serial)
    if not ceiling_match:
        raise ValueError(f"memory ceiling probe did not complete in {serial_log}")

    vc_rows = [
        {
            "segment": int(segment, 16),
            "blocks": int(blocks),
            "size": int(size.replace(",", "")),
            "name": name.strip(),
        }
        for segment, blocks, size, name in VC_ROW.findall(screen)
    ]
    # screen_expect records the matched screen and the final screen; deduplicate it.
    vc_rows = list({
        (row["segment"], row["blocks"], row["size"], row["name"]): row
        for row in vc_rows
    }.values())
    conventional_free = [row for row in vc_rows if row["name"] == "free memory" and row["segment"] < 0xA000]
    if not conventional_free:
        raise ValueError(f"VC conventional free block was not found in {screen_log}")

    mem_rows: list[dict[str, object]] = [
        {"segment": int(segment, 16), "name": name, "size": int(size), "type": kind}
        for segment, name, size, kind in MEM_ROW.findall(serial)
    ]
    if not mem_rows:
        for segment, size, remainder in RETAIL_MEM_ROW.findall(serial):
            fields = re.split(r"[ \t]{2,}", remainder.strip(), maxsplit=1)
            name, kind = (fields[0], fields[1]) if len(fields) == 2 else ("—", fields[0])
            mem_rows.append({
                "segment": int(segment, 16),
                "name": name,
                "size": int(size.replace(",", "")),
                "type": kind,
            })
    components: dict[str, int] = {}
    for name, size, detail in MEM_COMPONENT.findall(serial):
        if detail.startswith("Installed Device"):
            components[name] = components.get(name, 0) + int(size)
    retail_himem = re.search(r"^\s*([0-9,]+)\s+\([^)]*\)\s+XMSXXXX0\s+Installed Device=HIMEM", serial, re.MULTILINE)
    retail_emm386 = re.search(r"^\s*([0-9,]+)\s+\([^)]*\)\s+EMMXXXX0\s+Installed Device=EMM386", serial, re.MULTILINE)
    if retail_himem:
        components["HIMEM"] = int(retail_himem.group(1).replace(",", ""))
    if retail_emm386:
        components["EMM386"] = int(retail_emm386.group(1).replace(",", ""))

    command = next((row for row in vc_rows if row["name"] == "COMMAND"), None)
    low_system = [row for row in vc_rows if row["name"] == "system" and row["segment"] <= 0xA000]
    upper_free = [row for row in vc_rows if row["name"] == "free memory" and row["segment"] >= 0xA000]
    return {
        "largest": max(row["size"] for row in conventional_free),
        "first_free": min(row["segment"] for row in conventional_free),
        "command": command["size"] if command else None,
        "ceiling": max((row["segment"] for row in low_system), default=None),
        "upper_free": sum(row["size"] for row in upper_free),
        "vc_rows": vc_rows,
        "components": components,
        "mem_rows": mem_rows,
        "int12_kb": int(ceiling_match.group(1), 16),
        "bda_kb": int(ceiling_match.group(2), 16),
        "ebda_segment": int(ceiling_match.group(3), 16),
    }


def number(value: object) -> str:
    return "unknown" if value is None else f"{int(value):,}"


def hex_segment(value: object) -> str:
    return "unknown" if value is None else f"{int(value):04X}h"


def vc_prefix_accounting(data: dict[str, object]) -> dict[str, int]:
    """Split VC's conventional prefix into comparable owner-to-owner spans."""
    rows = sorted(
        (row for row in data["vc_rows"] if row["segment"] < 0xA000),
        key=lambda row: row["segment"],
    )

    def first(name: str) -> dict[str, object]:
        row = next((item for item in rows if item["name"] == name), None)
        if row is None:
            raise ValueError(f"VC row {name!r} is required for prefix accounting")
        return row

    command = first("COMMAND")
    vc = first("VC.COM")
    free = first("free memory")
    system_rows = [row for row in rows if row["segment"] < command["segment"]]
    if not system_rows:
        raise ValueError("VC has no conventional system row before COMMAND")
    base = system_rows[0]
    system_span = (command["segment"] - base["segment"]) * 16
    system_payload = sum(row["size"] for row in system_rows)
    return {
        "system_span": system_span,
        "system_payload": system_payload,
        "system_overhead": system_span - system_payload,
        "command_span": (vc["segment"] - command["segment"]) * 16,
        "vc_span": (free["segment"] - vc["segment"]) * 16,
        "ceiling_loss": (0xA000 - int(data["ceiling"])) * 16,
    }


def report(current: dict[str, object], retail: dict[str, object], config_hash: str, vc_hash: str) -> str:
    current_largest = int(current["largest"])
    retail_largest = int(retail["largest"])
    current_prefix = vc_prefix_accounting(current)
    retail_prefix = vc_prefix_accounting(retail)
    lines = [
        "# Conventional-memory comparison",
        "",
        "Fixed configuration: QEMU `pc`, 486 CPU, 8 MiB RAM, unchanged image `CONFIG.SYS`,",
        "and VC 4.05. `MEM /D` runs immediately before VC and exits before measurement.",
        f"The identical `CONFIG.SYS` hash is `{config_hash}`; the identical VC binary hash is `{vc_hash}`.",
        "",
        "| Metric | Current | Retail DOS 6.22 | Difference |",
        "| --- | ---: | ---: | ---: |",
        f"| VC largest conventional block | {current_largest:,} | {retail_largest:,} | {current_largest - retail_largest:+,} |",
        f"| VC first conventional free segment | {hex_segment(current['first_free'])} | {hex_segment(retail['first_free'])} | — |",
        f"| VC COMMAND allocation | {number(current['command'])} | {number(retail['command'])} | {int(current['command']) - int(retail['command']):+,} |",
        f"| Conventional ceiling/system segment | {hex_segment(current['ceiling'])} | {hex_segment(retail['ceiling'])} | — |",
        f"| `INT 12h` conventional memory | {number(current['int12_kb'])} KiB | {number(retail['int12_kb'])} KiB | {int(current['int12_kb']) - int(retail['int12_kb']):+,} KiB |",
        f"| BDA conventional-memory word | {number(current['bda_kb'])} KiB | {number(retail['bda_kb'])} KiB | {int(current['bda_kb']) - int(retail['bda_kb']):+,} KiB |",
        f"| BDA EBDA segment | {hex_segment(current['ebda_segment'])} | {hex_segment(retail['ebda_segment'])} | — |",
        f"| VC free UMB total | {number(current['upper_free'])} | {number(retail['upper_free'])} | {int(current['upper_free']) - int(retail['upper_free']):+,} |",
        "",
        "## Installed memory managers (`MEM /D`)",
        "",
        "| Component | Current | Retail DOS 6.22 | Difference |",
        "| --- | ---: | ---: | ---: |",
    ]
    current_components = current["components"]
    retail_components = retail["components"]
    for component in ("HIMEM", "EMM386"):
        ours = current_components.get(component)
        theirs = retail_components.get(component)
        difference = "unknown" if ours is None or theirs is None else f"{ours - theirs:+,}"
        lines.append(f"| {component} | {number(ours)} | {number(theirs)} | {difference} |")

    lines.extend([
        "",
        "## VC allocation rows",
        "",
        "VC groups adjacent blocks by owner. Its size is the grouped payload;",
        "`Blocks` is retained separately and must not be treated as payload bytes.",
        "",
    ])
    for label, data in (("Current", current), ("Retail DOS 6.22", retail)):
        lines.extend([
            f"### {label}",
            "",
            "| Address | Blocks | Payload | Owner |",
            "| ---: | ---: | ---: | --- |",
        ])
        for row in sorted(data["vc_rows"], key=lambda item: item["segment"]):
            lines.append(
                f"| {row['segment']:04X}h | {row['blocks']} | "
                f"{row['size']:,} | {row['name']} |"
            )
        lines.append("")

    lines.extend([
        "## Conventional-prefix accounting",
        "",
        "Owner-to-owner spans include their intervening MCBs and gaps. Unlike raw",
        "payload totals, their differences reconcile directly with the largest-block",
        "difference when the conventional-ceiling loss is included.",
        "",
        "| Span | Current | Retail DOS 6.22 | Difference |",
        "| --- | ---: | ---: | ---: |",
    ])
    prefix_labels = (
        ("System start to COMMAND", "system_span"),
        ("System payload before COMMAND", "system_payload"),
        ("System MCB/gap overhead", "system_overhead"),
        ("COMMAND to VC.COM", "command_span"),
        ("VC.COM to conventional free block", "vc_span"),
        ("Unavailable memory below A000h", "ceiling_loss"),
    )
    for label, key in prefix_labels:
        ours = current_prefix[key]
        theirs = retail_prefix[key]
        lines.append(f"| {label} | {ours:,} | {theirs:,} | {ours - theirs:+,} |")
    reconciled_gap = (
        current_prefix["system_span"] - retail_prefix["system_span"]
        + current_prefix["command_span"] - retail_prefix["command_span"]
        + current_prefix["vc_span"] - retail_prefix["vc_span"]
        + current_prefix["ceiling_loss"] - retail_prefix["ceiling_loss"]
    )
    if reconciled_gap != retail_largest - current_largest:
        raise ValueError(
            "VC prefix spans do not reconcile with the largest-block difference: "
            f"{reconciled_gap} != {retail_largest - current_largest}"
        )
    lines.extend([
        "",
        f"The span differences reconcile exactly to the {reconciled_gap:,}-byte gap.",
        "",
    ])

    lines.extend([
        "## Conventional rows from `MEM /D`",
        "",
        "These rows were captured while `MEM` was resident; VC ran only after `MEM`",
        "exited. They describe a different process snapshot and are raw supporting",
        "evidence, not operands to combine directly with VC's grouped totals.",
        "",
    ])
    for label, data in (("Current", current), ("Retail DOS 6.22", retail)):
        lines.extend([
            f"### {label}",
            "",
            "| Segment | Name | Size | Type |",
            "| ---: | --- | ---: | --- |",
        ])
        for row in data["mem_rows"]:
            if row["segment"] < 0xA000:
                lines.append(
                    f"| {row['segment']:04X}h | {row['name']} | {row['size']:,} | {row['type']} |"
                )
        lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("current_image", type=Path)
    parser.add_argument("retail_image", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    require_tools()
    for image in (args.current_image, args.retail_image):
        if not image.is_file():
            parser.error(f"image not found: {image}")

    current_config = image_file(args.current_image, "::CONFIG.SYS").replace(b"\r\n", b"\n")
    retail_config = image_file(args.retail_image, "::CONFIG.SYS").replace(b"\r\n", b"\n")
    if current_config != retail_config:
        raise SystemExit("CONFIG.SYS differs between current and retail images")
    current_vc = image_file(args.current_image, "::VC/VC.COM")
    retail_vc = image_file(args.retail_image, "::VC/VC.COM")
    if current_vc != retail_vc:
        raise SystemExit("VC.COM differs between current and retail images")
    config_hash = hashlib.sha256(current_config).hexdigest()
    vc_hash = hashlib.sha256(current_vc).hexdigest()

    with tempfile.TemporaryDirectory(prefix="msdos-memory-parity-") as temporary:
        directory = Path(temporary)
        ceiling_probe = directory / "CEILING.COM"
        subprocess.run(
            [
                "nasm", "-f", "bin",
                str(ROOT / "tests" / "memory_ceiling_probe.asm"),
                "-o", str(ceiling_probe),
            ],
            check=True,
        )
        current_logs = capture(
            "current", args.current_image.resolve(), directory, ceiling_probe
        )
        retail_logs = capture(
            "retail", args.retail_image.resolve(), directory, ceiling_probe
        )
        output = report(
            parse_capture(*current_logs),
            parse_capture(*retail_logs),
            config_hash,
            vc_hash,
        )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(output + "\n", encoding="utf-8")
    print(output)


if __name__ == "__main__":
    main()
