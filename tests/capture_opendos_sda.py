#!/usr/bin/env python3
"""Query OpenDOS public SDA registers with DOS-data upper placement off/on."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

import capture_drdos_memory as capture


def parse_registers(text):
    records = {}
    for line in text.splitlines():
        match = re.fullmatch(r"SDA_(5D06|5D0B) CF AX DS SI CX DX: "
                             r"((?:[0-9A-F]{4} ){6})", line)
        if match:
            name, values = match.groups()
            if name in records:
                raise ValueError("duplicate SDA record")
            records[name] = dict(zip(("cf", "ax", "ds", "si", "cx", "dx"),
                                     (int(value, 16) for value in values.split())))
    if records.keys() != {"5D06", "5D0B"}:
        raise ValueError("missing SDA records")
    if any(row["cf"] not in (0, 1) for row in records.values()):
        raise ValueError("invalid carry flag")
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("media", type=Path)
    parser.add_argument("reference_disk", type=Path)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--local-image", type=Path,
                        help="optional repository boot floppy; copied, never modified")
    args = parser.parse_args()
    media_hash = capture.sha256(args.media)
    if media_hash != capture.KNOWN_MEDIA_SHA256["Caldera OpenDOS 7.01"]:
        parser.error("OpenDOS media identity mismatch")
    disk_hash = capture.sha256(args.reference_disk)
    local_hash = capture.sha256(args.local_image) if args.local_image else None
    args.evidence.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="opendos-sda-") as directory:
        work = Path(directory)
        base, vc_hash = capture.prepare_opendos(args.media, args.reference_disk, work)
        if vc_hash != capture.KNOWN_VC_SHA256:
            raise ValueError("VC identity mismatch")
        _, qexit, _, _ = capture.build_public_probe(work)
        probe = work / "SDA.COM"
        source = capture.ROOT / "tests/dos_sda_address_probe.asm"
        subprocess.run(["nasm", "-f", "bin", str(source), "-o", str(probe)], check=True)
        records = {}
        for mode in ("OFF", "ON"):
            config, _ = capture.write_startup(
                work, ["DEVICE=EMM386.EXE /FRAME=AUTO", "DOS=HIGH",
                       f"HIDOS={mode}", "HIBUFFERS=15"], [],
                capture.common_settings(files=20, stack_size=128))
            capture.install_file(base, config, "CONFIG.SYS")
            (args.evidence / f"{mode}-CONFIG.SYS").write_bytes(config.read_bytes())
            output = capture.capture_public_interfaces(
                base, mode, work, probe, qexit, args.reference_disk)
            (args.evidence / f"{mode}.txt").write_text(output)
            records[mode] = parse_registers(output)
            print(mode, records[mode], flush=True)
        if args.local_image:
            local_probe = work / "LOCAL-SDA.COM"
            subprocess.run(["nasm", "-f", "bin", "-DLOCAL_SDA_LIVE",
                            str(source), "-o", str(local_probe)], check=True)
            local = work / "local.ima"
            shutil.copyfile(args.local_image, local)
            himem = capture.ROOT / "src/DEV/HIMEM/HIMEM.SYS"
            capture.install_file(local, himem, "HIMEM.SYS")
            for mode in ("LOW", "HIGH"):
                config = work / "local-config.sys"
                config.write_bytes(("DEVICE=HIMEM.SYS\r\n"
                                    f"DOS={mode}\r\nBUFFERS=15\r\n"
                                    "FILES=20\r\nFCBS=4,0\r\nLASTDRIVE=Z\r\n"
                                    "STACKS=9,128\r\n").encode("ascii"))
                capture.install_file(local, config, "CONFIG.SYS")
                label = f"local-{mode}"
                (args.evidence / f"{label}-CONFIG.SYS").write_bytes(config.read_bytes())
                output = capture.capture_public_interfaces(
                    local, label, work, local_probe, qexit, args.reference_disk)
                (args.evidence / f"{label}.txt").write_text(output)
                records[label] = parse_registers(output)
                if ("SDA_LIVE_PASS" in output) == ("SDA_LIVE_FAIL" in output):
                    raise RuntimeError("missing or ambiguous SDA live-state result")
                records[label]["live_psp_dta"] = "SDA_LIVE_PASS" in output
                print(label, records[label], flush=True)
            if capture.sha256(args.local_image) != local_hash:
                raise RuntimeError("local input image changed")
        if capture.sha256(args.reference_disk) != disk_hash:
            raise RuntimeError("reference disk changed")
        result = dict(media_sha256=media_hash, disk_sha256=disk_hash,
                      local_image_sha256=local_hash,
                      probe_sha256=capture.sha256(probe), source_sha256=capture.sha256(source),
                      emulator=capture.qemu_identity(), records=records,
                      scope="public registers only; floppy boot plus snapshot IDE; no save/restore test")
        if args.local_image:
            result["local_himem_sha256"] = capture.sha256(himem)
            result["local_probe_sha256"] = capture.sha256(local_probe)
        (args.evidence / "result.json").write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
