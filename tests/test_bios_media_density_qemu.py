#!/usr/bin/env python3
"""Qualify density fallback or extended IDs in a pinned retired-media fixture."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path,
                        help="completed test_bios_clock_callback_qemu.py --pack-headers --retire-media output")
    parser.add_argument("--extended-bpb", action="store_true", help="test requested, classic and unrequested volume IDs")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="bios-media-density-", dir=ROOT / "out"))
    print(f"Evidence: {work}", flush=True)
    layout = work / "layout.bin"
    subprocess.run([ROOT / "bin/jwasm-bin", f"-I{ROOT / 'src/INC'}", f"-Fo{layout}",
                    ROOT / "tests/bios_media_layout.asm"], check=True, capture_output=True)
    names = ("SIZE", "BYTEPERSEC", "SECPERCLUS", "RESSEC", "CFAT", "CDIR", "DRVLIM",
             "MEDIAD", "CSECFAT", "SECLIM", "HDLIM", "HIDSEC_L", "HIDSEC_H", "DRVLIM_H",
             "FLAGS", "FORMFACTOR", "FCHANGELINE", "FF96TPI", "VOL_SERIAL", "VOLID", "FILESYS_ID")
    fields = dict(zip(names, struct.unpack(f"<{len(names)}H", layout.read_bytes())))
    proof = json.loads((args.fixture / "results.json").read_text())
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")
    results = {}
    parents = (("fallback", False, False), ("high-poisoned", True, False), ("high-compacted", True, True))
    modes = (("extended", 1), ("classic", 2), ("unrequested", 3)) if args.extended_bpb else (("density", 0),)
    cases = [(parent + "-" + mode, parent, active, compact, False, id_mode)
             for parent, active, compact in parents for mode, id_mode in modes]
    cases.append(("missing-id-copy" if args.extended_bpb else "missing-unwind",
                  "high-poisoned", True, False, True, 1 if args.extended_bpb else 0))
    for name, parent, active, compact, omit, id_mode in cases:
        source = args.fixture / parent
        low = json.loads((source / "low.json").read_text())
        high = json.loads((source / "high/bios-high.json").read_text())
        original_image = source / "boot.img"
        if not (low.get("retired_media_bodies") and high.get("media")
                and proof[parent]["successful_callback"]
                and hashlib.sha256(original_image.read_bytes()).hexdigest() == proof[parent]["image_sha256"]
                and hashlib.sha256((source / "IO.SYS").read_bytes()).hexdigest() == high["low_image_sha256"] == low["sha256"]):
            raise ValueError(f"incomplete or changed media fixture: {source}")
        symbols, exports = low["symbols"], high["exports"]
        payload = (source / "high/bios-high.bin").read_bytes()
        if hashlib.sha256(payload).hexdigest() != high["sha256"] or payload not in (source / "IO.SYS").read_bytes():
            raise ValueError("high payload does not match the embedded image")
        start, end = exports["HIDENSITY"], exports["BIOS_MEDIA_SERVICE_END"]
        if payload[start:end].count(b"\x83\xc4\x02") != 1:
            raise ValueError("density helper must contain exactly one ADD SP,2")
        unwind = payload.index(b"\x83\xc4\x02", start, end)
        patch_offset = exports["GETBP1_PATCH"] if active else symbols["GETBP1_PATCH"]
        patch_image = payload if active else (source / "MSBIO.BIN").read_bytes()
        if patch_image[patch_offset] != 0xe8:
            raise ValueError("expected original near density call")
        directory = work / name
        directory.mkdir()
        definitions = {"B_" + key: value for key, value in fields.items()}
        definitions.update(ACTIVE=symbols["BIOS_SERVICE_ACTIVE"], EXPECT_ACTIVE=int(active),
                           EXPECT_POISON=int(active and not compact), OLD_START=symbols["CON$READ"],
                           OLD_SIZE=symbols["BIOS_SERVICE_END"]-symbols["CON$READ"],
                           GETBP_ENTRY=symbols["GETBP"], HIGH_GETBP=symbols["BIOS_HIGH_GETBP"],
                           HIGH_GETBP_OFFSET=exports["GETBP"], HIGH_UNWIND_OFFSET=unwind,
                           OMIT_UNWIND=int(omit and not id_mode), OMIT_ID_COPY=int(omit and bool(id_mode)),
                           ID_MODE=id_mode, EXPECTED_READS=1 if id_mode else 2,
                           ID_FLAG=symbols["SET_ID_FLAG"],
                           EXPECTED_ID_FLAG=2 if id_mode == 1 else 1 if id_mode == 2 else 0,
                           HIGH_ID_COPY_OFFSET=exports["MOV_MEDIA_IDS"], ID_COPY_OPCODE=payload[exports["MOV_MEDIA_IDS"]],
                           EXT_SIGNATURE=0 if id_mode == 2 else 0x29,
                           SECTOR_SIGNATURE=symbols["EXT_BOOT_SIG"]-symbols["DISKSECTOR"],
                           SECTOR_SERIAL=symbols["BOOT_SERIAL_L"]-symbols["DISKSECTOR"],
                           SECTOR_LABEL=symbols["BOOT_VOLUME_LABEL"]-symbols["DISKSECTOR"],
                           SECTOR_FILESYSTEM=symbols["BOOT_SYSTEM_ID"]-symbols["DISKSECTOR"],
                           PATCH_OFFSET=patch_offset,
                           PATCH_DISPLACEMENT=int.from_bytes(patch_image[patch_offset+1:patch_offset+3], "little"))
        (directory / "media-defs.inc").write_text("".join(f"{k} equ {v}\n" for k, v in definitions.items()))
        probe = directory / "DENSITY.COM"
        subprocess.run(["nasm", "-f", "bin", f"-I{directory}/", ROOT / "tests/bios_media_density.asm",
                        "-o", probe], check=True)
        image = directory / "boot.img"
        shutil.copyfile(original_image, image)
        autoexec = directory / "AUTOEXEC.BAT"
        autoexec.write_bytes(b"@ECHO OFF\r\nDENSITY.COM\r\n")
        for path in (probe, autoexec):
            subprocess.run(["mcopy", "-o", "-i", image, path, "::" + path.name], env=env, check=True)
        debug = directory / "debug.bin"
        command = ["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
                   "-display", "none", "-monitor", "none", "-serial", "none", "-no-reboot",
                   "-drive", f"if=floppy,format=raw,file={image}", "-boot", "a",
                   "-debugcon", f"file:{debug}", "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"]
        try:
            result = subprocess.run(command, capture_output=True, timeout=20)
            code, output = result.returncode, result.stdout + result.stderr
        except subprocess.TimeoutExpired as error:
            code, output = None, (error.stdout or b"") + (error.stderr or b"")
        (directory / "qemu.log").write_bytes(output)
        trace = debug.read_bytes() if debug.exists() else b""
        expected = b"BD1" if id_mode else b"BD12"
        if omit and id_mode:
            passed = trace == expected + b"\x20" and code == 35
        elif omit:
            passed = trace == expected and code != 33
        else:
            passed = trace == expected + b"P" and code == 33
        results[name] = dict(passed=passed, exit_code=code, trace=trace.hex(), negative_control=omit,
                             id_mode=id_mode, density_call_forced=not bool(id_mode),
                             emulator=subprocess.check_output(["qemu-system-i386", "--version"], text=True).splitlines()[0],
                             command=command, inputs={str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                                                      for p in (image, probe, source / "low.json", source / "high/bios-high.json",
                                                                Path(__file__), ROOT / "tests/bios_media_density.asm",
                                                                ROOT / "tests/bios_media_layout.asm")})
        (work / "results.json").write_text(json.dumps(results, indent=2) + "\n")
        if not passed:
            raise RuntimeError(f"density result: {name}: exit={code}, trace={trace!r}")
        print(f"PASS {name}", flush=True)


if __name__ == "__main__":
    main()
