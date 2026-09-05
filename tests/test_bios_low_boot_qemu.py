#!/usr/bin/env python3
"""Boot the combined inactive BIOS in low/high and standalone/EMM configurations."""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from build_bios_low_image import ROOT, build, run
from build_bios_high_payload import build as build_high


def main():
    scratch = Path(tempfile.mkdtemp(prefix="bios-low-boot-", dir=ROOT / "out"))
    manifest = build(scratch)
    high_manifest = build_high(scratch / "high", scratch)
    if high_manifest["low_image_sha256"] != manifest["sha256"]:
        raise RuntimeError("high payload was bound against a different low BIOS")
    # Every named low gate/helper imported by the high payload now exists in
    # this combined image. The owner segment is supplied by the future loader.
    for slot in high_manifest["runtime_slots"].values():
        if slot["target"] != "resident low BIOS segment":
            if slot["target"].upper() not in manifest["symbols"]:
                raise RuntimeError(f"missing production low binding: {slot['target']}")
    (scratch / "low-defs.inc").write_text(
        f"ACTIVE_OFFSET equ {manifest['symbols']['BIOS_SERVICE_ACTIVE']}\n"
        f"SLOT_WORD_COUNT equ {len(manifest['high_slot_words'])}\n")
    (scratch / "low-slots.inc").write_text(
        "dw " + ",".join(map(str, manifest["high_slot_words"])) + "\n")
    variants = {
        "bare-low": (False, "DOS=LOW\r\n"),
        "himem-low": (False, "DEVICE=HIMEM.SYS /TESTMEM:OFF\r\nDOS=LOW\r\n"),
        "himem-high": (True, "DEVICE=HIMEM.SYS /TESTMEM:OFF\r\nDOS=HIGH\r\n"),
        "emm-high": (True, "DEVICE=HIMEM.SYS /TESTMEM:OFF\r\n"
                     "DEVICE=EMM386.EXE RAM\r\nDOS=HIGH,UMB\r\n"),
    }
    env = {**os.environ, "MTOOLS_SKIP_CHECK": "1"}
    for name, (high, config) in variants.items():
        probe = scratch / f"{name}.com"
        run(["nasm", "-f", "bin", f"-I{scratch}/", f"-DEXPECT_HIGH={int(high)}",
             ROOT / "tests/bios_low_boot_probe.asm", "-o", probe], ROOT)
        image = scratch / f"{name}.img"
        shutil.copyfile(ROOT / "out/floppy.img", image)
        for source, destination in ((scratch / "IO.SYS", "IO.SYS"), (probe, "LOWBOOT.COM")):
            subprocess.run(["mcopy", "-o", "-i", str(image), str(source), f"::{destination}"],
                           env=env, check=True)
        for destination, text in (("CONFIG.SYS", config), ("AUTOEXEC.BAT",
                                  "@ECHO OFF\r\nCTTY AUX\r\nLOWBOOT.COM\r\n")):
            subprocess.run(["mcopy", "-o", "-i", str(image), "-", f"::{destination}"],
                           input=text.encode(), env=env, check=True)
        log = scratch / f"{name}.log"
        with log.open("wb") as stream:
            try:
                subprocess.run(["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
                                "-display", "none", "-monitor", "none", "-serial", "stdio",
                                "-boot", "a", "-no-reboot", "-device",
                                "isa-debug-exit,iobase=0xf4,iosize=0x04", "-drive",
                                f"if=floppy,index=0,format=raw,file={image},cache=writethrough"],
                               stdout=stream, stderr=subprocess.STDOUT, timeout=35)
            except subprocess.TimeoutExpired:
                pass
        result = log.read_bytes()
        if b"BIOS_LOW_BOOT_PASS" not in result or b"BIOS_LOW_BOOT_FAIL" in result:
            raise RuntimeError(f"FAIL {name}: {log}\n{result.decode(errors='replace')}")
        print(f"PASS {name}: {log}", flush=True)


if __name__ == "__main__":
    main()
