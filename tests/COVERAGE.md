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
Error exclusions must cite the live source files that prove a path is absent,
stubbed, or dependent on an unshipped subsystem. In particular, historical
allowed-error rows are not treated as proof that the built local FAT kernel can
emit every listed result: disabled extended-attribute code, nonallocating DUP2,
fixed MCB mappings, and operational-IFS-only paths are recorded explicitly.

`runtime_coverage.json` applies the same levels to every shipped or built
runtime `.COM`, `.EXE`, and `.SYS` component and to every directive parsed from
the kernel's live `COMTAB` in `BIOS/SYSINIT2.ASM`. Its verifier derives both
sets from the source and Makefile, rejecting omitted or stale entries.

`dos_interrupt_coverage.json` covers the DOS-initialized vector surface outside
the INT 21h dispatch table. Its verifier checks the live `MSINIT.ASM` vector
setup for INT 20h through INT 29h and the installed INT 2Fh handler. Focused
contracts currently include old-style termination and residency, process
termination and critical-error callbacks, and absolute sector reads and writes
on disposable images; callback or multiplex behavior that is only observed is
kept visibly incomplete.
The clean synchronous-vector probe also verifies INT 29h through BIOS cursor
state and INT 2Fh through the uninstalled SHARE, redirector, and NLSFUNC checks
plus DOS's own installation signature, before any resident utility can replace
the multiplex chain.
The asynchronous-vector probe connects through a private UNIX serial socket,
waits for an explicit guest-ready marker, and deliberately withholds input.
This proves DOS calls INT 28h from its actual console polling loop; the host
then sends Ctrl-C followed by `X`, proving one INT 23h callback and successful
continuation. Both vectors are restored before the probe exits.

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
`test_ifsfunc_filesys_qemu.sh` extends the same fixture through the runtime
lifecycle: IFSFUNC installs its DOS interface, FILESYS attaches the fixture to
C:, reports its exact `TESTIFS` name, and detaches it. A post-detach probe reads
the resident header and requires exactly one ATTSTART, ATTSTAT, and ATTEND
request, so command completion alone cannot satisfy the contract. Duplicate
attachment, an unknown IFS, and repeated detachment must return failure without
reaching the driver; a final status query must report an empty attachment list.

`test_config_multitrack_qemu.sh` attaches separate FAT16 IDE images to parallel
ON and OFF boots. An INT 13h observer proves the same ten-sector absolute read
is coalesced across a track only when MULTITRACK is enabled.
Each probe also writes an unchanged sector back through INT 26h and requires a
successful observed BIOS write, keeping all mutation confined to its private
disk copy.

Driver contracts similarly require an effect after installation. For example,
`test_ansi_driver_qemu.sh` sends an ANSI cursor-position sequence through DOS
and checks the resulting coordinates through the BIOS. Its interactive probe
also resolves the live ANSI header and verifies all 13 pass-through request
statuses against the lower BIOS CON driver. The first command beyond ANSI's
table is rejected through the same chain, guarding the dispatch bound that
previously indexed into adjacent escape-command data.
`test_display_chain_qemu.sh` installs DISPLAY above ANSI and BIOS CON. It
repeats visible output and controlled blocking, nonblocking, and flush effects
through all three layers, then resolves DISPLAY's first live `CON` header and
asserts every pass-through request status. Reserved requests 17 and 18 and the
first out-of-table request are kept as exact compatibility contracts rather
than being inferred from the individual lower driver.
The combined driver boot also exercises RAMDRIVE and VDISK through two
independent paths. DOS file I/O must return exact payload markers, while a
guest probe checks each 64 KiB BPB field by field, writes and reads the final
sector using that driver's distinct sector size, and rereads RAMDRIVE after a
VDISK mutation to prove the two memory-backed devices are isolated. The probe
also resolves each driver through its live DOS DPB, calls its strategy and
interrupt entries directly, and asserts exact success or unknown-command
status for every otherwise-reachable no-op or unsupported request. A request
one command beyond each table proves the dispatch bound as well.
Resident utility contracts follow the same rule. `test_graftabl_qemu.sh`
derives the complete 128-character bitmap oracles from the maintained font
sources, then switches 437 to 850 and back in one DOS session. After every
switch it verifies GRAFTABL's INT 2Fh handler, the INT 1Fh vector, and all 1,040
resident bytes including the code-page identifier and language metadata.
`test_driver_sys_qemu.sh` installs a logical drive backed by a separate second
floppy and handles the driver's media prompt through QMP. The guest verifies
exact bytes read through the new drive letter, creates a second file through
that mapping, and reads it back. After QEMU exits, the host independently reads
both files from the physical backing image and requires their exact payloads,
proving that DRIVER.SYS forwards and persists both reads and writes.
`test_printer_driver_qemu.sh` loads the 4201 printer definition and proves its
code-page control path by preparing, selecting, and querying code page 850.
`test_print_spooler_qemu.sh` then exercises the ordinary data path: PRINT queues
a deterministic text file, a guest probe polls the resident INT 2Fh queue until
it is empty, and QEMU captures LPT1. The host requires the exact source bytes
and PRINT's final form feed, proving delivery through the installed PRINTER.SYS
chain rather than merely observing successful queue commands.
`test_graphics_print_qemu.sh` installs GRAPHICS from its DOS-record profile,
draws a deterministic asymmetric CGA pattern, invokes the resident INT 5h
Print Screen handler, and captures LPT1. The host requires the exact 17,781-byte
stream and all 25 graphics escape blocks. This also guards the `.PRO` CRLF
checkout rule: an LF-only profile is rejected by the actual DOS parser and
cannot reach the print assertion.
`test_fastopen_cache_qemu.sh` creates a deep fixed-disk fixture through DOS,
proves the FASTOPEN multiplex hook is absent before installation and present
afterward, and reads the exact payload to populate the pathname cache. It then
renames the cached directory, requires the stale pathname to fail, reads the
payload through the new pathname, renames it back, and reads it again. This
guards subtree invalidation as well as installation; it exposed the resident
cache retaining renamed directories that had cached children.
`test_smartdrv_flush_qemu.sh` attaches a fixed disk and uses FLUSH13 to assert
SMARTDRV status, disable/enable transitions, policy changes, and an explicit
successful flush. A purpose-built guest probe also writes and reads back a
deterministic 512-byte absolute sector through the installed cache. The same
probe resolves the resident `SMARTAAR` header, directly verifies every
otherwise-reachable no-op and unknown-command request status, and rejects the
first command beyond the live dispatch table. Extended
status must show that real I/O populated cache tracks while the shipped
write-through implementation kept them clean; after a clean guest exit, the
host independently requires every byte of that sector on the backing image.
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
Rejected `/T`/`/N`, `/C`, and `/Z` cases must also set a nonzero DOS errorlevel
and leave every byte of their initially zeroed private target image unchanged.

