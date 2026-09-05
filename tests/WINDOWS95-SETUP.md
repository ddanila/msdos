# Windows 95 installer compatibility investigation

Local investigation on 2026-09-05 using the user's Windows 95 OEM CD in
QEMU 10.2.1 (Pentium TCG, 32 MiB RAM, 504 MiB FAT16 IDE disk, no network).
The CD and VM disks are not redistribution/test fixtures.
The observations below were made from base revision `e148ff1` plus the fixes
described here, before subsequent upstream BIOS/HMA changes through `e1d9bdf`.
The unresolved Windows-loader and ScanDisk cases have not been rerun on that
newer upstream state.

## Confirmed fixes

- `mk/cmd.mk` named `comsw.asm` instead of the tracked `COMSW.ASM`, breaking
  deployment on case-sensitive Linux. `test_toolchain_transforms.py` checks
  the exact prerequisite against directory entries; the old spelling fails.
- Failed opens leaked JFN reservations when the selected SFT was outside
  DOSGROUP. `AccessFile` loads DS with the SFT segment; `OpenE` then loaded
  the global `pJFN` through that DS instead of SS. Make the SS override
  explicit. Microsoft's CD-supplied EXTRACT.EXE repeatedly probes absent
  `DIA0.TMP` while holding two cabinet inputs open. Before the fix it runs
  out of handles; afterwards both PRECOPY cabinets extract to completion.
  The public regression uses no Microsoft files: the INT 21h system probe
  holds two NUL handles and performs 64 missing-file opens with FILES=60.
  It prints `INT21_MISSING_OPEN_LEAK` before the fix and
  `INT21_SYSTEM_PASS` afterwards.

## Still under investigation

Windows Setup reaches its graphical wizard with the corrected kernel and
`FILES=60`, `BUFFERS=30`, no HIMEM, and the CD-documented `SETUP /IS` option.
This path subsequently completed Windows installation and booted the guest
to its desktop. The installed guest also ran JUKUWIN and booted a simulated
C12 Juku; those host-specific fixes and results are recorded in the sibling
`8080-cosim/docs/windows-jukuhost-client-win95-acceptance.md`.
Earlier normal-Setup attempts were followed by damage to the staged setup
directory. Skipping ScanDisk avoided that symptom; the precise cause has
not been established. Loading the current HIMEM produced an insufficient
extended-memory error in the mini-Windows loader; this also remains open.

### HIMEM / mini-Windows loader

The failing configuration included:

```ini
FILES=60
BUFFERS=30
DEVICE=A:\HIMEM.SYS /TESTMEM:OFF
DOS=HIGH
```

`SETUP /IS` reported: `Insufficient extended memory to run Windows in standard mode.`
Removing both the HIMEM device line and `DOS=HIGH`, while retaining FILES and
BUFFERS, allowed the graphical loader to start. This does not isolate HIMEM
from HMA residency, and that observation preceded the failed-open cleanup fix.
The successful installation does not validate this configuration.

Next check: on fresh cloned disks with the corrected kernel, compare no HIMEM,
HIMEM with DOS=LOW, and HIMEM with DOS=HIGH under the same QEMU settings.
Record XMS installation/version, free-memory query, allocation and lock results
before invoking the CD's loader. Do not infer an XMS implementation defect solely
from the loader's generic memory message.

### ScanDisk / staged source directory damage

The original setup source was staged in `C:\WIN95`. Following normal Setup
attempts, that directory no longer listed the CAB files and instead listed
`WINTEMP.400`; subsequent Setup attempts reported a missing required CAB file.
A separate DOS `MD C:\PROBE` test left the source directory intact. Using
`SETUP /IS` avoided the observed directory damage.

These attempts preceded the failed-open cleanup fix, which can write through
the wrong pointer. ScanDisk has **not** been established as a separate remaining
kernel bug: stale state from an interrupted installation and the fixed cleanup
defect have not been excluded. Retest normal Setup and `/IS` on separate pristine
clones with the corrected kernel, comparing FAT/root/subdirectory metadata and
CAB hashes before and after the ScanDisk stage. Do not test repair operations on
the only copy of an installed guest or original media.

## Validation retained locally

`make -j4 deploy`, `python3 tests/test_toolchain_transforms.py`,
`bash tests/test_int21_system_qemu.sh`, `bash tests/test_int21_path_errors_qemu.sh`
(DOS=LOW and DOS=HIGH), and `bash tests/test_int21_file_memory_qemu.sh` passed.
The failed-open regression was observed failing before the segment fix and
passing afterwards. VM disks and diagnostics are under the sibling project's
ignored `build/win95/`; none of the proprietary installation files are committed.
The same deployment and focused regression commands also passed after
integrating upstream `e1d9bdf`, before publishing this report. That regression
rerun did not include the proprietary Windows installer/HIMEM/ScanDisk cases.

## Follow-up reproduction, 2026-09-05

