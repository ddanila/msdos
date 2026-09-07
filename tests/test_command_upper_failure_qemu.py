#!/usr/bin/env python3
"""Reject upper allocation or low shrink in same-size private COMMAND copies."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from capture_vc_memory_comparison import ROOT, capture, image_file, parse_capture
from report_command_residency import parse_map
from test_command_high_resident_qemu import build
from test_command_upper_data_qemu import check_runtime
from test_dos_char_retirement_qemu import install
from test_umb_subpage_composition import xms_summary


def check_persistent_failure(directory, source, binary):
    directory.mkdir()
    disk = directory / "input.img"
    shutil.copyfile(source, disk)
    for name in ("COMMAND.COM", "DOS/COMMAND.COM"):
        install(disk, name, bytes(binary))
    install(disk, "FATALRUN.TXT", b"AUTOEXEC_NOT_RUN\r\n")
    install(disk, "AUTOEXEC.BAT", b"@ECHO OFF\r\nECHO UNSAFE_CONTINUATION>FATALRUN.TXT\r\n")
    socket = directory / "qmp"
    with (directory / "qemu.log").open("wb") as log:
        process = subprocess.Popen(["qemu-system-i386", "-display", "none", "-monitor", "none",
            "-cpu", "486", "-m", "8", "-boot", "c", "-serial", "none", "-no-reboot",
            "-drive", f"if=ide,index=0,format=raw,file={disk}",
            "-qmp", f"unix:{socket},server=on,wait=off"], stdout=log, stderr=log)
        try:
            subprocess.run([sys.executable, ROOT / "tests/screen_expect.py", socket,
                directory / "screen.log", "COMMAND memory-policy recovery failed. Restart required.",
                "hmp:stop"], check=True, timeout=55)
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    assert image_file(disk, "::FATALRUN.TXT") == b"AUTOEXEC_NOT_RUN\r\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path, help="packed upper-data composition")
    parser.add_argument("--policy-rejection", action="store_true",
                        help="compare successful placement with rejected UMB-link restoration")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="command-upper-failure-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    command = build(work / "build", True, upper_data=True)
    original = command.read_bytes()
    assert original == image_file(args.image, "::COMMAND.COM"), "fresh shell differs from pinned composition"
    assert original == image_file(args.image, "::DOS/COMMAND.COM")
    segments, _ = parse_map(command.with_suffix(".MAP"))
    listing = (work / "build/INIT.LST").read_text(encoding="latin-1")
    block = listing.split("relocate_shell_data proc near", 1)[1].split("relocate_shell_data endp", 1)[0]
    sites = {}
    recovery_sites = []
    for label, service in (("allocation-rejected", "48"), ("shrink-rejected", "4A")):
        matches = re.findall(rf"(?im)^([0-9A-F]+)\s+B4{service}\b.*mov ah,{service}h", block)
        assert len(matches) == 1, (label, matches)
        site = segments["INIT"].start + int(matches[0], 16) + 2 - 0x100
        assert original[site-2:site+2] == bytes.fromhex("b4" + service + "cd21")
        sites[label] = site
    if args.policy_rejection:
        restore = block.split("shell_data_restore_policy:", 1)[1]
        matches = re.findall(r"(?im)^([0-9A-F]+)\s+B80358\b.*mov ax,5803h", restore)
        assert len(matches) in (1, 2), matches  # optional independent cleanup retry
        site = segments["INIT"].start + int(matches[0], 16) + 3 - 0x100
        assert original[site-3:site+2] == bytes.fromhex("b80358cd21")
        sites["link-reject"] = site
        recovery_sites = [segments["INIT"].start + int(value, 16) + 3 - 0x100 for value in matches]
    ceiling = work / "CEILING.COM"
    subprocess.run(["nasm", "-f", "bin", ROOT / "tests/memory_ceiling_probe.asm", "-o", ceiling], check=True)
    policy = work / "POLICY.COM"
    subprocess.run(["nasm", "-f", "bin", ROOT / "tests/command_allocation_policy.asm", "-o", policy], check=True)
    report = dict(input_sha256=hashlib.sha256(args.image.read_bytes()).hexdigest(), results={})
    cases = ("success", "link-reject") if args.policy_rejection else ("success", *sites)
    for label in cases:
        directory = work / label
        directory.mkdir()
        disk = directory / "input.img"
        shutil.copyfile(args.image, disk)
        binary = bytearray(original)
        if label in sites:
            site = sites[label]
            binary[site:site+2] = b"\xf9\x90"  # STC/NOP instead of this INT 21h only
        for name in ("COMMAND.COM", "DOS/COMMAND.COM"):
            install(disk, name, bytes(binary))
        serial, screen = capture(label, disk, directory, ceiling)
        result = parse_capture(serial, screen)
        result["xms"] = xms_summary(serial.read_text(encoding="latin-1"))
        install(disk, "POLICY.COM", policy.read_bytes())
        check_runtime(directory, disk, initial_commands="POLICY.COM > POLICY0.BIN\r\n",
                      extra_commands="POLICY.COM > POLICY.BIN\r\n")
        policy_bytes = image_file(directory / "runtime.img", "::POLICY.BIN")
        assert len(policy_bytes) == 4, policy_bytes
        assert policy_bytes == image_file(directory / "runtime.img", "::POLICY0.BIN"), "runtime changed policy"
        result["allocation_policy"] = policy_bytes.hex()
        result["mutation_offset"] = sites.get(label)
        result["command_sha256"] = hashlib.sha256(binary).hexdigest()
        report["results"][label] = result
        (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")
        if label != "success":
            control = report["results"]["success"]
            assert result["largest"] == control["largest"] - 336, "wrong low fallback allocation"
            assert result["upper_free"] == control["upper_free"] + 352, "temporary upper owner leaked"
            assert result["xms"] == control["xms"]
            assert result["allocation_policy"] == control["allocation_policy"], "policy not restored"
        else:
            assert result["largest"] == 625312 and result["upper_free"] == 48064, "control did not publish packed state"
        print(f"{label}: PASS", flush=True)
    if args.policy_rejection and len(recovery_sites) == 2:
        binary = bytearray(original)
        for site in recovery_sites:
            assert binary[site:site+2] == b"\xcd\x21"
            binary[site:site+2] = b"\xf9\x90"
        check_persistent_failure(work / "fatal", args.image, binary)
        report["persistent_rejection"] = dict(passed=True, mutation_offsets=recovery_sites,
            command_sha256=hashlib.sha256(binary).hexdigest(), autoexec_ran=False)
        (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")
        print("persistent rejection: explicit stop before AUTOEXEC: PASS", flush=True)


if __name__ == "__main__":
    main()
