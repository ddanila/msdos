#!/usr/bin/env python3
"""Separate repeated probes, disk-persistent batch state and QMP reset effects."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

import capture_drdos_memory as capture


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("media", type=Path)
    parser.add_argument("reference_disk", type=Path)
    parser.add_argument("evidence", type=Path, help="new text-only evidence directory")
    args = parser.parse_args()
    media_hash = capture.sha256(args.media)
    if media_hash != capture.KNOWN_MEDIA_SHA256["Caldera OpenDOS 7.01"]:
        parser.error("OpenDOS media identity mismatch")
    disk_hash = capture.sha256(args.reference_disk)
    args.evidence.mkdir(parents=True, exist_ok=False)
    results = {}
    with tempfile.TemporaryDirectory(prefix="od-reset-control-") as temporary:
        work = Path(temporary)
        base, vc_hash = capture.prepare_opendos(args.media, args.reference_disk, work)
        if vc_hash != capture.KNOWN_VC_SHA256:
            raise ValueError("VC identity mismatch")
        probe, qexit, warmboot, probe_hash = capture.build_public_probe(work)
        config, _ = capture.write_startup(work, capture.OPENDOS_VARIANTS["emm-frame"], [],
                                         capture.common_settings(files=20, stack_size=128))
        capture.install_file(base, config, "CONFIG.SYS")
        (args.evidence / "CONFIG.SYS").write_bytes(config.read_bytes())
        for mode in ("none", "cold", "reset"):
            before, after = capture.capture_warm_public_interfaces(
                base, mode, work, probe, qexit, warmboot, args.reference_disk,
                restart=mode, memory_maps=True)
            (args.evidence / f"{mode}-before.txt").write_text(before)
            (args.evidence / f"{mode}-after.txt").write_text(after)
            for phase in ("BEFORE", "AFTER"):
                raw = subprocess.check_output(
                    ["mtype", "-i", str(work / f"{mode}-interfaces-warm.ima"),
                     f"::{phase}.MEM"], env=capture.mtools_env())
                (args.evidence / f"{mode}-{phase.lower()}-mem.txt").write_text(raw.decode("cp437"))
            batch = work / f"{mode}-interfaces-warm.bat"
            (args.evidence / f"{mode}-AUTOEXEC.BAT").write_bytes(batch.read_bytes())
            first = capture.public_interface_semantics(capture.parse_public_interfaces(before))
            second = capture.public_interface_semantics(capture.parse_public_interfaces(after))
            changes = {key: [first.get(key), second.get(key)]
                       for key in first.keys() | second.keys() if first.get(key) != second.get(key)}
            results[mode] = changes
            print(f"{mode}: {json.dumps(changes, sort_keys=True)}", flush=True)
        if capture.sha256(args.reference_disk) != disk_hash:
            raise RuntimeError("reference disk changed")
        report = dict(media_sha256=media_hash, disk_sha256=disk_hash,
                      vc_sha256=vc_hash, probe_sha256=probe_hash,
                      emulator=capture.qemu_identity(), changes=results,
                      scope="floppy boot with snapshot IDE; controlled diagnosis, not acceptance")
        (args.evidence / "results.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