`test_recover.sh` covers both public RECOVER modes on disposable media. File
mode must preserve the exact original payload. Whole-drive mode destroys only
a private B: directory, proves both original names are removed, and reads back
the payloads from the generated `FILEnnnn.REC` chains. The guest exits through
the test-only QEMU port after persistence checks are ready, avoiding a fixed
interactive timeout.

`test_backup_restore.sh` treats existence as insufficient evidence for a
successful archive round trip. Binary FC comparisons assert exact payloads for
archive-bit selection, append preservation, basic restore, recursive restore,
and restore-if-missing. Its negative date/time/filter cases still require the
documented nonzero errorlevel and no-match behavior.

`test_chkdsk_fix.sh` injects a three-cluster orphan chain with a distinct byte
pattern in every cluster. After `/F`, the generated `FILE0000.CHK` must match
the complete injected chain by SHA-256, an ordinary referenced file must remain
byte-exact, and a second read-only CHKDSK pass must report a clean filesystem.

`test_fdisk.sh` reads the resulting MBR and EBR as structures rather than only
checking partition type bytes. It bounds the requested 5 MB and 10 MB sizes by
one geometry unit, proves non-overlap and extended-partition containment,
checks CHS/LBA agreement and the EBR signature, and requires unused entries to
remain zero in the primary-only regression case.

`test_diskcomp_diskcopy.sh` independently compares a dedicated source and
target image on the host after DOS reports a successful physical copy. Every
byte must match except BPB offsets 39–42, where DISKCOPY is required by its
live source contract to generate a distinct volume serial number. DISKCOMP's
own matching and deliberately mismatching paths remain separate assertions.
The parser contract follows the live synonym tables: DISKCOMP accepts `/1`
and `/8` separately and together, while repeating either consumed synonym is
rejected. Both tools reject an unknown switch and a third drive with
errorlevel 1 and their exact parser diagnostic classes.

`test_sys.sh` boots media produced by SYS and separately attaches a formatted
B: image read-only. The failure case must return a nonzero DOS errorlevel,
must never print the success diagnostic, and must leave the complete target
image SHA-256 unchanged.
Both source forms are exercised: `SYS B:` uses the default source, while
`SYS A: B:` names its source drive explicitly. Parser and target validation separately
reject missing operands, switches, excess operands, the default target drive,
and an invalid drive with their exact diagnostics and nonzero errorlevels.

`test_label.sh` covers the command-line boundary in addition to interactive
set/delete behavior. A 12-character input must persist only its first eleven
characters. An invalid-character input must enter LABEL's documented recovery
prompt; submitting an empty replacement and declining deletion must preserve
the prior on-disk label.

`test_select.sh` drives SELECT through its BIOS keyboard and video interfaces.
Besides the stub transition and invalid-command-line return path, the valid
MENU workflow must reach Welcome, cancel to the Exit panel, decline exit, and
return to Welcome. This proves a reversible UI state transition and recovery
without starting an installation or mutating a target disk.

