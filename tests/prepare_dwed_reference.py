#!/usr/bin/env python3
"""Prepare a private DWED test floppy from local DOS reference media."""

import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

CORE = ("IO.SYS", "MSDOS.SYS", "COMMAND.COM")
DRIVERS = ("HIMEM.SYS", "EMM386.EXE")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--system-files", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    source = args.image.read_bytes()
    installed = {}
    for name in CORE:
        data = subprocess.check_output(["mtype", "-i", str(args.image), "::" + name])
        if data != (args.system_files / name).read_bytes():
            parser.error(f"reference image and system-files differ: {name}")
        installed[name] = digest(data)
    drivers = {
        name: digest((args.system_files / name).read_bytes()) for name in DRIVERS
    }
    listing = subprocess.check_output(
        ["mdir", "-a", "-b", "-i", str(args.image), "::"], text=True
    ).splitlines()
    if any(not name.startswith("::/") or "/" in name[3:] for name in listing):
        parser.error("reference floppy must contain only root-level files")
    args.output.mkdir(parents=True, exist_ok=False)
    boot = args.output / "boot.img"
    shutil.copyfile(args.image, boot)
    for name in listing:
        if name[3:].upper() not in CORE:
            subprocess.run(["mdel", "-i", str(boot), name], check=True)
    for name in CORE:
        data = subprocess.check_output(["mtype", "-i", str(boot), "::" + name])
        assert digest(data) == installed[name]
    report = {
        "source_image_sha256": digest(source),
        "boot_image_sha256": digest(boot.read_bytes()),
        "core_sha256": installed,
        "driver_sha256": drivers,
        "operation": "Copy floppy; retain boot sectors and DOS core; remove other root files",
    }
    (args.output / "provenance.json").write_text(json.dumps(report, indent=2) + "\n")
    print(boot)


if __name__ == "__main__":
    main()
