# Windows 95 installer compatibility investigation

Local investigation on 2026-09-05 using the user's Windows 95 OEM CD in
QEMU 10.2.1 (Pentium TCG, 32 MiB RAM, 504 MiB FAT16 IDE disk, no network).
The CD and VM disks are not redistribution/test fixtures.
The initial observations below used base revision `e148ff1`. Subsequent sections
record retests and fixes through the DOS=HIGH installation on 2026-09-06,
using `2fe0b98` plus the two HIMEM fixes described below.

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

## Initial observations and follow-up

Windows Setup reaches its graphical wizard with the corrected kernel and
`FILES=60`, `BUFFERS=30`, no HIMEM, and the CD-documented `SETUP /IS` option.
This path subsequently completed Windows installation and booted the guest
to its desktop. The installed guest also ran JUKUWIN and booted a simulated
C12 Juku; those host-specific fixes and results are recorded in the sibling
`8080-cosim/docs/windows-jukuhost-client-win95-acceptance.md`.
Earlier normal-Setup attempts were followed by damage to the staged setup
directory. Skipping ScanDisk avoided that symptom; the precise cause has
not been established. Loading HIMEM initially produced an insufficient
extended-memory error in the mini-Windows loader; the 2026-09-06 follow-up below
isolates and fixes the HIMEM defects and verifies a full DOS=HIGH installation.

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

#### DOS=HIGH follow-up on 2fe0b98, 2026-09-06

Fresh external-media `SETUP /IS` runs using rebuilt boot components reproduced
the original extended-memory error with HIMEM + DOS=HIGH. HIMEM + DOS=LOW
instead reported `KERNEL: Unable to initialize heap`; no HIMEM reached the
graphical welcome/license screens. All 37 source files remained intact.
The full developer-image build hit an unrelated SHARE link failure for
`SetverResidentTable`, so these tests used a minimal floppy assembled from the
current IO.SYS, MSDOS.SYS, COMMAND.COM, SYSMENU.OVL, and HIMEM.SYS binaries.

A local XMS-call tracing TSR, leaving HIMEM unchanged, recorded function 08h
returning positive free-memory sizes but allocator scratch data in BL. After
the loader's allocations, one query returned AX=72ECh, DX=72ECh, BL=94h.
`largest_gap` leaves the end of the last allocation in BX, and `xms_query_free`
did not convert that scratch value into a public status. Function 88h already
normalized BL, but its legacy 08h counterpart did not.

