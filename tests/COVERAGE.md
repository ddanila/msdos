# Behavioral coverage and traceability

The coverage goal is contract coverage, not a misleading source-line percentage
for a mixed 16-bit assembly/C system. Every supported external interface must
eventually have focused positive, negative, boundary, and state-transition
tests on the built system under QEMU.

`int21_coverage.json` is the machine-readable traceability inventory for the
kernel's live INT 21h dispatch table. `test_coverage_manifest.py` parses
`DOS/MS_TABLE.ASM` directly, verifies that the table is exactly `00h` through
`6Ch`, rejects stale calls or missing evidence files, and reports four levels:

- **contract tested**: a focused test asserts the function's documented result;
- **behavior observed**: existing E2E behavior reaches the call, but does not
  isolate its complete contract;
- **justified exclusion**: direct testing is not feasible and the reason is
  recorded;
- **uncovered**: no evidence has been established yet.

`int21_error_coverage.json` independently derives every function/error pair
from the kernel's live `I21_MAP_E_TAB`. This prevents a successful call from
being mistaken for coverage of all its documented failure contracts. Its
structural verifier rejects stale pairs and non-CI evidence while reporting
the remaining negative-path backlog.

`runtime_coverage.json` applies the same levels to every shipped or built
runtime `.COM`, `.EXE`, and `.SYS` component and to every directive parsed from
the kernel's live `COMTAB` in `BIOS/SYSINIT2.ASM`. Its verifier derives both
sets from the source and Makefile, rejecting omitted or stale entries.

Focused CONFIG.SYS state coverage uses `test_config_state_qemu.sh`. Its probe
queries BREAK and LASTDRIVE through public INT 21h interfaces and reads the DOS
list of lists for the configured BUFFERS, FILES, and FCBS allocations. COMMENT
and REM contain apparent state-changing commands; the probe asserts that both
lines were ignored and did not override BREAK.
The same probe loads `CPSW=ON` and verifies the DOS 4 compatibility behavior:
INT 21h/AH=33h subfunctions 03h and 04h are accepted but intentionally preserve
their caller-visible sentinel state.
DRIVPARM applies a deliberately nondefault B: geometry, which is read back
through DOS generic IOCTL and checked field by field.

`test_config_switches_qemu.sh` boots isolated control and `SWITCHES=/K` images
in parallel. An INT 16h hook proves that the directive changes DOS CON input
from the extended keyboard read function to the conventional compatibility
function.

`test_config_stacks_qemu.sh` compares isolated `STACKS=0,0` and
`STACKS=9,256` boots. The configured case must reserve at least the exact lower
bound implied by nine stack entries and their 256-byte payloads; the current
build also accounts for the relocated stack handler.

`test_config_ifs_qemu.sh` supplies a minimal purpose-built IFS fixture. It
accepts the boot-time INIT request, returns its resident size, and is then
verified by name in DOS's live IFS header chain. This covers actual IFS loading
and linkage without pretending that one of the shipped TSRs is an IFS driver.

`test_config_multitrack_qemu.sh` attaches separate FAT16 IDE images to parallel
ON and OFF boots. An INT 13h observer proves the same ten-sector absolute read
is coalesced across a track only when MULTITRACK is enabled.

Driver contracts similarly require an effect after installation. For example,
`test_ansi_driver_qemu.sh` sends an ANSI cursor-position sequence through DOS
and checks the resulting coordinates through the BIOS.
`test_driver_sys_qemu.sh` installs a logical drive backed by a separate second
floppy, handles the driver's media prompt through QMP, and verifies known bytes
read through the new drive letter.
`test_printer_driver_qemu.sh` loads the 4201 printer definition and proves its
code-page control path by preparing, selecting, and querying code page 850.
`test_smartdrv_flush_qemu.sh` attaches a fixed disk and uses FLUSH13 to assert
SMARTDRV status, disable/enable transitions, policy changes, and an explicit
successful flush.
`test_xma_drivers_qemu.sh` covers the XMA drivers' documented hardware gate on
QEMU's AT-compatible machine. It asserts both exact boot diagnostics, walks the
live DOS device chain to prove neither rejected driver remained resident,
checks that no LIM EMS signature was installed on INT 67h, and verifies DOS
services remain operational.

