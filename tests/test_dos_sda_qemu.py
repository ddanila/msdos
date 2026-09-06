#!/usr/bin/env python3
"""Check live SDA pointers and both public APIs in private boot images."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

import capture_drdos_memory as capture
from capture_opendos_sda import parse_registers


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, default=capture.ROOT / "out/floppy.img")
    parser.add_argument("--kernel", type=Path, default=capture.ROOT / "src/DOS/MSDOS.SYS")
    parser.add_argument("--preserve-config", action="store_true",
                        help="test an existing development boot configuration unchanged")
    args = parser.parse_args()
    capture.require_tools()
    input_hash = capture.sha256(args.image)
    work = Path(tempfile.mkdtemp(prefix="dos-sda-", dir=capture.ROOT / "out"))
    print(f"Evidence: {work}", flush=True)
    base = work / "base.img"
    shutil.copyfile(args.image, base)
    capture.install_file(base, args.kernel, "MSDOS.SYS")
    himem = capture.ROOT / "src/DEV/HIMEM/HIMEM.SYS"
    if not args.preserve_config:
        capture.install_file(base, himem, "HIMEM.SYS")
    probe, qexit = work / "SDA.COM", work / "QEXIT.COM"
    source = capture.ROOT / "tests/dos_sda_address_probe.asm"
    subprocess.run(["nasm", "-f", "bin", "-DLOCAL_SDA_LIVE",
                    str(source), "-o", str(probe)], check=True)
    subprocess.run(["nasm", "-f", "bin", str(capture.QEMU_EXIT_SOURCE),
                    "-o", str(qexit)], check=True)
    records = {}
    failures = []
    for mode in (["configured"] if args.preserve_config else ["LOW", "HIGH"]):
        if not args.preserve_config:
            config = work / f"{mode}-CONFIG.SYS"
            config.write_bytes((f"DEVICE=HIMEM.SYS\r\nDOS={mode}\r\n"
                                "BUFFERS=15\r\nFILES=20\r\nFCBS=4,0\r\n"
                                "LASTDRIVE=Z\r\nSTACKS=9,128\r\n").encode("ascii"))
            capture.install_file(base, config, "CONFIG.SYS")
        else:
            capture.image_copy(base, "CONFIG.SYS", work / "configured-CONFIG.SYS")
        output = capture.capture_public_interfaces(base, mode, work, probe, qexit)
        (work / f"{mode}.txt").write_text(output)
        rows = parse_registers(output)
        passed = (all(row["cf"] == 0 for row in rows.values())
                  and rows["5D06"]["ds"] != 0xFFFF
                  and "SDA_LIVE_PASS" in output and "SDA_TABLE_PASS" in output
                  and "SDA_LIVE_FAIL" not in output and "SDA_TABLE_FAIL" not in output)
        records[mode] = dict(registers=rows, passed=passed)
        print(f"{'PASS' if passed else 'FAIL'} {mode}: {rows}", flush=True)
        if not passed:
            failures.append(mode)
    if capture.sha256(args.image) != input_hash:
        raise RuntimeError("input image changed")
    (work / "result.json").write_text(json.dumps(dict(
        input_sha256=input_hash, kernel_sha256=capture.sha256(args.kernel),
        probe_sha256=capture.sha256(probe), emulator=capture.qemu_identity(),
        records=records), indent=2) + "\n")
    if failures:
        raise SystemExit("SDA ownership failed: " + ", ".join(failures))


if __name__ == "__main__":
    main()
