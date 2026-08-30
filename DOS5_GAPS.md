# MS-DOS 5.0 compatibility gaps

This is the canonical inventory of known differences between retail Microsoft
MS-DOS 5.0 and this repository. It covers the operating-system API, commands,
drivers, user-facing product, and project tooling. A feature is not considered
complete merely because similarly named source exists.

## Baseline and status

The product baseline is Microsoft's 1991
[MS-DOS 5.0 User's Guide and Reference](https://bitsavers.trailing-edge.com/pdf/microsoft/msdos_5/Microsoft_-_MS-DOS_5.0_Users_Guide_and_Reference_1991.pdf).
The API baseline is Microsoft's 1991
[MS-DOS Programmer's Reference](https://bitsavers.trailing-edge.com/pdf/microsoft/msdos_5/Microsoft_-_MS-DOS_Programmers_Reference_1991.pdf).
Repository status comes from the live source, build inventories, and strict
coverage manifests under `tests/`.

The tables use these terms:

- **Present**: the documented surface exists; the listed evidence finds no
  known DOS 5 omission.
- **Partial**: useful behavior exists, but a known operation, option, value, or
  compatibility class is absent.
- **Missing**: the component or API family is not shipped.
- **Unverified**: source exists, but the complete DOS 5 contract has not been
  demonstrated. This is an evidence gap, not automatically an implementation
  defect.

OEM additions and localized editions can contain extra files. This inventory
uses the Microsoft retail English product and does not count later DOS 6
features such as DELTREE, DEFRAG, MEMMAKER, MOVE, or SCANDISK.

## Product-level gap summary

| DOS 5 feature | Repository status | Gap |
| --- | --- | --- |
| DOS in the HMA and programs/drivers in UMBs | Present on 386+; broader validation pending | HIMEM and EMM386 HMA/UMB integration is exercised end to end on 386+ systems. HIMEM execution on a 286 remains missing. |
| MS-DOS Shell and Task Swapper | Missing | No DOSSHELL UI, program groups, file manager, session switching, EGA save driver, or task-switcher API. |
| Command history and macros | Present | DOSKEY provides resident history, macros, edit modes, redirected input, INT 2Fh services, and the DOS 5 interactive history/editing keys. |
| Full-screen Editor and QBasic | Missing | No EDIT, QBASIC, BASIC runtime, help, or sample programs. EDLIN remains available. |
| Online command help | Partial | Shipped executable `/?` surfaces are tested, but HELP and its searchable help database are absent. |
| Delete/format recovery | Missing | MIRROR, UNDELETE, and UNFORMAT are absent. |
| Partitions up to 2 GiB | Present | Automated and interactive FDISK paths create and validate a near-2-GiB FAT16 partition on a sparse 2-GiB disk. |
| More than two hard disks | Present | FDISK models up to eight BIOS fixed disks; automated creation and interactive selection, display, and deletion are validated through disk 3. |
| 2.88 MiB floppy support | Present | FORMAT creates the standard FAT12 layout, SYS creates bootable media, and DRIVER.SYS `/F:9` provides DOS-side read/write access. |
| Guided Setup with online help | Partial | SETUP performs tested fresh and upgrade installs from the two-disk compressed set and produces a bootable fixed disk. Its concise `/?` help is not the retail interactive help system. |
| Compressed installation media | Present | `EXPAND.EXE` and the deterministic host encoder share the DOS 5 SZDD format; the build produces boot and compressed-data FAT12 images with `PACKING.LST`. The host SELECT panel tool named `compress` is unrelated. |
| DOS 5 version compatibility table | Present | SETVER edits the persistent table in SETVER.EXE, `DEVICE=SETVER.EXE` loads it during CONFIG.SYS, and EXEC applies the selected version. |

## Command inventory

### Missing commands

Every documented option of a missing command is necessarily unsupported.

| Command | Missing DOS 5 surface |
| --- | --- |
| `DOSSHELL` | Text/graphics Shell, `/T`, `/G`, resolution selection, `/B`, program groups, file operations, help, and task swapping. |
| `EDIT` | Full-screen text editor and `/B`, `/G`, `/H`, `/NOHI`; depends on QBASIC. |
| `HELP` | Command index, `HELP command`, and the DOS 5 help database. |
| `MIRROR` | Delete-tracking file, disk/partition recovery metadata, `/1`, `/T`, `/U`, and `/PARTN`. |
| `QBASIC` | BASIC editor/interpreter, `/B`, `/EDITOR`, `/G`, `/H`, `/MBF`, `/NOHI`, `/RUN`, online help, and bundled examples. |
| `UNDELETE` | File recovery, `/LIST`, `/ALL`, `/DOS`, and delete-tracking modes. |
| `UNFORMAT` | Disk recovery/reconstruction, `/J`, `/U`, `/L`, `/TEST`, `/P`, and `/PARTN`. |

`EGA.SYS`, required by DOSSHELL Task Swapper on EGA systems, is also absent.

### Present commands with known gaps

| Command | Implemented | Missing or incompatible DOS 5 behavior |
| --- | --- | --- |
| `ATTRIB` | `+R`, `-R`, `+A`, `-A`, `+H`, `-H`, `+S`, `-S`, `/S` | No known DOS 5 option gap. |
| `DISKCOPY` | Copy, `/1`, and `/V` read-back verification | No known DOS 5 option gap. |
| `FDISK` | Automated primary, extended, and logical creation; interactive display, near-2-GiB creation, active selection, deletion, and multi-disk selection, with resulting MBR state validated | No known DOS 5 workflow gap. |
| `FIND` | `/V`, `/C`, `/N`, `/I` | No known DOS 5 option gap. |
| `FORMAT` | Safe, `/Q`, and `/U` modes on floppy and FAT16 fixed media; bad-cluster marking; hard-disk warning/errorlevel 5; `/1`, `/4`, `/8`, `/B`, `/F` including 2.88 MiB, `/N`, `/S`, `/T`, `/V`, and inherited private switches | UNFORMAT-compatible recovery metadata belongs to Stage 4. |
| `SYS` | Default and explicit source paths; bootable 1.44 and 2.88 MiB targets; fresh and upgrade transfers across small and large FAT16 fixed-disk geometries | No known DOS 5 workflow gap. |

### Present commands without a known parser omission

The following Microsoft DOS 5 commands or aliases are built and have focused
coverage. Their inclusion here means no missing documented top-level switch was
found; it does not claim every hardware, locale, or error-path permutation:

`APPEND`, `ASSIGN`, `BACKUP`, `BREAK`, `CALL`, `CHCP`, `CHDIR`/`CD`,
`CHKDSK`, `CLS`, `COMMAND`, `COMP`, `COPY`, `CTTY`, `DATE`, `DEBUG`, `DOSKEY`,
`DEL`/`ERASE`, `DIR`, `DISKCOMP`, `ECHO`, `EDLIN`, `EMM386`, `EXE2BIN`, `EXIT`,
`EXPAND`, `FASTOPEN`,
`FC`, `FOR`, `GOTO`, `GRAFTABL`, `GRAPHICS`, `IF`, `JOIN`, `KEYB`, `LABEL`,
`LOADHIGH`/`LH`, `MEM`, `MKDIR`/`MD`, `MODE`, `MORE`, `NLSFUNC`, `PATH`,
`PAUSE`, `PRINT`, `PROMPT`, `RECOVER`, `RENAME`/`REN`, `REPLACE`, `RESTORE`,
`RMDIR`/`RD`, `SET`, `SETVER`, `SHARE`, `SHIFT`, `SORT`, `SUBST`, `TIME`, `TREE`,
`TYPE`, `VER`, `VERIFY`, `VOL`, and `XCOPY`.

Repository-only or inherited extensions such as `TRUENAME`, `FILESYS`,
`IFSFUNC`, `FLUSH13`, `SELECT`, and undocumented FORMAT switches do not close
any missing DOS 5 product component.

## CONFIG.SYS and driver gaps

All documented DOS 5 top-level CONFIG.SYS directives exist: `BREAK`,
`BUFFERS`, `COUNTRY`, `DEVICE`, `DEVICEHIGH`, `DOS`, `DRIVPARM`, `FCBS`,
`FILES`, `INSTALL`, `LASTDRIVE`, `REM`, `SHELL`, `STACKS`, and `SWITCHES`.
The repository additionally provides `INSTALLHIGH` and inherited directives.
Complete limit/error/order parity remains unverified outside the cases in
`tests/runtime_coverage.json`.

| Driver | Status | Missing DOS 5 surface |
| --- | --- | --- |
| `HIMEM.SYS` | Partial XMS 2.00 implementation | On 386+ systems it parses every documented DOS 5 option; HMA thresholds, 1-128 handles, INT 15h reservation, and generic A20 backends are tested. 286 execution and representative validation of machine-specific A20, shadow-RAM, and CPU-clock behavior remain missing. |
| `EMM386.EXE` | Partial DOS 5 EMM386 replacement | Driver-load `Pn=`, `B=`, `A=`, and `D=` controls remain. Driver and runtime loading implement `ON`, `OFF`, `AUTO`, `W=ON`, and `W=OFF`; driver loading also implements pool size, `M1`-`M14`, `FRAME=`, `/P`, `I=`, `X=`, `L=`, `H=`, `RAM`, and `NOEMS`. The effect of `W=ON` on real Weitek hardware is unverified. |
| `EGA.SYS` | Missing | DOSSHELL Task Swapper display save/restore support. |
| `SETVER.EXE` | Present | Persistent table loading through CONFIG.SYS and reboot-stable command edits are tested. |
| `ANSI.SYS` | Present | No known DOS 5 `/X` or `/K` omission; exhaustive escape-sequence and adapter conformance is not complete. |
| `DISPLAY.SYS`, `PRINTER.SYS` | Present | Core code-page flow is tested; the full adapter/printer type and code-page matrix is unverified. |
| `DRIVER.SYS` | Present | Core logical-drive behavior and `/F:9` 2.88 MiB geometry are tested; the remaining DOS 5 geometry matrix is unverified. |
| `RAMDRIVE.SYS`, `SMARTDRV.SYS` | Present | Core media/cache behavior exists; the complete memory-provider, cache-size, and hardware matrix is unverified. |

The shipped `VDISK.SYS`, `XMA2EMS.SYS`, and `XMAEM.SYS` are inherited
compatibility components, not substitutes for the missing DOS 5 items above.

## API and binary compatibility gaps

### Kernel API

The live `INT 21h` dispatcher and its error map are source-derived and checked
by `tests/int21_coverage.json` and `tests/int21_error_coverage.json`. It includes
the DOS 5 true-version call `AX=3306h`, allocation strategies, and UMB link
control through `AH=58h`. No missing documented top-level INT 21h function is
currently known.

Known limitations remain:

- `AH=30h` and SETVER provide per-process fake versions through EXEC; the
  filename database is persisted and loaded through CONFIG.SYS.
- Network/server calls are present, but interoperability with a complete DOS 5
  network redirector stack is not established.
- List-of-Lists, PSP, SFT, CDS, DPB, country, and driver structures have focused
  tests, not a byte-for-byte audit of every DOS 5 internal field and flag.
- Critical-error handling, sharing, locking, redirector, and asynchronous paths
  have representative contracts rather than exhaustive cross-product coverage.

### Multiplex and task-switching APIs

- DOSKEY `INT 2Fh/4800h` installed-state and `4810h` command-line service are
  implemented and runtime-tested.
- Task-switcher `INT 2Fh/4B01h` through `4B05h`: notification-chain building,
  switcher detection/ID allocation/free, and instance-data discovery.
- Task-switcher notification functions `0000h` through `0007h` and service
  functions `0000h` through `0006h`, including session suspend/resume,
  instance data, memory-region tests, and API-chain management.

The DOSKEY services are present. DOSSHELL/Task Swapper services remain absent
and must not be represented by no-op stubs if compatibility is claimed.

### XMS, EMS, and device APIs

- The repository HIMEM exposes XMS 2.00 HMA, A20, handle, move, lock, resize,
  and UMB calls. Its public function set is substantially present, but DOS 5
  configuration semantics, 286 execution, and the complete error/timing matrix
  remain gaps.
- EMM386 contains the LIM EMS dispatcher through the 4.0 function range and
  focused allocation, mapping, save/restore, and warm-boot tests. Complete LIM
  4.0 semantic conformance and third-party application compatibility are still
  unverified.
- Strict manifests account for every source-declared request command of shipped
  drivers. That proves coverage of this tree, not equivalence for missing DOS 5
  drivers or unsupported hardware.

## Storage, locale, and hardware gaps

- FDISK's automated and interactive near-2-GiB creation, display, active
  selection, deletion, and multi-disk selection are established. The bounded
  implementation supports up to eight BIOS fixed disks and is exercised
  through disk 3.
- FORMAT, SYS, DRIVER.SYS, and the BIOS have end-to-end 2.88 MiB FAT12
  coverage, including DOS-side I/O and bootability.
- Fixed-disk and removable formatting, partition-boundary behavior, and SYS
  upgrades have focused coverage. Recovery metadata and interrupted-write
  reconstruction belong to Stage 4.
- COUNTRY.SYS, KEYB, DISPLAY, PRINTER, and CPI files provide working NLS and
  code-page paths, but every retail keyboard, country, printer, and code-page
  combination has not been compared.
- HIMEM's documented configuration semantics have focused tests on 386+
  systems. Its move engine currently requires a 386, so 286 execution remains
  an implementation gap rather than only an acceptance-test gap.
- Hardware validation is dominated by QEMU. The recorded 86Box 486 gate does
  not replace testing on representative 8086/286/386 systems and controllers.

## Installation, documentation, and tooling gaps

The repository's native build, deterministic artifacts, strict manifests,
parallel tests, QEMU matrix, and CI are project capabilities that the retail
product did not expose. They are strengths, not DOS 5 compatibility features.
Remaining project-level gaps are:

- no uninstall workflow or reproduction of the exact retail disk layout and UI;
- no user manual/help corpus for the implemented commands beyond `/?` output;
- no automated differential runner against user-supplied genuine DOS 5 media;
- no CI-hosted 286/386/486 hardware-model matrix beyond QEMU and the separately
  reproducible 86Box acceptance run;
- host tools support Linux x86-64 and macOS arm64, not Windows or other hosts;
- builds depend on pinned custom JWasm, Open Watcom, and kvikdos forks, so each
  tool update still requires the complete reproducibility/runtime gate.

## Delivery stages

The compatibility work is split into four independently useful stages:

1. **Core command and runtime compatibility.** Complete FDISK workflows and
   2 GiB boundaries, remaining DIR behavior, fixed/removable FORMAT and SYS
   cases, persistent SETVER loading, DOSKEY navigation, and EMM386 runtime
   control.
2. **Distribution and installation (complete).** EXPAND, the DOS 5
   compressed-file format, reproducible two-disk media, and tested guided
   fresh-install/upgrade flows are present.
3. **Memory, locale, and hardware breadth.** Complete HIMEM configuration and
   286 support, EMM386 driver-load options, media geometries, NLS combinations,
   and representative 286/386/486 hardware validation.
4. **Help and recovery.** Add the HELP command/database and the MIRROR,
   UNDELETE, and UNFORMAT recovery workflow, including recovery metadata and
   interrupted-write tests.

DOSSHELL/Task Swapper and EDIT/QBASIC are separate product-scale projects and
are not hidden inside these four stages. EGA.SYS belongs with Task Swapper if
that project is accepted.

Update this file whenever a listed gap closes or a new source/reference
difference is demonstrated. Machine-readable manifests remain authoritative
for the interfaces that this repository currently claims to cover.
