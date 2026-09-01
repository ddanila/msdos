# Emulator strategy

Local emulator results are authoritative while automatic CI is disabled.
Emulators have distinct roles; a passing fast smoke test does not replace the
machine model needed by a hardware contract.

## Roles

| Backend | Role |
| --- | --- |
| kvikdos | Fast deterministic command and utility behavior that does not need a complete PC. |
| QEMU | Primary 80386-and-newer machine tests: boot, filesystems, drivers, TSRs, EMM386, interrupts, and multi-machine transports. |
| 86Box | Authoritative IBM AT 80286 acceptance: real BIOS paths, A20/HMA, protected-mode block moves, fallback, and reboot. |
| DOSBox-X | Fast 8086/286 comparison and smoke tests. Its synthesized 286 BIOS/protected-mode behavior is not sufficient as the sole oracle. |
| MAME | Optional independent full-machine oracle when an 86Box result is disputed or stronger scripted timing is required. |

PCem and Bochs currently offer no useful additional contract. Add another
backend only when it closes a specific validation gap.

## 86Box reference machine

Keep one versioned configuration for an IBM AT-class machine with:

- an 80286 CPU;
- a real AT BIOS from the separately installed 86Box ROM set;
- enough extended memory to exercise HIMEM and BIOS block moves;
- VGA text output;
- a writable copy of the deployed FAT image; and
- serial output captured to a private per-run file.

86Box and its ROMs are test prerequisites, not distributable product
artifacts. On macOS, install the emulator with:

```sh
brew install --cask 86box
```

Use 86Box's normal ROM directory or set `ROM_PATH`. `EMU286` may select the
binary. The suite must validate prerequisites and skip with a precise reason
when they are absent.

Run the complete 286 acceptance gate with:

```sh
gmake test-286-acceptance
```

The gate creates private images and logs, boots without UI interaction, waits
for bounded serial completion, terminates the emulator, and leaves the
canonical deployed image unchanged.

## 286 acceptance contract

The current suite covers:

- clean IBM AT boot and DOS 6.22 identity;
- BIOS `INT 15h/AH=87h` block movement and protected-mode return;
- HIMEM installation, A20 ownership, HMA lifecycle, XMS moves, and warm reboot;
- memory-stack behavior without 386-only EMM386 services;
- safe 286 rejection by 386-only tools and MemMaker; and
- fallback behavior for DEVICEHIGH and LOADHIGH when UMBs are unavailable.

Any new hardware-sensitive 286 behavior should land in this gate and, where
practical, receive a DOSBox-X comparison. QEMU remains the regression backend
for 386-and-newer behavior.

## Known limits

DOSBox-X 2026.08.02 passes the focused HIMEM lifecycle, but the broader
pre-386 boot image can stall before AUTOEXEC. Treat that as a backend
limitation unless an independent full-machine emulator reproduces it.

Emulation does not prove compatibility with every chipset or physical device.
Unusual A20 controllers, shadow RAM, real Weitek hardware, physical storage
controllers, and timing-sensitive peripherals remain explicit validation
limits. Prefer agreement between independent full-machine emulators before
changing hardware-facing code to accommodate a single backend.
