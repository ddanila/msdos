# Windows 95 installer acceptance

This opt-in harness uses user-supplied Windows 95 OEM media. Acceptance requires
normal Typical installation through desktop and shutdown, with staged source
files unchanged. Qualify each memory/cache configuration and boot image
separately; focused public regressions do not qualify a full installation.

Combined HIMEM/SMARTDRV use, DOS=LOW installation, physical hardware, endurance,
and continued cache use under Windows protected mode remain validation gaps.

## Reproduce

Build and deploy first. The harness needs QEMU, mtools, Tesseract, Python 3.11+,
and `pycdlib`. Run from the repository root with your own ISO and a new output path:

```sh
uv run --with pycdlib python tests/win95_setup_probe.py \
  --iso /path/to/WINDOWS95.ISO --output out/win95-high-new \
  --memory high --mode normal --interactive
```

`uv` is optional if `pycdlib` is installed in your Python environment. Use
`--floppy` to select a matched boot image instead of `out/floppy.img`.
`--memory low` selects HIMEM with DOS=LOW; `--memory none` is the no-HIMEM
control. `--mode fork-smartdrv` loads the runtime cache before normal Setup;
`--mode skip-scandisk` selects `SETUP /IS` for comparison.

The harness stages the ISO in a fresh VM and compares source files after it
stops. Existing installed VMs are not reused. See the
[harness](win95_setup_probe.py) for machine configuration; the run report records
the QEMU command.

Interactive input accepts QEMU monitor commands, `shot` for a screenshot/OCR
capture, and `finish` to stop and compare files. At Setup's restart prompt,
use `eject floppy0` and `boot_set c`. After Windows powers off, press Enter to
collect exit status and offline comparisons.

A successful harness exit does not assert installation success or unchanged
source files. Inspect the screens, installed guest, and `report.json`, including
`changed_source_files`, before declaring success. Keep media, product
identification, VM disks, and captures out of Git.