The local fix sets BL=0 when memory remains and BL=A0h when exhausted, keeping
AX/DX as the reported memory sizes. The latter error is specified by the
[Microsoft XMS specification, function 08h](https://jnz.dk/swag/FAQ/0053.PAS.html).
The small regression additions to `himem_xms3_probe.asm` check status before
allocation, after a 64 KiB allocation (which made the old implementation leak
80h), and after exhausting the pool. The initial status assertion was observed
failing at phase `q` before the fix and passing afterwards.

With only this fix, both HIGH and LOW get past their previous loader errors
and enter the graphical environment, but fail with `WINSETUP caused Segment
Load Failure in module WINSETUP.BIN at 0001:4EE5`. That intermediate result was
not a successful installation. Local evidence is in `out/win95-high-xms-trace-03`
and `out/win95-{high,low}-query-fixed-01`; no external media is committed.

Do not infer HMA residency from AX=3306h in this fork: the current handler
explicitly returns zero flags even with DOS=HIGH configured. The local probe's
zero location flags therefore do not demonstrate fallback to DOS=LOW.

The second defect was in `resolve_move_address`: checking `offset + length`
changed BP from the start offset's high word to the end offset's high word.
The physical-address calculation then reused that changed value. A transfer
crossing a 64 KiB offset boundary could access memory 64 KiB beyond the intended
start, despite returning success. Preserve the original high word across the
bounds check, balancing its saved value on both valid and invalid paths.

`tests/himem_move_boundary_probe.asm` is a standalone regression requiring no
Windows files. It allocates 192 KiB and verifies crossing 32-byte writes and
reads at offset FFF0h against independently seeded/read eight-byte subranges.
It failed with the old address calculation and passes with the fix under both
DOS=LOW and DOS=HIGH. Run `bash tests/test_himem_move_boundary_qemu.sh` with a
boot floppy, optionally selected through `FLOPPY_IMAGE`. The existing
`test-himem-xms3-qemu` make target also runs this test.

With both fixes, fresh LOW and HIGH `/IS` runs reached graphical Setup and
preserved all 37 source files. A separate **normal Setup without `/IS`**, in
`out/win95-high-install-fixed-01`, completed a Typical installation with
`FILES=60`, `BUFFERS=30`, `DEVICE=A:\HIMEM.SYS /TESTMEM:OFF`, and `DOS=HIGH`.
ScanDisk, hardware detection, file copying, hard-disk reboot, and first-boot
configuration completed. The final Windows desktop accepted input and shut
down cleanly; the harness recorded QEMU exit code 0 and no source-file changes.
Screens `desktop.png` and `shutdown.png`, plus `report.json` and the stopped
installed disk, are retained in that ignored evidence directory.

The tested HIMEM.SYS SHA-256 is
`a477564a596029e91eb5021164a5ffc3762a712e8e31c302cb08c1bf290bc265`.
XMS 3.0 tests (including legacy-query status and exhaustion), the LOW/HIGH move
regression, the HIMEM ownership check, and the broader XMS/UMB/EMS/rollback/warm
reboot suite passed. The broader suite requires EMM386 on its base floppy;
the installer-only minimal image lacked it and was not a valid input for that
combined suite. The corrected regression image includes the current EMM386.

The tracked external-media harness now supports the memory configurations
directly, without the local diagnostic adapter used during investigation:

```sh
uv run --with pycdlib python tests/win95_setup_probe.py \
  --iso /path/to/WINDOWS95.ISO --floppy /path/to/current-boot.img \
  --output out/win95-high-new --memory high --mode normal --interactive
```

Use `--memory low` for HIMEM with DOS=LOW, or `--memory none` for the no-HIMEM
control. Full DOS=LOW installation, hardware validation, and extended endurance
are not claimed by this DOS=HIGH acceptance run.

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

The launch failure was fixed at this checkpoint. The complete installation
verification below was performed subsequently; the welcome-screen result
alone was not treated as a complete installation.
HIMEM/DOS=HIGH was tested separately in the 2026-09-06 follow-up. All screenshots, memory dumps,
Microsoft binaries, and disk images remain ignored local evidence under `out/`.

### Complete cache-enabled installation, 2026-09-05

`out/win95-smartdrv-install-01` completed a fresh Typical Windows 95 installation
using the corrected DOS build at `40cfc0f`. Runtime `A:\SMARTDRV.EXE` was loaded
before normal `SETUP`, **without `/IS`**. CONFIG.SYS contained only `FILES=60`
and `BUFFERS=30`; neither HIMEM nor DOS=HIGH was used. The QEMU machine and
external OEM ISO were the same as the earlier reproduction.

- Setup passed its disk checks, prepared the wizard, completed hardware
  detection, and copied the recommended Windows components without errors.
  No network services, printer, or startup floppy were configured.
- At the restart prompt, the disposable boot floppy was ejected and boot order
  changed to the hard disk. First-boot configuration completed, followed by
  Setup's final restart and the Windows 95 desktop.
- The desktop accepted keyboard input and launched `WINVER`. Windows shutdown
  powered off QEMU. A separate boot of the same installed disk, with no floppy,
  again reached the desktop; another Windows shutdown ended QEMU with status 0.
- With that VM stopped, all **37** original `C:\WIN95` source files matched
  their pre-install SHA-256 hashes. `WINDOWS\WIN.COM`, `EXPLORER.EXE`,
  `SYSTEM.DAT`, and `USER.DAT` were present and readable offline.
- Corrected SMARTDRV.EXE SHA-256:
  `783927a8e989f9d2d6cd135796c06e46522053eb8b16464d780ec71ec38a0a4a`.
  Modified test boot-floppy SHA-256:
  `740ae8b04918ad40e44c85991966e7cf580515f72386a9433f46dc4c28bfbc53`.

Local evidence includes `interactive-023.ppm` / `desktop.png` (first desktop),
`interactive-025.ppm` (WINVER), `reboot-02.ppm` (independent second boot), and
`reboot-shutdown.png` (Windows shutdown selection). The initial interactive
harness reported `Broken pipe` when a screenshot was requested after Windows
had powered off QEMU; this was a harness lifecycle error, not an installation
failure. Normal process exit is now handled explicitly and recorded in
`qemu_exit_code`. The independent boot/shutdown supplied the explicit exit-0
check; the original report is retained unaltered rather than relabeled a pass.
The focused `win95-smartdrv-harness-exit-01` run exercised a normal monitor
`quit` during Setup and then collected exit code 0 with no harness error and
unchanged sources. That run validates exit handling only, not installation.

To repeat the supervised installation with your own media and identification:

```sh
uv run --with pycdlib python tests/win95_setup_probe.py \
  --iso /path/to/WINDOWS95.ISO --output out/win95-install-new \
  --mode fork-smartdrv --seconds 15 --interactive
```

After the initial bounded observation, the harness accepts QEMU human-monitor
commands on stdin (for example `sendkey ret 30`), `shot` to retain a numbered
screenshot and OCR text, or `finish` to stop the VM and compare source files.
At Setup's restart prompt, use `eject floppy0` and `boot_set c` before continuing.
After Windows powers the VM off, press Enter to collect its exit status and
offline comparisons. Do not treat a normal harness exit as automatic evidence
that the wizard completed; inspect the retained screens and installed guest.
No product identification, ISO contents, or Windows installation is committed.

This verifies installation through the fork's runtime cache, not continued use
of that cache under Windows protected mode, HIMEM/DOS=HIGH compatibility,
physical hardware, or endurance. The separate working Juku Windows VM was not
modified by these experiments.
