#!/usr/bin/env python3
"""Load CP866 through DISPLAY/MODE; compare actual VGA plane bytes and capture screens."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

from screen_expect import QMPConnection
from test_ru_cpi import CPI, ROOT, check_glyphs, parse_cpi


def run(*args, **kwargs):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)


def existing_font(page, height):
    source = ROOT / f"src/DEV/DISPLAY/EGA/{page}-8X{height}.ASM"
    values = []
    for line in source.read_bytes().decode("latin1").splitlines():
        if re.match(r"\s*db\b", line, re.I):
            values.extend(int(x, 16) for x in re.findall(r"\b([0-9a-f]+)h\b", line.split(";")[0], re.I))
    if len(values) != 256 * height:
        raise AssertionError(f"unexpected existing font length: {source}")
    return [bytes(values[i * height:(i + 1) * height]) for i in range(256)]


def run_case(work, base, page, height, expected, corrupt=False):
    case = work / f"{page}-{height}{'-corrupt' if corrupt else ''}"
    case.mkdir()
    image = case / "boot.img"
    shutil.copyfile(base, image)
    def copy(source, target):
        run("mcopy", "-o", "-i", str(image), str(source), f"::{target}")
    for name, defines in [("SETH.COM", ["-DSETUP_ONLY"]), ("PROBE.COM", [])]:
        output = case / name
        run("nasm", "-f", "bin", f"-DHEIGHT={height}", f"-DPAGE={page}", *defines,
            str(ROOT / "tests/ru_font_probe.asm"), "-o", str(output))
        copy(output, name)
    run("nasm", "-f", "bin", str(ROOT / "tests/qemu_exit.asm"), "-o", str(case / "QEXIT.COM"))
    copy(case / "QEXIT.COM", "QEXIT.COM")
    source = CPI if page == 866 else CPI.with_name("EGA.CPI")
    if corrupt:
        data = bytearray(source.read_bytes())
        # CP866/16-row yo slot: wrong glyph byte, with all CPI structures intact.
        data[59 + 6 + 0xf1 * 16] ^= 0x80
        source = case / "CORRUPT.CPI"
        source.write_bytes(data)
    copy(source, "TEST.CPI")
    copy(ROOT / "src/DEV/DISPLAY/DISPLAY.SYS", "DISPLAY.SYS")
    copy(ROOT / "src/CMD/MODE/MODE.COM", "MODE.COM")
    config = b"DEVICE=DISPLAY.SYS CON=(EGA,437,(1,3))\r\n"
    autoexec = ("@ECHO OFF\r\nCTTY AUX\r\n"
                f"MODE CON CP PREPARE=(({page}) A:\\TEST.CPI)\r\n"
                "IF ERRORLEVEL 1 GOTO FAIL\r\nSETH.COM\r\n"
                f"MODE CON CP SELECT={page}\r\n"
                "IF ERRORLEVEL 1 GOTO FAIL\r\nPROBE.COM\r\n"
                "IF ERRORLEVEL 1 GOTO FAIL\r\nECHO RU_DISPLAY_DONE\r\nQEXIT.COM\r\n"
                ":FAIL\r\nECHO RU_DISPLAY_FAIL\r\nQEXIT.COM\r\n").encode()
    for name, data in [("CONFIG.SYS", config), ("AUTOEXEC.BAT", autoexec)]:
        run("mcopy", "-o", "-i", str(image), "-", f"::{name}", input=data)
    serial = case / "serial.log"
    with tempfile.TemporaryDirectory(prefix="ru-qmp-") as sockets, (case / "qemu.log").open("wb") as log:
        sock = Path(sockets) / "qmp"
        command = [os.environ.get("QEMU", "qemu-system-i386"), "-display", "none", "-m", "4",
                   "-drive", f"if=floppy,index=0,format=raw,file={image},cache=writethrough",
                   "-boot", "a", "-serial", f"file:{serial}", "-qmp", f"unix:{sock},server=on,wait=off",
                   "-no-reboot", "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"]
        process = subprocess.Popen(command, stdout=log, stderr=log, stdin=subprocess.DEVNULL)
        qmp = None
        try:
            qmp = QMPConnection(str(sock))
            deadline = time.monotonic() + 30
            while True:
                output = serial.read_bytes() if serial.exists() else b""
                if b"RU_FONT_READY" in output:
                    break
                if process.poll() is not None or time.monotonic() > deadline:
                    raise AssertionError(f"guest did not reach font capture: {case}\n{output!r}")
                time.sleep(0.05)
            qmp.human_cmd(f'screendump "{case / "screen.ppm"}"')
            screen = case / "screen.ppm"
            if not screen.exists() or screen.stat().st_size < 1000:
                raise AssertionError("missing QEMU screenshot")
            qmp.send_key("ret")
            status = process.wait(timeout=10)
            output = serial.read_bytes()
            if status != 33 or b"RU_FONT_PASS" not in output or b"RU_DISPLAY_DONE" not in output or b"FAIL" in output:
                raise AssertionError(f"guest completion/exit failed: {status}, {output!r}")
        finally:
            if qmp:
                qmp.close()
            if process.poll() is None:
                process.kill()
                process.wait()
    actual = run("mtype", "-i", str(image), "::FONT.BIN").stdout
    (case / "font-plane.bin").write_bytes(actual)
    if len(actual) != 8192:
        raise AssertionError("incomplete VGA font-plane read")
    mismatches = [byte for byte in range(256) if actual[byte * 32:byte * 32 + height] != expected[byte]]
    if corrupt:
        if mismatches != [0xf1]:
            raise AssertionError(f"wrong-slot control did not isolate yo: {mismatches}")
    elif mismatches:
        raise AssertionError(f"VGA font bytes differ at {page}/{height}: {mismatches}; artifacts: {case}")
    result = {"page": page, "height": height, "emulator_exit": status,
              "guest_completion": True, "mismatched_slots": mismatches,
              "negative_control": corrupt, "font_plane_sha256": hashlib.sha256(actual).hexdigest(),
              "screen": str(screen.relative_to(work)),
              "screen_sha256": hashlib.sha256(screen.read_bytes()).hexdigest()}
    print(f"PASS: {page} / 8x{height}" + (" wrong-slot control detected" if corrupt else " VGA bytes and guest completion"), flush=True)
    return result


def main():
    base = Path(os.environ.get("FLOPPY_IMAGE", ROOT / "out/floppy.img"))
    if not base.is_file():
        raise SystemExit("build and deploy the base image first")
    work = Path(tempfile.mkdtemp(prefix="ru-display-", dir=ROOT / "out"))
    print(f"Russian display artifacts: {work}", flush=True)
    fonts = parse_cpi(CPI.read_bytes())
    check_glyphs(fonts)
    results = [run_case(work, base, 866, height, fonts[height]) for height in (16, 14, 8)]
    results.extend(run_case(work, base, page, 16, existing_font(page, 16))
                   for page in (437, 850, 860, 863, 865))
    results.append(run_case(work, base, 866, 16, fonts[16], corrupt=True))
    (work / "results.json").write_text(json.dumps({"schema_version": 1,
        "base_image_sha256": hashlib.sha256(base.read_bytes()).hexdigest(),
        "cpi_sha256": hashlib.sha256(CPI.read_bytes()).hexdigest(), "cases": results}, indent=2) + "\n")


if __name__ == "__main__":
    main()
