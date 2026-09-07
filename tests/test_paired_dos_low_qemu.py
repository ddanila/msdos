#!/usr/bin/env python3
"""Check paired boot/FCB with explicit, mode-specific diagnostic expectations."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from capture_vc_memory_comparison import image_file
from test_dos_char_retirement_qemu import ROOT, install
from test_command_high_resident_qemu import sha


def low_witness(provider):
    """Change only a pinned boot witness: require no DOS HMA cache, not one.

    Same-size diagnostic variant, not a provider implementation fix. All public
    cached-XMS/ownership checks before and after step 10 remain intact.
    """
    assert hashlib.sha256(provider).hexdigest() == "1004ea0150c50e7dd234199e8931ec1f810d87223a92a04b71ec850658f7944c"
    block = bytes.fromhex("b83412b94d58be010033ffcd2f83f8010f858302"
                          "3b1e6c1c0f857b023b166e1c0f857302")
    assert provider.count(block) == 1
    offset = provider.index(block)
    patched = bytearray(provider)
    patched[offset + 15] = 0  # CMP AX,0: DOS_HMA_REBASE_XMS rejects when hma_owned=0.
    # A rejected cache query has no DX:BX result to compare. Keep its JNE fail.
    patched[offset + 20:offset + 36] = b"\x90" * 16
    return bytes(patched), offset


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--mode", choices=("HIGH", "LOW"), default="LOW")
    parser.add_argument("--low-witness", action="store_true",
                        help="use the pinned same-size DOS-low boot-witness variant")
    parser.add_argument("--expect-witness-failure", action="store_true")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="paired-dos-low-", dir=ROOT / "out"))
    print(f"Evidence: {work}", flush=True)
    disk = work / "boot.img"
    shutil.copyfile(args.image, disk)
    config = image_file(disk, "::CONFIG.SYS")
    assert config.count(b"DOS=HIGH") == 1
    config = config.replace(b"DOS=HIGH", f"DOS={args.mode}".encode())
    (work / "CONFIG.SYS").write_bytes(config)
    install(disk, "CONFIG.SYS", config)
    fcb = work / "I21FCB.COM"
    subprocess.run(["nasm", "-f", "bin", ROOT / "tests/int21_fcb_probe.asm", "-o", fcb], check=True)
    install(disk, "I21FCB.COM", fcb.read_bytes())
    # The FCB probe exits QEMU itself; no batch command after it can be a witness.
    install(disk, "AUTOEXEC.BAT", b"@ECHO OFF\r\nCTTY AUX\r\nECHO PAIRED_DOS_BOOT_READY\r\nI21FCB.COM\r\n")
    provider = image_file(args.image, "::DOS/EMM386.EXE")
    witness_offset = None
    if args.low_witness:
        provider, witness_offset = low_witness(provider)
        install(disk, "DOS/EMM386.EXE", provider)
    for name in ("IO.SYS", "MSDOS.SYS", "COMMAND.COM", "DOS/COMMAND.COM",
                 "DOS/HIMEM.SYS"):
        assert image_file(disk, "::" + name) == image_file(args.image, "::" + name), name
    assert image_file(disk, "::DOS/EMM386.EXE") == provider
    debug = work / "debug.log"
    command = ["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
        "-display", "none", "-monitor", "none", "-serial", "stdio", "-boot", "c", "-no-reboot",
        "-drive", f"if=ide,format=raw,file={disk}", "-debugcon", f"file:{debug}",
        "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"]
    try:
        process = subprocess.run(command, capture_output=True, timeout=40)
        code, output = process.returncode, process.stdout + process.stderr
    except subprocess.TimeoutExpired as error:
        code, output = None, (error.stdout or b"") + (error.stderr or b"")
    (work / "serial.log").write_bytes(output)
    fcb_passed = b"INT21_FCB_PASS" in output
    passed = code == 33 and b"PAIRED_DOS_BOOT_READY" in output and fcb_passed
    trace = debug.read_bytes()
    witness_failed = (code == 35 and trace.endswith(b"XF\x0a")
                      and b"PAIRED_DOS_BOOT_READY" not in output and not fcb_passed)
    result = dict(mode=args.mode, passed=passed, exit_code=code,
                  input_sha256=sha(args.image), image_sha256=sha(disk),
                  low_witness=args.low_witness, witness_offset=witness_offset,
                  provider_sha256=hashlib.sha256(provider).hexdigest(),
                  witness_failed=witness_failed, fcb_passed=fcb_passed, debug_hex=trace.hex())
    (work / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    assert witness_failed if args.expect_witness_failure else passed, result


if __name__ == "__main__":
    main()
