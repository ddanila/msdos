# Windows 95 installer acceptance

This is an opt-in check using user-supplied Windows 95 OEM media. QEMU trials
have completed normal Typical installation through to desktop and shutdown in
these separate configurations:

- runtime SMARTDRV, with no HIMEM;
- HIMEM with DOS=HIGH, without runtime SMARTDRV.

HIMEM with DOS=LOW has reached graphical Setup; a full installation is not
qualified. Combined HIMEM/SMARTDRV installation, physical hardware, endurance,
and continued cache use under Windows protected mode are also unqualified.
The earlier loader and cache-launch defects are fixed. Source-directory damage
seen before those fixes did not reproduce in the successful normal installations;
ScanDisk is not an established outstanding defect.

These are bounded acceptance results, not a claim that every current build or
memory composition has been retested. Build history and investigation logs
belong in Git and ignored local artifacts.

## Reproduce

Build and deploy first. The harness needs QEMU, mtools, Tesseract, and Python
`pycdlib`. Run from the repository root with your own ISO and a new output path:

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

The harness creates a fresh 504 MiB FAT16 disk, stages the ISO, and runs a
Pentium TCG machine with 32 MiB RAM. It waits for Setup's prompt and compares
staged source files after the VM stops. Existing installed VMs are not reused.

Interactive input accepts QEMU monitor commands, `shot` for a screenshot/OCR
capture, and `finish` to stop and compare files. At Setup's restart prompt,
use `eject floppy0` and `boot_set c`. After Windows powers off, press Enter to
collect exit status and offline comparisons.

A successful harness exit only means observation completed. Inspect retained
screens, the report, installed guest, and source comparisons before declaring
installation successful. Keep media, product identification, VM disks, and
captures out of Git.

## Public regressions

The Windows-independent tests cover the defects exposed by these trials:

- `test-int21-system-qemu`: repeated failed opens while other handles remain live.
- `test-himem-xms3-qemu`: legacy free-memory status and exhaustion, plus XMS
  transfers crossing a 64 KiB offset boundary under LOW/HIGH.
- `tests/test_smartdrv_dos6_qemu.sh`: bounded cache-hit/miss transfers and
  resident storage; run with `SMARTDRV_INSTALL_MODE=runtime` for self-installation.

These focused tests do not replace an external-media installation run.
