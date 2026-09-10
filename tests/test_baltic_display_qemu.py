#!/usr/bin/env python3
"""Load CP775 on matched HIGH/LOW profiles and compare actual VGA font bytes."""

import hashlib
import json
import os
from pathlib import Path
import tempfile

from ru_profiles import verify_base
from test_baltic_cpi import CPI, ROOT, check_fonts
from test_ru_cpi import parse_cpi
from test_ru_display_qemu import run_case


def main():
    base = Path(os.environ.get("FLOPPY_IMAGE", ROOT / "out/floppy.img"))
    core = verify_base(base)
    fonts = parse_cpi(CPI.read_bytes(), 775)
    check_fonts(fonts)
    work = Path(tempfile.mkdtemp(prefix="baltic-display-", dir=ROOT / "out"))
    print(f"Baltic display artifacts: {work}", flush=True)
    report = {"schema_version": 1, "status": "running", "core_sha256": core,
              "base_image_sha256": hashlib.sha256(base.read_bytes()).hexdigest(),
              "cpi_sha256": hashlib.sha256(CPI.read_bytes()).hexdigest(),
              "country_sha256": hashlib.sha256((ROOT / "src/DEV/COUNTRY/COUNTRY.SYS").read_bytes()).hexdigest(),
              "scope": "Shared CP775 font, Estonian country selection for HIGH/LOW setup, rendered samples in all three languages. Country API and keyboard behavior require separate gates.",
              "cases": []}
    for profile in ("high", "low"):
        folder = work / profile
        folder.mkdir()
        for height, corrupt in ((16, False), (14, False), (8, False), (16, True)):
            result = run_case(folder, base, 775, height, fonts[height], corrupt=corrupt,
                              profile=profile, cpi_source=CPI, corrupt_slot=0xe4,
                              country=372, country_page=775)
            result["screen"] = profile + "/" + result["screen"]
            report["cases"].append(result)
            (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    report["status"] = "passed"
    (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
