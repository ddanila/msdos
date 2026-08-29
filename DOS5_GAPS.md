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
| DOS in the HMA and programs/drivers in UMBs | Present on 386+ | Original HIMEM also supports 286 systems; repository HIMEM rejects pre-386 CPUs. |
| MS-DOS Shell and Task Swapper | Missing | No DOSSHELL UI, program groups, file manager, session switching, EGA save driver, or task-switcher API. |
| Command history and macros | Partial | DOSKEY provides resident history, macros, edit-mode configuration, and INT 2Fh services. Multi-entry Up/Down/F7/F8/F9 navigation remains incomplete. |
| Full-screen Editor and QBasic | Missing | No EDIT, QBASIC, BASIC runtime, help, or sample programs. EDLIN remains available. |
| Online command help | Partial | Shipped executable `/?` surfaces are tested, but HELP and its searchable help database are absent. |
| Delete/format recovery | Missing | MIRROR, UNDELETE, and UNFORMAT are absent. |
| Partitions up to 2 GiB | Present | Automated and interactive FDISK paths create and validate a near-2-GiB FAT16 partition on a sparse 2-GiB disk. |
| More than two hard disks | Unverified | FDISK's two-disk selection and mutation workflow is tested; the inherited implementation still models only two physical disks while the DOS 5 guide describes selecting higher disk numbers. |
| 2.88 MiB floppy support | Partial | FORMAT and the BIOS provide a tested 2.88 MiB path; SYS-created bootability and DRIVER.SYS geometry remain unverified. |
| Guided Setup with online help | Missing | SELECT is the inherited DOS 4 installer, not the DOS 5 SETUP/upgrade workflow. |
| Compressed installation media | Missing | No DOS `EXPAND.EXE`, DOS 5 compressed-file format workflow, or retail multi-disk installer. The host build tool named `compress` is unrelated. |
| DOS 5 version compatibility table | Partial | SETVER lists and edits a bounded resident kernel table, and EXEC applies add/update/delete changes immediately. Persistence across reboot and the original CONFIG.SYS loader remain absent. |

## Command inventory

### Missing commands

Every documented option of a missing command is necessarily unsupported.

| Command | Missing DOS 5 surface |
| --- | --- |
| `DOSSHELL` | Text/graphics Shell, `/T`, `/G`, resolution selection, `/B`, program groups, file operations, help, and task swapping. |
| `EDIT` | Full-screen text editor and `/B`, `/G`, `/H`, `/NOHI`; depends on QBASIC. |
| `EXPAND` | Extraction of one or more compressed distribution files. |
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
| `DOSKEY` | Resident history and macros; `/REINSTALL`, `/BUFSIZE`, `/MACROS`, `/HISTORY`, `/INSERT`, `/OVERSTRIKE`; `$1`-`$9`, `$*`, `$$`, `$G`, `$L`, `$B`, and queued `$T`; `4800h`/`4810h` APIs | Complete multi-entry Up/Down/Page/F7/F8/F9 and Alt-key interactive navigation. |
| `SETVER` | List, add, update, `/DELETE`/`/D`, and `/QUIET` against the resident kernel table; EXEC reports the selected version to matching programs | Persistent table storage and the CONFIG.SYS device-loader form. |
| `DIR` | Basic listing; `/P`, `/W`, `/B`, `/L`; `/A[:attributes]` with `D`, `R`, `H`, `A`, `S`, and negated selectors | `/O[:sortorder]`, `/S`, and `DIRCMD` defaults. These include DOS 5's recursive search and sorted-directory features. |
| `DISKCOPY` | Copy, `/1`, and `/V` read-back verification | No known DOS 5 option gap. |
| `FDISK` | Automated primary, extended, and logical creation; interactive display, near-2-GiB creation, active selection, deletion, and two-disk selection, with resulting MBR state validated | Selection of physical disks beyond disk 2 remains unsupported. |
| `FIND` | `/V`, `/C`, `/N`, `/I` | No known DOS 5 option gap. |
| `FORMAT` | Safe, `/Q`, and `/U` modes on floppy and FAT16 fixed media; hard-disk warning/errorlevel 5; `/1`, `/4`, `/8`, `/B`, `/F` including 2.88 MiB, `/N`, `/S`, `/T`, `/V`, and inherited private switches | Deterministic hardware-fault coverage for fixed-disk bad-cluster marking and UNFORMAT-compatible recovery metadata. |
| `SYS` | Default and explicit source paths; bootable target media | DOS 5 compatibility across hard-disk geometries, 2.88 MiB media, and upgrade scenarios is not established. |

