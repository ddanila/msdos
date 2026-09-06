#!/usr/bin/env python3
"""Qualify administrative revocation on returned INIT exits before preparation."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

import capture_drdos_memory as capture
from capture_emm_init_phases import parse_post_boot
from report_himem_residency import bootstrap_layout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path, help="completed common staged-cancellation fixture")
    args = parser.parse_args()
    base = args.fixture.resolve()
    manifest = json.loads((base / "result.json").read_text())
    modes = ("ON", "OFF", "AUTO", "RAM")
    if (not all(manifest.get(key) for key in ("common_xms_entry", "stage_bootstrap", "rejected"))
            or set(manifest.get("post_boot", {})) != set(modes)
            or capture.sha256(base / "HIMEM.SYS") != manifest["himem_sha256"]):
        raise ValueError("requires a complete matching common cancellation fixture")
    layout = bootstrap_layout(base / "HIMEM.LST", manifest["xms_handles"])
    work = Path(tempfile.mkdtemp(prefix="emm-admin-early-exit-", dir=capture.ROOT / "out"))
    print(f"Evidence: {work}", flush=True)
    results = {}
    for case in ("error", "no-callback", "bound-stage"):
        driver = work / f"{case}.sys"
        subprocess.run(["nasm", "-f", "bin",
                        *(["-DNO_CALLBACK"] if case == "no-callback" else []),
                        *(["-DSTAGED_ABORT"] if case == "bound-stage" else []),
                        str(capture.ROOT / "tests/emm_admin_early_exit.asm"),
                        "-o", str(driver)], check=True)
        for mode in modes:
            stem = f"{case}-{mode}"
            disk = work / f"{stem}.img"
            shutil.copyfile(base / f"{mode}.img", disk)
            capture.install_file(disk, driver, "EMM386.EXE")
            trace = work / f"{stem}.bin"
            with (work / f"{stem}.log").open("wb") as log:
                result = subprocess.run([
                    "qemu-system-i386", *capture.hardware_args(), "-display", "none",
                    "-monitor", "none", "-serial", "stdio", "-no-reboot", "-boot", "a",
                    "-drive", f"if=floppy,format=raw,file={disk}",
                    "-debugcon", f"file:{trace}", "-global", "isa-debugcon.iobase=0xe9",
                    "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"],
                    stdout=log, stderr=subprocess.STDOUT, timeout=35)
            data = trace.read_bytes()
            if case == "bound-stage":
                if result.returncode != 35 or data != b"SBEAAF":
                    raise ValueError(f"unsafe abort was not stopped at cleanup: {stem}: {result.returncode}, {data!r}")
                results[stem] = dict(unsafe_abort_refused=True, boot_stopped=True)
                print(f"PASS: {stem}: refuses to release administration behind a bound stage", flush=True)
                continue
            if result.returncode != 33 or len(data) != 21 or data[:7] != b"EAARUC\1" or data[-4:] != b"DO\0\0":
                raise ValueError(f"early exit did not preserve the local owner: {stem}: {result.returncode}, {data!r}")
            measurement = parse_post_boot(data[7:-4], 0)
            if measurement["himem_bytes"] != layout["linked_boot_end"]:
                raise ValueError("early abort released a still-needed bootstrap allocation")
            results[stem] = measurement
            print(f"PASS: {stem}: administrative storage revoked/overwritten, local HIMEM retained", flush=True)
    (work / "result.json").write_text(json.dumps(dict(fixture=str(base), cases=results), indent=2) + "\n")


if __name__ == "__main__":
    main()