`tests/win95_setup_probe.py` is an opt-in external-media harness. It creates
fresh 504 MiB FAT16 disks under ignored `out/`, stages the user's ISO, boots
the generated DOS floppy, waits for the actual Setup prompt using screenshot
OCR, and compares every staged source file byte-for-byte after the bounded
run. It never reuses or modifies an existing Windows VM. Dependencies are
QEMU, mtools, Tesseract, and Python `pycdlib` (for example via `uv run --with
pycdlib python ...`). These observations concern the initial Setup stage,
not a complete unattended installation.

Example, from the repository root:

```sh
uv run --with pycdlib python tests/win95_setup_probe.py \
  --iso /path/to/WINDOWS95.ISO --output out/win95-normal-new \
  --mode normal --seconds 25
```

- `out/win95-normal-current-01` was inconclusive: a fixed-delay Enter was sent
  before Setup's prompt. It must not be counted as a successful ScanDisk run.
  The harness now waits for the actual prompt rather than relying on boot time.
- `out/win95-normal-current-02`, using the corrected build on `b9f980e`, ran
  **normal Setup without `/IS`**, reached the graphical welcome screen, and
  preserved all 37 staged source files byte-for-byte (39 directory entries
  including `.` and `..`). The earlier damage did not reproduce at this stage.
- `out/win95-smartdrv-current-01` did not reach the initial Setup prompt within
  the 120-second observation window after loading the fork's `SMARTDRV.EXE`.
  A second instrumented run, `out/win95-smartdrv-current-02`, shows
  `PROBE_CACHE_RETURNED`, `PROBE_DRIVE_SELECTED`, and `PROBE_SETUP_START`,
  but no Setup prompt during observation. This localizes the stall to launching
  or running Setup after cache installation, not the cache install command
  itself. The basic `test_smartdrv_runtime_qemu.sh` install/status fixture uses
  a blank 16 MiB disk and does not cover this staged-source workload.
- The harness now retains failure text, CPU registers when available, and
  offline source comparisons even when Setup does not reach its prompt.
  Failure exits nonzero. A successful harness exit is only a completed
  observation: inspect the screen/report before calling an installer stage a pass.
- SMARTDrive (disk cache) and ScanDisk (disk checker) are separate components;
  these observations do not establish that the earlier source-directory damage
  had the same cause. The following investigation isolates the cache-enabled
  launch failure, not the historical pre-handle-fix disk image.

### SMARTDRV read overruns and runtime resident storage

Fresh cache-enabled runs reproduced three defects:

1. The partial-read cache-hit range check overwrote AX, the caller's word
   count, and added a word at the byte-sized `valid_start` field, incorporating
   the adjacent `valid_count`. The subsequent copy could greatly exceed the
   requested sector count. Preserve AX on both hit and refill paths and add
   the two byte fields with explicit zero extension.
2. On a cache miss, recording `READ_WINDOW_COUNT` in AL also changed the
   restored caller word count immediately before `read_buffer`. Preserve AX
   while recording the cached window. Fixing only the hit path was insufficient.
3. Runtime self-installation kept only the executable and C stack, although
   driver initialization expands its conventional track buffer and metadata
   beyond the linked image. The following program could reuse live cache
   storage. Reserve the driver's full segment before initialization and retain
   at least the returned INIT break address when terminating resident.

Evidence and regression coverage:

- `win95-smartdrv-trace-01` and `-02` reproduced the original stall, including
  after rebuilding the merged BIOS changes. A low-memory snapshot showed FAT
  data replacing the DOS interrupt-stack area. With only the hit-path fix,
  `win95-smartdrv-fixed-01` still stalled with corrupted DOS buffer links.
  With both transfer fixes but the old loader, `win95-smartdrv-fixed-02`
  reported `Program too big to fit in memory`, followed by a memory-allocation
  error; the resident block did not include the expanded cache storage.
- `smartdrv_read_probe.asm` now checks 8192 guard bytes after both the initial
  one-sector miss and a repeated hit. The hit guard failed before the first
  fix; the miss guard still failed with only that fix. Both pass together.
  The DOS 6 suite exercises this at short and long read-ahead settings.
- `SMARTDRV_INSTALL_MODE=runtime bash tests/test_smartdrv_dos6_qemu.sh` runs
  the full disk/CD, eviction, transfer-sizing, and delayed-write workload with
  self-installation instead of CONFIG.SYS loading. It fails with the binary
  containing both read fixes but the old loader (supplied through
  `SMARTDRV_BINARY`), and passes with the corrected loader. The original
  device-installation mode also passes with the read fixes.
- `make -j4 deploy`, the basic runtime self-installation gate, the explicit
  and command-prompt flush gate, and the INT 19h reboot-flush gate passed.
- `out/win95-smartdrv-fixed-03` loaded the corrected runtime SMARTDRV, ran
  normal Setup **without `/IS`**, and reached the graphical welcome screen.
  All 37 staged ISO files remained byte-for-byte unchanged. The no-cache
  control `out/win95-normal-merged-01` also reached that screen.

The launch failure is fixed at this checkpoint. Completing the wizard and
verifying an installed Windows desktop from this cache-enabled path remain
outstanding; reaching the welcome screen is not a complete installation.
HIMEM/DOS=HIGH remains a separate observation. All screenshots, memory dumps,
Microsoft binaries, and disk images remain ignored local evidence under `out/`.
