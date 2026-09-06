#!/usr/bin/env python3
"""Execute the actual development Ctrl+C entry with distinct low owners."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, default=ROOT / "out/floppy.img")
    parser.add_argument("--wrong-owner", action="store_true")
    parser.add_argument("--wrong-pipe-owner", action="store_true")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="command-contc-entry-", dir=ROOT / "out"))
    print(f"Evidence: {work}", flush=True)
    source = ROOT / "src/CMD/COMMAND/COMMAND1.ASM"
    matches = re.findall(r"(?ims)^CONTC\s+PROC\s+FAR\b.*?^ASSUME\s+DS:RESGROUP", source.read_text())
    if len(matches) != 1:
        raise ValueError("expected one complete CONTC decision/owner-selection entry")
    (work / "CONTC_ENTRY.INC").write_text(matches[0] + "\n")
    pipe = re.findall(r"(?ims)^ResPipeOff:.*?(?=^CODERES\s+ENDS)", source.read_text())
    if len(pipe) != 1:
        raise ValueError("expected one complete ResPipeOff procedure")
    (work / "PIPEOFF.INC").write_text(pipe[0] + "\n")
    equates = (ROOT / "src/CMD/COMMAND/comequ.asm").read_text()
    flags = []
    for name in ("initINIT", "initSpecial", "initCtrlC"):
        found = re.findall(rf"(?im)^{name}\s+equ\s+[^;\r\n]+", equates)
        if len(found) != 1:
            raise ValueError(f"expected one {name} definition")
        flags.append(found[0])
    (work / "CONTC_FLAGS.INC").write_text("\n".join(flags) + "\n")
    shutil.copyfile(ROOT / "src/CMD/COMMAND/RESBIND.INC", work / "RESBIND.INC")
    shutil.copyfile(ROOT / "tests/command_contc_entry_masm.asm", work / "probe.asm")

    def run(*cmd, **kwargs):
        return subprocess.run([str(arg) for arg in cmd], check=True, **kwargs)

    flags = "-I. -DWRONG_OWNER" if args.wrong_owner else "-I."
    if args.wrong_pipe_owner:
        flags += " -DWRONG_PIPE_OWNER"
    run(ROOT / "bin/jwasm-masm", flags, "probe.asm,probe.obj;", cwd=work)
    run(ROOT / "bin/wlink", "probe.obj,probe.exe,probe.map;", cwd=work)
    run(ROOT / "bin/exe2bin", "probe.exe", "probe.com", cwd=work)
    image = work / "boot.img"
    shutil.copyfile(args.image, image)
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")
    run("mcopy", "-o", "-i", image, work / "probe.com", "::PROBE.COM", env=env)
    for name, data in (("CONFIG.SYS", "FILES=20\r\n"),
                       ("AUTOEXEC.BAT", "@ECHO OFF\r\nPROBE.COM\r\n")):
        run("mcopy", "-o", "-i", image, "-", "::" + name, input=data.encode(), env=env)
    debug = work / "debug.bin"
    result = subprocess.run([
        "qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
        "-display", "none", "-monitor", "none", "-serial", "none",
        "-drive", f"if=floppy,format=raw,file={image}", "-boot", "a", "-no-reboot",
        "-debugcon", f"file:{debug}", "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04",
    ], timeout=30, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (work / "qemu.log").write_bytes(result.stdout)
    trace = debug.read_bytes()
    passed = result.returncode == 33 and trace == b"CCCCCCCPP"
    record = {"passed": passed, "wrong_owner": args.wrong_owner,
              "wrong_pipe_owner": args.wrong_pipe_owner,
              "exit": result.returncode, "trace": trace.decode("ascii", errors="replace"),
              "qemu": run("qemu-system-i386", "--version", capture_output=True, text=True).stdout.splitlines()[0],
              "sha256": {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                         for path in (source, work / "RESBIND.INC", work / "probe.asm",
                                      work / "CONTC_ENTRY.INC", work / "CONTC_FLAGS.INC",
                                      work / "PIPEOFF.INC",
                                      work / "probe.com", args.image)}}
    (work / "result.json").write_text(json.dumps(record, indent=2) + "\n")
    if not passed:
        raise ValueError(f"CONTC entry failed: exit={result.returncode}, trace={trace!r}")
    print("PASS: seven CONTC paths and two pipeline cleanup cases with separate DS owners")


if __name__ == "__main__":
    main()
