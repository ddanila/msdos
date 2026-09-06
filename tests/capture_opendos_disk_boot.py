#!/usr/bin/env python3
"""Cold disk-boot placement control using vendor SYS, never vendor source."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

import capture_drdos_memory as capture


def disk_spec(image: Path) -> str:
    offset = capture.partition_offset(image)
    if offset < 512 or offset >= image.stat().st_size:
        raise ValueError("invalid first-partition offset")
    return f"{image}@@{offset}"


def read_file(spec: str, name: str) -> bytes:
    return subprocess.check_output(["mtype", "-i", spec, f"::{name}"],
                                   env=capture.mtools_env())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("media", type=Path)
    parser.add_argument("template", type=Path, help="reference HDD with VC 4.05 in C:\\VC; read-only input")
    parser.add_argument("evidence", type=Path, help="new directory for text evidence only")
    args = parser.parse_args()
    media_hash = capture.sha256(args.media)
    if media_hash != capture.KNOWN_MEDIA_SHA256["Caldera OpenDOS 7.01"]:
        parser.error("OpenDOS distribution identity mismatch")
    template_hash = capture.sha256(args.template)
    args.evidence.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="opendos-disk-") as temporary:
        work = Path(temporary)
        floppy, vc_hash = capture.prepare_opendos(args.media, args.template, work)
        if vc_hash != capture.KNOWN_VC_SHA256:
            raise ValueError("VC identity mismatch")
        _, qexit, _, _ = capture.build_public_probe(work)
        capture.install_file(floppy, qexit, "QEXIT.COM")
        disk = work / "disk.img"
        shutil.copyfile(args.template, disk)
        spec = disk_spec(disk)
        config = work / "CONFIG.SYS"
        config.write_bytes(b"DOS=LOW\r\n")
        autoexec = work / "AUTOEXEC.BAT"
        autoexec.write_bytes(b"@ECHO OFF\r\nSYS C: > SYSLOG.TXT\r\nQEXIT.COM\r\n")
        capture.install_file(floppy, config, "CONFIG.SYS")
        capture.install_file(floppy, autoexec, "AUTOEXEC.BAT")
        with (args.evidence / "install-stderr.txt").open("w") as log:
            result = subprocess.run([
                "qemu-system-i386", "-display", "none", "-monitor", "none",
                *capture.hardware_args(), "-boot", "a", "-no-reboot",
                "-drive", f"if=floppy,index=0,format=raw,file={floppy}",
                "-drive", f"if=ide,index=0,format=raw,file={disk}",
                "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"],
                stdout=log, stderr=log, timeout=35)
        syslog = read_file(str(floppy), "SYSLOG.TXT")
        (args.evidence / "sys.txt").write_text(syslog.decode("cp437"))
        if result.returncode != 33:
            raise RuntimeError("vendor SYS boot did not reach the exit probe")
        system_hashes = {}
        for name in ("IBMBIO.COM", "IBMDOS.COM", "COMMAND.COM"):
            original = read_file(str(floppy), name)
            installed = read_file(spec, name)
            if original != installed:
                raise ValueError(f"vendor SYS did not install exact {name}")
            system_hashes[name] = hashlib.sha256(installed).hexdigest()
        # Use exactly the framed topology-control settings, changing boot media.
        for name in ("EMM386.EXE", "MEM.EXE", "MEMMAX.COM", "VC.COM", "CEILING.COM"):
            source = work / name
            capture.image_copy(floppy, name, source)
            capture.install_file(Path(spec), source, name)
        common = capture.common_settings(files=20, stack_size=128, environment=512)
        config, autoexec = capture.write_startup(work, capture.OPENDOS_VARIANTS["emm-frame"], [], common)
        for source in (config, autoexec):
            capture.install_file(Path(spec), source, source.name)
            shutil.copyfile(source, args.evidence / source.name)
        screen, mem, ceiling = capture.capture(disk, "disk-boot", work, boot_disk=True)
        shutil.copyfile(screen, args.evidence / "vc.txt")
        (args.evidence / "mem.txt").write_text(mem)
        (args.evidence / "ceiling.txt").write_text(ceiling)
        data = capture.parse(screen, mem, ceiling)
        data.update(media_sha256=media_hash, template_sha256=template_hash,
                    vc_sha256=vc_hash, system_sha256=system_hashes,
                    emulator=capture.qemu_identity(), boot="IDE C:; no floppy media attached",
                    qualification="cold placement only; no reset/public-interface gate")
        if capture.sha256(args.template) != template_hash:
            raise RuntimeError("reference disk changed")
        (args.evidence / "result.json").write_text(json.dumps(data, indent=2) + "\n")
        print(json.dumps({key: data[key] for key in
                          ("largest", "system_span", "command_span", "upper_free", "hma_free")}, indent=2))


if __name__ == "__main__":
    main()