`test_format.sh` groups cases by the floppy geometry cached by IO.SYS. Its
media checks cover 1.44MB and 720KB BPBs, 360KB and single-sided formats in a
1.2MB drive, and the legacy pre-BPB 320KB `/8` FAT layout. Unsupported `/T`/`/N`
and undocumented-switch paths require their exact rejection diagnostics; no
FORMAT case is accepted merely because the batch continued.

`test_int21_file_memory_qemu.sh` includes destructive-but-recoverable resource
limits. It consumes the largest reported DOS arena, asserts error 8 on the next
allocation, releases it, and allocates again. With `FILES=12` and an expanded
process handle table, it similarly exhausts the global SFT, asserts error 4,
closes every handle, and proves a subsequent open succeeds.
`test_root_exhaustion_qemu.sh` independently fills all 224 FAT12 root entries,
asserts access denied on create while clusters remain free, releases one entry,
and creates again. `test_disk_exhaustion_qemu.sh` fills the data clusters,
asserts DOS's documented short-write result, releases controlled files, and
then completes a full write.
`test_int21_path_errors_qemu.sh` distinguishes local FAT failure classes with
purpose-built paths: absent file versus absent parent, existing directory,
nonempty directory, current-directory removal, and a find with no matches.
The file/memory probe separately fills the default JFT and configured SFT so
duplicate and all create/open variants return their exact capacity errors.
The process probe covers EXEC success and seven distinct failure contracts. It
rejects invalid modes, missing files and parents, directories, unterminated
32 KiB environments, an exhausted system file table, and an exhausted memory
arena. It releases both constrained resources before a final successful child
execution, so the test also proves recovery rather than only observing errors.
Rename coverage distinguishes absent leaves and parents, an existing target,
and attempts to rename the active current directory. Extended-open coverage
asserts its action and access selectors plus missing, existing, directory,
full-root, and exhausted-SFT behavior rather than treating ordinary open/create
coverage as evidence for the DOS 4-specific interface.
Memory-manager coverage temporarily corrupts and restores an allocated block's
MCB signature to prove arena validation, and distinguishes that from ordinary
capacity exhaustion. Handle-table coverage similarly asserts growth failure
under arena exhaustion, shrink rejection across a live high handle, the
reserved count boundary, and recovery after the constraint is removed.
The disposable-media probe additionally proves that rename cannot cross from
A: to B:, and checks invalid-drive handling before performing successful media
ID get/set/readback. IOCTL argument coverage distinguishes invalid selectors,
unsupported flag data, invalid handles, and absent drives.
Country and code-page failures run in two explicit environments: without
NLSFUNC to assert DOS's invalid-function fallback, and with NLSFUNC resident to
assert COUNTRY.SYS lookup failures for unknown country and code-page records.

Run the inventory check with:

```sh
make test-coverage-manifest
make test-int21-error-coverage-manifest
make test-runtime-coverage-manifest
```

Contract evidence must include a runnable shell test referenced directly by
the CI workflow. The verifier rejects source-only evidence and tests that can
silently disappear from CI.

The normal `make test` and CI build enforce the completed contract gate:

```sh
python3 tests/test_coverage_manifest.py --require-complete
```

Every non-excluded dispatch entry now has focused contract evidence. Any new
uncovered or observation-only entry fails the normal test suite and CI.

The completed runtime inventory is enforced with:

```sh
python3 tests/test_runtime_coverage_manifest.py --require-complete
```

CI also sets `FAIL_ON_SKIP=1`; an unexpected host-test skip is therefore a
failure rather than being folded into the pass count.
