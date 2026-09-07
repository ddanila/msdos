# Emulator tests

Local results are authoritative while automatic CI is paused. Choose the
backend needed by the hardware contract; a command smoke test cannot qualify
BIOS, A20, or protected-mode behavior.

| Backend | Role |
| --- | --- |
| kvikdos | Fast command and utility tests without a complete PC. |
| QEMU | Primary 386+ boot, filesystem, driver, TSR, interrupt, EMM386, and transport tests. |
| 86Box | IBM AT 286 acceptance with a real BIOS: A20/HMA, block moves, fallback, CPU rejection, and reboot. |
| DOSBox-X | Pre-386 comparison and smoke tests; synthesized BIOS behavior is insufficient as the sole 286 oracle. |

MAME can provide an independent full-machine comparison when needed; it is not
part of the maintained acceptance gate. Add backends only for a concrete gap.

## 286 acceptance

The suite uses the tracked [IBM AT configuration](tests/86box/ibmat-286.cfg).
86Box 6.x and the IBM 5170 ROMs are external prerequisites. On macOS:

```sh
brew install --cask 86box
```

Set `BOX86_BIN` to the executable and `BOX86_ROMS` to the ROM-set directory
when automatic discovery is insufficient. Binary discovery checks PATH and the
macOS application; ROM discovery defaults to the macOS application-support
path. Other installations should set `BOX86_ROMS` explicitly. Required ROM
filenames and discovery rules are in [86box_286_lib.sh](tests/86box_286_lib.sh).

After building, run:

```sh
FAIL_ON_SKIP=1 make test-286-acceptance
```

Use `gmake` on macOS as described in [README.md](README.md). Missing prerequisites
are reported as skips, or failures with `FAIL_ON_SKIP=1`. The suite uses private
images, bounded serial completion, and disk-result checks; failure diagnostics
are retained under `out/86box-286-failures/`.

## Limits

The default 286 suite does not qualify opt-in composed memory layouts.
Retest those with matched images and their own success/fallback probes; see
[MEMORY.md](MEMORY.md).

A DOSBox-X stall alone does not establish a product defect; compare a real-BIOS
backend. Emulators do not prove every chipset, A20 controller, physical storage
or printer device, Weitek coprocessor, or timing-sensitive peripheral.
