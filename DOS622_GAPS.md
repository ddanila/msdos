# MS-DOS 6.22 compatibility gaps

This is the canonical plan for moving the current DOS 5-compatible system to
the retail English MS-DOS 6.22 surface. [DOS5_GAPS.md](DOS5_GAPS.md) remains
the detailed inventory for inherited DOS 5 behavior; this file records the
6.22 delta and the order in which it should be closed.

## Baseline and scope

The product baseline is Microsoft's 1994
[MS-DOS 6.22 User's Guide](https://bitsavers.trailing-edge.com/pdf/microsoft/msdos_6.22/DOS_6.22_Users_Manual_1994.pdf),
especially its new-feature summary and command/driver appendix. Exact syntax
comes from the archived
[MS-DOS 6.22 online Help corpus](https://www.infania.net/misc/dos622help/).
Repository status comes from the live source, `distribution/files.json`, and
strict manifests under `tests/`.

Status means:

- **Present**: the documented 6.22 surface is implemented and covered.
- **Partial**: useful behavior exists, but listed 6.22 behavior is absent.
- **Missing**: no shipped implementation exists.
- **Separate epic**: part of 6.22, but intentionally planned independently.
- **Non-goal**: deliberately excluded and not counted toward completion.

OEM additions and the optional Supplemental Disk are outside the retail base
system. Windows-only companion applications are also outside this DOS project.
DOSSHELL and Task Swapper are permanent non-goals. QBASIC and the QBASIC-based
EDIT and Help UI form a separate epic; the present text Help command remains a
valid lightweight interface.

## Executive gap map

| Area | Status | Gap |
| --- | --- | --- |
| DOS identity and compatibility | Present | The kernel and true-version API identify 6.22, and SETVER ships the retail 6.2/6.22 default table. The `MSDOS5.0` FAT OEM identifier is correct for 6.22 and remains unchanged. |
| Startup and configuration | Partial | Configuration blocks, boot menus, and the `CONFIG` selection variable remain; F5/Shift bypass and F8 CONFIG/AUTOEXEC stepping are present. |
| Everyday command additions | Partial | `CHOICE`, `DELTREE`, `LOADFIX`, and `MOVE` are present; overwrite policy additions to `COPY` and `XCOPY` remain. |
| Disk health and performance | Missing | `SCANDISK` and `DEFRAG`; no ScanDisk repair log or undo flow. |
| Memory optimization | Partial | Strong DOS 5 HMA/UMB base, but not the complete DOS 6 EMM386/MEM/loader contract or `MEMMAKER`. |
| SMARTDrive | Partial | A DOS 5 block driver and control helper exist, not the DOS 6 dual-purpose `SMARTDRV.EXE` cache interface and write-behind behavior. |
| Diagnostics and power | Missing | `MSD` and the `POWER.EXE` driver/command. |
| Machine-to-machine and CD-ROM access | Missing | `INTERLNK.EXE`, `INTERSVR.EXE`, and `MSCDEX.EXE`. |
| Backup | Missing | The shipped DOS 5 `BACKUP`/`RESTORE` pair does not replace Microsoft Backup. |
| Anti-virus | Missing | `MSAV` and resident `VSAFE`. |
| Drive compression | Separate epic | No DriveSpace loader, driver, CVF implementation, manager, integration, or API. |
| QBASIC and Editor | Separate epic | No BASIC interpreter/IDE or QBASIC-backed `EDIT`; full-screen 6.22 Help shares technology with this epic. |
| DOSSHELL and Task Swapper | Non-goal | Will not be implemented; `EGA.SYS` and the Shell task-switching UI/API are excluded with it. |

## Commands and user-visible options

Every option below is unsupported unless explicitly marked partial. Unchanged
DOS 5 commands inherit their status from `DOS5_GAPS.md`.

| Command | Status | Missing 6.22 surface |
| --- | --- | --- |
| `CHOICE` | Present | Prompt, `/C[:]choices`, `/N`, `/S`, `/T[:]choice,seconds`, key-index errorlevels, and redirected input are covered. |
| `DEFRAG` | Missing | Full-screen and command-line operation; `/F`, `/U`, `/S[:]order`, `/B`, `/SKIPHIGH`, `/LCD`, `/BW`, `/G0`, `/H`, documented errorlevels, progress/error reporting, and safe interruption. |
| `DELTREE` | Present | Recursive and wildcard deletion, multiple targets, protected attributes, prompting, and `/Y` are covered. |
| `DRVSPACE` | Separate epic | Interactive and command-line DriveSpace manager; `/AUTOMOUNT`, `/CHKDSK`, `/COMPRESS`, `/CREATE`, `/DELETE`, `/FORMAT`, `/INFO`, `/MOUNT`, `/RATIO`, `/SIZE`, `/UNCOMPRESS`, `/UNMOUNT`, host-drive swapping, and the driver/format/API integration listed below. |
| `FASTHELP` | Present | Compact command list/topic interface backed by the lean text Help database. |
| `INTERLNK` | Missing | Client installation/status, drive and printer redirection, server discovery, and the driver options and transports listed below. |
| `INTERSVR` | Missing | Serial/parallel file and printer server, `/B`, `/V`, `/LPT`, `/COM`, `/X`, drive selection, connection status, and client bootstrap transfer. |
| `LOADFIX` | Present | Placement above the first 64 KiB, argument forwarding, and child exit propagation are covered. |
| `MEMMAKER` | Missing | Express/custom analysis, reboot passes, CONFIG.SYS/AUTOEXEC.BAT rewriting, undo, batch/session modes, `/B`, `/T`, `/UNDO`, `/W`, and swap-drive control. |
| `MOVE` | Present | Files, directory rename, multiple sources, prompts, `/Y`, `/-Y`, `COPYCMD`, cross-drive recursion, and errorlevels are covered. |
| `MSAV` | Missing | Interactive scanning and `drive:`, `/S`, `/C`, `/R`, `/A`, `/L`, `/N`, `/P`, `/F`, `/VIDEO` and its display switches; removal, reports, checksums, exit code 86, configuration, and signature database. |
| `MSBACKUP` | Missing | Interactive backup/restore/compare, `.SET` setup and catalog files, full/incremental/differential sets, compression, verification, scheduling, spanning, destination devices, and `setup_file`, `/BW`, `/LCD`, `/MDA`. DOS 5 `RESTORE` remains responsible for old `BACKUP` sets. |
| `MSCDEX` | Missing | CD-ROM redirector installation and `/D`, `/L`, `/M`, `/E`, `/S`, `/V`, `/K`; driver discovery, ISO 9660 access, audio/control IOCTLs, and multiplex API. A hardware-specific CD-ROM device driver remains external. |
| `MSD` | Missing | Interactive/report diagnostics and `/B`, `/I`, `/F`, `/P`, `/S`; hardware, memory, IRQ, driver, disk, video, network, and OS reporting. |
| `POWER` | Missing | Installable driver plus runtime status/on/off and conservation levels (`ADV`, `STD`, `REG`, `MIN`, `MAX` as applicable), idle detection, and APM coordination. |
| `SCANDISK` | Missing | FAT12/FAT16 and surface analysis, interactive repair, `/ALL`, `/AUTOFIX`, `/CHECKONLY`, `/CUSTOM`, `/FRAGMENT`, `/MONO`, `/NOSAVE`, `/NOSUMMARY`, `/SURFACE`, `/UNDO`, `SCANDISK.INI`, repair log, undo disk, and compressed-volume integration. |
| `SMARTDRV` | Partial | Replace the shipped DOS 5 `SMARTDRV.SYS` interface with DOS 6 `SMARTDRV.EXE`: runtime install/status, per-drive read/write cache selection, cache sizing, `/B`, `/C`, `/E`, `/F`, `/L`, `/N`, `/Q`, `/R`, `/S`, `/V`, `/X`, write-behind flush, shutdown safety, CD-ROM caching, and the CONFIG.SYS compatibility-driver mode. |
| `VSAFE` | Missing | Resident monitoring options `1` through `8`, `/NE`, `/NX`, `/Ax`, `/Cx`, `/N`, `/D`, `/U`, hotkeys, checksums, network monitoring, and MSAV signature sharing. |

Known gaps in commands already shipped:

| Existing command | Missing 6.22 behavior |
| --- | --- |
| `COMMAND` | `/K`, `/Y` batch single-stepping, F5/Shift startup bypass, and F8 CONFIG/AUTOEXEC confirmation are present. Selected-configuration propagation remains. |
| `COPY` | Present: `/Y`, `/-Y`, overwrite prompting, `COPYCMD`, and command-line precedence are covered. |
| `DIR` | `/C[H]` compression ratios and `O:C`/`O:-C`; these depend on DriveSpace. |
| `EMM386` | The DOS 6 enhanced automatic EMS/UMB behavior and remaining 6.22 parser/API/hardware differences need a reference differential audit. Existing DOS 5 modes and memory regions are a strong base. |
| `FORMAT` | `/C` retests previously marked bad clusters, while normal formatting preserves their marks. Compressed/host-drive interaction depends on the DriveSpace epic. |
| `HELP` | The current searchable text database lacks the retail full-screen hypertext UI, complete 6.22 topic corpus, mouse navigation, syntax/notes/examples links, and full-text search. The UI belongs to the QBASIC epic; lean text topics can grow with each stage. |
| `HIMEM.SYS` | XMS 2.00 and DOS 5 options exist; exact 6.22 version/API identity, defaults, diagnostics, and machine-option parity remain unverified. |
| `MEM` | Existing `/C`, `/D`, `/F`, `/M`, and `/PROGRAM` views need differential validation against DOS 6.22's enhanced reports and EMM386 integration. |
| `SETVER` | Retail 6.2/6.22 defaults, persistent editing, driver loading, and 6.22 identity behavior are covered. |
| `UNDELETE` | DOS protection modes exist, but the enhanced 6.22 UI/configuration and Windows companion are absent. The Windows companion is out of scope. |
| `XCOPY` | Present: `/Y`, `/-Y`, `COPYCMD`, overwrite prompts, and hidden/system exclusion are covered. |

## Startup, drivers, and APIs

### CONFIG.SYS and boot

CONFIG.SYS `SET` environment propagation and `NUMLOCK=ON|OFF` are present.
Missing 6.22 configuration behavior:

- named configuration blocks plus `[menu]` and `[common]`;
- `MENUITEM`, `MENUDEFAULT`, `MENUCOLOR`, `SUBMENU`, and `INCLUDE`;
- the `CONFIG` environment variable passed to AUTOEXEC.BAT;
- section selection, invalid-menu recovery, timeouts, nesting, and common-section
  ordering;
- 6.22 parsing limits, diagnostics, and interaction with `DEVICEHIGH`,
  `INSTALL`, `SHELL`, and AUTOEXEC.BAT.

`DEVICEHIGH /L:region[,minsize][;...] /S` and the corresponding `LOADHIGH`
region grammar are already implemented and covered. `INSTALLHIGH` is a useful
repository extension, not a retail 6.22 directive.

### New driver and multiplex surfaces

- `INTERLNK.EXE`: block/character device behavior, serial and parallel
  transports, `/DRIVES`, `/NOPRINTER`, port selection, redirector semantics,
  drive/printer mapping, and unload/reconnect behavior.
- `POWER.EXE`: device request interface, runtime command interface, idle/power
  policy, and hardware fallback.
- `SMARTDRV.EXE`: DOS 6 device mode, cache command/multiplex interface,
  write-behind consistency, and CD-ROM cooperation.
- `MSCDEX.EXE`: redirector and `INT 2Fh` CD-ROM extensions, ISO 9660/Joliet-era
  8.3 presentation expected by 6.22, IOCTL forwarding, and network sharing.
- DriveSpace: boot-time `DRVSPACE.BIN`, `DRVSPACE.SYS`, `DRVSPACE.EXE`, CVF
  mount/compress/uncompress/resize, drive-letter swapping, `DRVSPACE.INI`,
  DoubleSpace coexistence/conversion, compression-ratio queries, IOCTL and
  multiplex APIs, and crash-consistent metadata.

The documented DOS 6.22 kernel `INT 21h` surface is largely inherited from DOS
5. The version result, internal structure revisions, redirector interactions,
startup state, and new multiplex consumers still need reference-derived binary
contracts. FAT32, VFAT long filenames, Windows 9x DOS extensions, and protected
mode interfaces are not part of the 6.22 target.

## Installation, media, and project tooling

The current deterministic build, manifests, emulators, and CI remain suitable.
Closing the 6.22 product gap additionally requires:

- 6.22 boot/install/upgrade media and versioned SETUP behavior;
- SETUP configuration for SMARTDrive, memory management, Undelete, Backup, and
  Anti-Virus, with DriveSpace added only in its epic;
- upgrade, rollback/uninstall-disk, emergency/startup-disk, and compressed-drive
  recovery flows;
- a complete 6.22 text Help database as components land;
- clean-room black-box captures from user-supplied genuine 6.22 media for every
  new parser, errorlevel, file-format, API, and state transition;
- strict command, driver-request, interrupt/multiplex, artifact, and runtime
  manifests for each new shipped component;
- differential FAT12/FAT16 corruption corpora for ScanDisk and Defrag, transport
  fault injection for Interlnk, and power/cache interruption tests;
- if DriveSpace is accepted, independently generated CVF corpora and torn-write,
  low-space, host-drive, boot, repair, and conversion matrices.

Exact Microsoft disk layout, timestamps, byte-identical binaries, Windows-only
tools (`MWBACKUP`, `MWAV`, and Windows Undelete), bundled Windows integration,
and Supplemental Disk utilities are not compatibility requirements.

## Delivery stages

1. **DOS 6.22 platform contract.** Complete the SETVER defaults; implement
   configuration blocks, boot menus, `CONFIG`, startup
   bypass/confirmation, `COMMAND /K` and `/Y`; add `CHOICE`, `DELTREE`,
   `LOADFIX`, `MOVE`, COPY/XCOPY overwrite policy, and complete lean Help topics.
2. **Core maintenance and memory.** Add `SCANDISK` and `DEFRAG`; close DOS 6.22
   MEM, HIMEM, EMM386, DEVICEHIGH/LOADHIGH, and FORMAT differences; then build
   `MEMMAKER` on the proven configuration and memory-region model.
3. **Caching, diagnostics, and connectivity.** Replace the DOS 5 SMARTDrive
   product surface, then add `MSD`, `POWER`, `INTERLNK`/`INTERSVR`, and `MSCDEX`.
   This stage makes the system broadly useful without the large application
   suites.
4. **Data-protection suites.** Add Microsoft Backup compatibility and finish
   the DOS 6 Undelete product surface. Treat `MSAV`/`VSAFE` as optional within
   this stage: their historical signature database has little modern security
   value, but their interfaces remain recorded above.
5. **DriveSpace epic.** Implement the CVF format, boot loader, driver, manager,
   APIs, DIR/SCANDISK/DEFRAG/SYS/SETUP integration, DoubleSpace transition, and
   recovery testing as one explicit, separately accepted milestone.

The QBASIC/EDIT/full-screen Help epic is independent of these stages. DOSSHELL,
Task Swapper, and their EGA support remain excluded permanently.

Update this file whenever a gap closes or a reference comparison discovers a
new difference. Machine-readable manifests remain authoritative for what the
repository currently claims to ship and test.