### Present commands without a known parser omission

The following Microsoft DOS 5 commands or aliases are built and have focused
coverage. Their inclusion here means no missing documented top-level switch was
found; it does not claim every hardware, locale, or error-path permutation:

`APPEND`, `ASSIGN`, `BACKUP`, `BREAK`, `CALL`, `CHCP`, `CHDIR`/`CD`,
`CHKDSK`, `CLS`, `COMMAND`, `COMP`, `COPY`, `CTTY`, `DATE`, `DEBUG`,
`DEL`/`ERASE`, `DISKCOMP`, `ECHO`, `EDLIN`, `EMM386`, `EXE2BIN`, `EXIT`,
`FASTOPEN`,
`FC`, `FOR`, `GOTO`, `GRAFTABL`, `GRAPHICS`, `IF`, `JOIN`, `KEYB`, `LABEL`,
`LOADHIGH`/`LH`, `MEM`, `MKDIR`/`MD`, `MODE`, `MORE`, `NLSFUNC`, `PATH`,
`PAUSE`, `PRINT`, `PROMPT`, `RECOVER`, `RENAME`/`REN`, `REPLACE`, `RESTORE`,
`RMDIR`/`RD`, `SET`, `SHARE`, `SHIFT`, `SORT`, `SUBST`, `TIME`, `TREE`,
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
| `HIMEM.SYS` | Partial XMS 2.00 implementation | 286 support; `/HMAMIN`, `/NUMHANDLES`, `/INT15`, `/MACHINE`, `/A20CONTROL`, `/SHADOWRAM`, and `/CPUCLOCK`. The handle count is fixed and machine-specific A20 selection is automatic only. |
| `EMM386.EXE` | Partial DOS 5 EMM386 replacement | Driver-load `ON`/`OFF`/`AUTO`, `W=`, `FRAME=`, `Pn=`, `B=`, `L=`, `A=`, `H=`, and `D=` controls. The dual-purpose retail-named executable implements runtime status, `ON`, `OFF`, `AUTO`, `W=ON`, and `W=OFF`; driver loading implements pool size, page-frame selection, `I=`, `X=`, `RAM`, and `NOEMS`. |
| `EGA.SYS` | Missing | DOSSHELL Task Swapper display save/restore support. |
| `SETVER.EXE` | Partial (`SETVER.COM`) | Kernel-resident table and complete command editing work; the original dual-purpose EXE/device loader and persistent on-disk table remain. |
| `ANSI.SYS` | Present | No known DOS 5 `/X` or `/K` omission; exhaustive escape-sequence and adapter conformance is not complete. |
| `DISPLAY.SYS`, `PRINTER.SYS` | Present | Core code-page flow is tested; the full adapter/printer type and code-page matrix is unverified. |
| `DRIVER.SYS` | Present | Core logical-drive behavior is tested; all DOS 5 geometry values, including 2.88 MiB, are unverified. |
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

- `AH=30h` and SETVER provide immediate per-process fake versions through EXEC,
  but the filename database is not yet persisted or loaded through CONFIG.SYS.
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
  selection, deletion, and two-disk selection are established. Physical disks
  beyond disk 2 remain unsupported.
- FORMAT has a demonstrated 2.88 MiB path; SYS bootability and DRIVER.SYS
  geometry still need end-to-end coverage on that media.
- Fixed-disk formatting, bad-sector preservation, partition-boundary behavior,
  removable-media changes, and recovery after interrupted writes need broader
  DOS 5 differential tests.
- COUNTRY.SYS, KEYB, DISPLAY, PRINTER, and CPI files provide working NLS and
  code-page paths, but every retail keyboard, country, printer, and code-page
  combination has not been compared.
- Base DOS has pre-386 fallback coverage, but repository HIMEM cannot provide
  the original 286 XMS/HMA configuration.
- Hardware validation is dominated by QEMU. The recorded 86Box 486 gate does
  not replace testing on representative 8086/286/386 systems and controllers.

## Installation, documentation, and tooling gaps

The repository's native build, deterministic artifacts, strict manifests,
parallel tests, QEMU matrix, and CI are project capabilities that the retail
product did not expose. They are strengths, not DOS 5 compatibility features.
Remaining project-level gaps are:

- no DOS 5 SETUP, upgrade, uninstall, or retail multi-disk packaging flow;
- no DOS-side EXPAND utility or compatible compressed distribution;
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
2. **Distribution and installation.** Implement EXPAND and the DOS 5
   compressed-file format, then provide reproducible compressed media and a
   guided install/upgrade flow.
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