Command-mode depth is derived from live parser definitions where possible.
SORT tests both endpoints of its declared `/+n` range (1 through 65535), the
adjacent rejected values, and an unknown switch. TREE exercises `/F` and `/A`,
then proves that its parser's deliberate removal of a consumed synonym rejects
a duplicate switch as well as an unknown one. Negative cases require both the
expected parser diagnostic and errorlevel 1.
FIND covers all eight combinations of its `/V`, `/C`, and `/N` flags and proves
that count mode takes precedence over line numbering. Its distinct parser
policy is also pinned: duplicate recognized switches are idempotent, while an
unknown switch and missing or extra quoted search strings return the exact
diagnostic class and errorlevel 2.
FC coverage distinguishes explicit `/B` from automatic binary selection by
extension and checks every source-level binary/line incompatibility (`/L`,
`/N`, and numeric resynchronization). Its actual `/LBn` syntax is exercised at
one and twenty lines; `/LB` without digits pins the historical default-buffer
fallback, while `/LB0` must fail through the allocation path. Unknown switches
and excess filenames require usage output and errorlevel 1.
COMP's ordinary comparisons verify exact mismatch offsets and byte values,
different sizes, missing files, and its ten-error cutoff. A real-DOS serial
workflow additionally covers its stateful tail prompt: `N` returns to the
calling batch, while `Y` requests exactly one fresh filename pair, performs a
second comparison in the same process, and accepts a final `N`.
`test_more_paging_qemu.sh` drives MORE through the real DOS console with sixty
uniquely numbered lines. It requires exactly two `-- More --` boundaries,
injects an extended two-byte key at one and an ordinary raw key at the other,
and then verifies every line appeared exactly once and in order before MORE
returned to its caller.
MEM's complete two-switch surface is covered at the parser as well as output
level. `/PROGRAM` and `/DEBUG` each produce detailed reports and accept folded
case, while every mixed or duplicate second switch is rejected. Unknown
switches and forbidden positional operands require their distinct parser
diagnostics and errorlevel 1.
EXE2BIN fixtures exercise all three conversion algorithms with host-side byte
oracles: BIN copies its load image, COM removes exactly the initial `100h`
bytes, and one relocation adds the interactively supplied base segment to its
target word. Separate malformed-signature, nonzero-SS, and invalid-IP headers
must each report that conversion is impossible and leave no output file.

ATTRIB metadata transitions operate on a disposable copy rather than a source
file. The test covers combined set/clear operations, recursive enumeration,
the exact missing-file and invalid-switch failure classes with nonzero exits,
payload SHA-256 preservation, and attribute cleanup before removing the copy.

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
It separately asserts missing-parent behavior for find-first, create-temporary,
and create-new, while wildcard leaves exercise the distinct file-not-found
mapping of ordinary create and create-new.
It also covers local access-mode enforcement by opening a directory, reading a
write-only handle, writing a read-only handle, deleting a temporarily read-only
file, and rejecting non-changeable attribute bits. Every changed attribute and
opened handle is restored or released before the probe completes.
The file/memory probe separately fills the default JFT and configured SFT so
duplicate and all create/open variants return their exact capacity errors.
The process probe covers EXEC success and seven distinct failure contracts. It
rejects invalid modes, missing files and parents, directories, unterminated
32 KiB environments, an exhausted system file table, and an exhausted memory
arena. It releases both constrained resources before a final successful child
execution, so the test also proves recovery rather than only observing errors.
It additionally creates and deletes a zero-byte executable image to exercise
the safe, explicit bad-format path before that final successful execution.
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
The SHARE-resident compatibility probe distinguishes an overlapping-range lock
violation from exhaustion of SHARE's finite lock-record pool, then releases
every acquired range. This exposed and now guards a SHARE defect where its
dispatcher replaced the capacity error with lock violation instead of
preserving error 36.
The media tests use separate writable and write-protected B: images. The latter
issues valid media-ID writes through both generic IOCTL and function 69h and
asserts access denied from the real block driver; its isolated CI job can run
in parallel with the writable metadata round trip.

Run the inventory check with:

```sh
make test-coverage-manifest
make test-int21-error-coverage-manifest
make test-runtime-coverage-manifest
make test-dos-interrupt-coverage-manifest
make test-device-request-coverage-manifest
```

`device_request_coverage.json` derives the command number and handler for each
explicit request table in the shipped installable drivers. It also records the
different forwarding models used by DRIVER.SYS and PRINTER.SYS. Source-backed
post-failed-INIT commands are separated from meaningful behavioral contracts.
Every reachable pass-through, no-op, and unsupported handler is exercised
through its installed strategy/interrupt interface. The normal test target
enforces this as a strict zero-gap gate.

Contract evidence must include a runnable shell test referenced directly by
the CI workflow. The verifier rejects source-only evidence and tests that can
silently disappear from CI.

The normal `make test` and CI build enforce the completed contract gate:

```sh
python3 tests/test_coverage_manifest.py --require-complete
python3 tests/test_int21_error_coverage.py --require-complete
```

Every non-excluded dispatch entry now has focused contract evidence. Any new
uncovered or observation-only entry fails the normal test suite and CI.

The completed runtime inventory is enforced with:

```sh
python3 tests/test_runtime_coverage_manifest.py --require-complete
```

CI also sets `FAIL_ON_SKIP=1`; an unexpected host-test skip is therefore a
failure rather than being folded into the pass count.
