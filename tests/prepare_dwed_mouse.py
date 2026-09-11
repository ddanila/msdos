#!/usr/bin/env python3
"""Prepare the hash-pinned external CuteMouse fixture for DWED runtime tests."""

import argparse
import json
from pathlib import Path

from capture_dos_app_smoke import package_files
from dwed_mouse_scenarios import validate_driver

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--cache", type=Path, default=ROOT / "out/dwed-mouse-fixtures")
args = parser.parse_args()
args.cache.mkdir(parents=True, exist_ok=True)
manifest = json.loads((ROOT / "tests/dos_app_smoke.json").read_text())
package = next(
    package for package in manifest["packages"] if package["id"] == "ctmouse"
)
directory, provenance = package_files(package, args.cache)
driver = directory / "ctmouse.exe"
validate_driver(driver)
(args.cache / "package.json").write_text(json.dumps(provenance, indent=2) + "\n")
print(driver.resolve())
