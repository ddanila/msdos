#!/usr/bin/env python3
"""Development partial-UMB installation, I/O, accounting and rollback gates."""

import argparse
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import tempfile
import time
from capture_uma_topology import QMP
from test_umb_subpage_discovery_qemu import ROOT, build, run


def reset_capture(command, serial, endpoint):
    with serial.open("wb") as stream:
        process = subprocess.Popen(command + ["-qmp", f"unix:{endpoint},server=on,wait=off"],
                                   stdout=stream, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 35
            while b"UMB_FINE_RESET_READY" not in serial.read_bytes():
                if process.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError(f"guest failed before reset: {serial}")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as connection:
                connection.connect(str(endpoint))
                qmp = QMP(connection)
                qmp.call("system_reset")
            process.wait(timeout=35)
            return process.returncode, serial.read_bytes()
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--warm-reset", action="store_true")
    args = parser.parse_args()
    boots = 2 if args.warm_reset else 1
    work = Path(tempfile.mkdtemp(prefix="umb-fine-mapping-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")
    for source, output, flags in (
        ("umb_subpage_probe.asm", "SUBPAGE.COM", []),
        ("umb_file_read_probe.asm", "UMBREAD.COM", ["-DEXPECT_HIGH=1", "-DEMS_IO", "-DTARGET_KIB=12"]),
        ("qemu_exit.asm", "QEXIT.COM", []),
    ):
        run(["nasm", "-I" + str(ROOT / "tests") + "/", "-f", "bin", *flags,
             ROOT / "tests" / source, "-o", work / output])
    baseline = None
    for name, extra, mapped in (
        ("coarse", None, False),
        ("fine", "", True),
        ("reverse", "-DUMB_TEST_REVERSE_FREE", True),
        ("after-one", "-DUMB_SUBPAGE_FAIL_AFTER_MAP=1", False),
        ("after-three", "-DUMB_SUBPAGE_FAIL_AFTER_MAP=3", False),
        ("before-publish", "-DUMB_SUBPAGE_FAIL_BEFORE_PUBLISH", False),
    ):
        binary = build(work / name, extra is not None,
                       "-DUMB_SUBPAGE_MAPPING " + extra if extra is not None else "")
        if extra is None:
            assert binary.read_bytes() == (ROOT / "src/MEMM/MEMM/EMM386.EXE").read_bytes()
        image = work / f"{name}.img"
        shutil.copyfile(ROOT / "out/floppy.img", image)
        for source, dest in [(binary, "EMM386.EXE")] + [(work / n, n) for n in ("SUBPAGE.COM", "UMBREAD.COM", "QEXIT.COM")]:
            run(["mcopy", "-o", "-i", image, source, "::" + dest], env=env)
        finish = "QEXIT.COM\r\n"
        if args.warm_reset:
            finish = ("IF EXIST RESET.OK GOTO DONE\r\nECHO X>RESET.OK\r\n"
                      "SUBPAGE.COM /FLUSH\r\nECHO UMB_FINE_RESET_READY\r\n"
                      ":WAIT\r\nGOTO WAIT\r\n:DONE\r\nQEXIT.COM\r\n")
        for filename, contents in {
            "CONFIG.SYS": "DEVICE=HIMEM.SYS /TESTMEM:OFF\r\nDEVICE=EMM386.EXE RAM M5\r\nDOS=HIGH,UMB\r\n",
            "AUTOEXEC.BAT": "@ECHO OFF\r\nCTTY AUX\r\nSUBPAGE.COM\r\nUMBREAD.COM\r\nSUBPAGE.COM\r\n" + finish,
        }.items():
            run(["mcopy", "-o", "-i", image, "-", "::" + filename], input=contents.encode(), env=env)
        debug = work / f"{name}-debug.log"
        command = [
            "qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
            "-display", "none", "-monitor", "none", "-serial", "stdio",
            "-drive", f"if=floppy,index=0,format=raw,file={image},cache=writethrough",
            "-boot", "a", "-debugcon", f"file:{debug}",
            "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"]
        serial = work / f"{name}-serial.log"
        if args.warm_reset:
            code, log = reset_capture(command, serial, work / f"{name}.qmp")
        else:
            result = subprocess.run(command + ["-no-reboot"], stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=45)
            code, log = result.returncode, result.stdout
            serial.write_bytes(log)
        assert code == 33, (name, code, log)
        assert b"FAIL" not in log and b"Error in CONFIG" not in log, (name, log)
        assert log.count(b"UMB_SUBPAGE_PROBE_PASS") == 2 * boots, (name, log)
        for marker in (b"UMB_FILE_READ_PASS", b"UMB_EMS_IO_PASS", b"DMA_PROGRAM_PHASE_PASS"):
            assert log.count(marker) == boots, (name, marker, log)
        values = {}
        for field in ("FREE_PARAS", "EMS_FREE", "EMS_TOTAL", "ROM_HASH"):
            captures = re.findall(rb"UMB_SUBPAGE_" + field.encode() + rb"=([0-9A-F]{4})", log)
            assert len(captures) == 2 * boots, (name, field, captures)
            if args.warm_reset:
                assert captures[:2] == captures[2:], (name, field, captures)
            if field != "FREE_PARAS":
                assert captures[0] == captures[1], (name, field, captures)
            values[field] = tuple(int(value, 16) for value in captures)
        assert re.findall(rb"UMB_READ_TARGET=([0-9A-F]{4})", log) == [b"CB01" if mapped else b"CC01"] * boots, (name, log)
        if baseline is None:
            baseline = values
        else:
            assert values["ROM_HASH"] == baseline["ROM_HASH"], (name, values, baseline)
            assert values["EMS_TOTAL"] == baseline["EMS_TOTAL"], (name, values, baseline)
            assert values["EMS_FREE"] == tuple(x - int(mapped) for x in baseline["EMS_FREE"]), (name, values, baseline)
            assert values["FREE_PARAS"] == tuple(x + 0x100 * int(mapped) for x in baseline["FREE_PARAS"]), (name, values, baseline)
        if extra and not mapped:
            assert debug.read_bytes().count(b"R") == boots, (name, debug.read_bytes())
        print(f"PASS {name}: {values}", flush=True)


if __name__ == "__main__":
    main()
