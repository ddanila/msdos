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
| Startup and configuration | Partial | Named blocks, nested boot menus, ordered `INCLUDE`, `MENUCOLOR`, defaults/timeouts, keyboard recovery, and `CONFIG` propagation are present alongside F5/Shift bypass and F8 stepping. Reference diagnostics and selected-block interaction coverage remain. |
| Everyday command additions | Partial | `CHOICE`, `DELTREE`, `LOADFIX`, and `MOVE` are present; overwrite policy additions to `COPY` and `XCOPY` remain. |
| Disk health and performance | Partial | ScanDisk has a shipped FAT12/FAT16 logical-repair core, repair log, and stale-safe undo flow. Defrag has byte-preserving FAT12/FAT16 `/U` relocation, `/F` compaction, physical directory sorting, hidden/nested coverage, and reboot behavior. Remaining checks, interruption safety, surface recovery, and reference UI are listed below. |
| Memory optimization | Partial | Strong HMA/UMB base plus a reversible MemMaker startup-file/reboot workflow; measurement-driven custom placement and remaining DOS 6 EMM386/MEM/HIMEM differentials remain. |
| SMARTDrive | Partial | A DOS 5 block driver and control helper exist, not the DOS 6 dual-purpose `SMARTDRV.EXE` cache interface and write-behind behavior. |
| Diagnostics and power | Partial | `MSD` ships with interactive and report modes. POWER now has an installable driver, controller modes, INT 28h CPU-idle action, APM discovery, and status API; broader busy-device detection remains. |
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
| `DEFRAG` | Partial | `/U` relocates fragmented FAT12/FAT16 file chains into contiguous free runs; `/F` compacts movable clusters and `/S[:]order` physically sorts directory entries while preserving byte-exact files. Nested and hidden-file policy and `/B` reboot are covered. Divergent FAT copies, lost allocations, and invalid chains are refused; one mid-relocation interruption boundary is proven recoverable through ScanDisk. Remaining: meaningful display modes, broader interruption tests, exhaustive errorlevels, and the reference full-screen interface. |
| `DELTREE` | Present | Recursive and wildcard deletion, multiple targets, protected attributes, prompting, and `/Y` are covered. |
| `DRVSPACE` | Separate epic | Interactive and command-line DriveSpace manager; `/AUTOMOUNT`, `/CHKDSK`, `/COMPRESS`, `/CREATE`, `/DELETE`, `/FORMAT`, `/INFO`, `/MOUNT`, `/RATIO`, `/SIZE`, `/UNCOMPRESS`, `/UNMOUNT`, host-drive swapping, and the driver/format/API integration listed below. |
| `FASTHELP` | Present | Compact command list/topic interface backed by the lean text Help database. |
| `INTERLNK` | Missing | Client installation/status, drive and printer redirection, server discovery, and the driver options and transports listed below. |
| `INTERSVR` | Missing | Serial/parallel file and printer server, `/B`, `/V`, `/LPT`, `/COM`, `/X`, drive selection, connection status, and client bootstrap transfer. |
| `LOADFIX` | Present | Placement above the first 64 KiB, argument forwarding, and child exit propagation are covered. |
| `MEMMAKER` | Partial | Unattended Express rewriting, byte-exact backups and `/UNDO`, reboot plus `/SESSION`, `/SWAP`, `/W` status, memory-manager insertion, DEVICEHIGH/INSTALLHIGH, and eligible TSR `LH` conversion are live. Remaining: measured multi-pass placement and size ordering, interactive Custom choices, automatic session scheduling, Windows SYSTEM.INI handling, rollback fault injection, and exact retail UI/status behavior. |
| `MOVE` | Present | Files, directory rename, multiple sources, prompts, `/Y`, `/-Y`, `COPYCMD`, cross-drive recursion, and errorlevels are covered. |
| `MSAV` | Missing | Interactive scanning and `drive:`, `/S`, `/C`, `/R`, `/A`, `/L`, `/N`, `/P`, `/F`, `/VIDEO` and its display switches; removal, reports, checksums, exit code 86, configuration, and signature database. |
| `MSBACKUP` | Missing | Interactive backup/restore/compare, `.SET` setup and catalog files, full/incremental/differential sets, compression, verification, scheduling, spanning, destination devices, and `setup_file`, `/BW`, `/LCD`, `/MDA`. DOS 5 `RESTORE` remains responsible for old `BACKUP` sets. |
| `MSCDEX` | Missing | CD-ROM redirector installation and `/D`, `/L`, `/M`, `/E`, `/S`, `/V`, `/K`; driver discovery, ISO 9660 access, audio/control IOCTLs, and multiplex API. A hardware-specific CD-ROM device driver remains external. |
| `MSD` | Partial | A lean interactive/report implementation covers `/B`, `/I`, `/F`, `/P`, `/S` and core hardware, memory, IRQ, driver, FAT-drive geometry, SUBST/JOIN/network mappings, video, network, and OS reporting. Retail screen layout, exhaustive device detail, and reference-differential output remain. |
| `POWER` | Partial | The installable `POWER.EXE` driver and `POWER.COM` controller provide status, `OFF`, `STD`, `ADV`, and `ADV:MIN|REG|MAX`; the resident service uses INT 28h idleness for level-dependent CPU halts and APM idle calls when firmware is present. Remaining: keyboard-poll detection, disk/video/DOS busy tracking, exact APM lifecycle and reference diagnostics/API comparison. |
| `SCANDISK` | Partial | FAT12/FAT16 traversal, mirror and chain repair, lost-chain recovery, `/AUTOFIX`, `/CHECKONLY`, core prompting, repair logging, and byte-exact stale-safe `/UNDO` are live. Remaining: complete directory validation, occupied-cluster surface recovery, write/read surface verification, functional `/FRAGMENT`, full `SCANDISK.INI`, exact multi-drive/parser/UI behavior, broader corruption/fault corpora, and compressed-volume integration in the DriveSpace epic. |
| `SMARTDRV` | Partial | Replace the shipped DOS 5 `SMARTDRV.SYS` interface with DOS 6 `SMARTDRV.EXE`: runtime install/status, per-drive read/write cache selection, cache sizing, `/B`, `/C`, `/E`, `/F`, `/L`, `/N`, `/Q`, `/R`, `/S`, `/V`, `/X`, write-behind flush, shutdown safety, CD-ROM caching, and the CONFIG.SYS compatibility-driver mode. |
| `VSAFE` | Missing | Resident monitoring options `1` through `8`, `/NE`, `/NX`, `/Ax`, `/Cx`, `/N`, `/D`, `/U`, hotkeys, checksums, network monitoring, and MSAV signature sharing. |

Known gaps in commands already shipped:

| Existing command | Missing 6.22 behavior |
| --- | --- |
| `COMMAND` | `/K`, `/Y` batch single-stepping, F5/Shift startup bypass, F8 CONFIG/AUTOEXEC confirmation, and selected-configuration propagation are present. |
| `COPY` | Present: `/Y`, `/-Y`, overwrite prompting, `COPYCMD`, and command-line precedence are covered. |
| `DIR` | `/C[H]` compression ratios and `O:C`/`O:-C`; these depend on DriveSpace. |
| `EMM386` | The DOS 6 enhanced automatic EMS/UMB behavior and remaining 6.22 parser/API/hardware differences need a reference differential audit. Existing DOS 5 modes and memory regions are a strong base. |
| `FORMAT` | `/C` retests previously marked bad clusters, while normal formatting preserves their marks. Compressed/host-drive interaction depends on the DriveSpace epic. |
| `HELP` | The current searchable text database lacks the retail full-screen hypertext UI, complete 6.22 topic corpus, mouse navigation, syntax/notes/examples links, and full-text search. The UI belongs to the QBASIC epic; lean text topics can grow with each stage. |
| `HIMEM.SYS` | XMS 2.00, the DOS 5 option set, DOS 6 `/EISA` memory discovery, `/V` and `/VERBOSE` diagnostics, and `/TESTMEM:ON|OFF` parsing/default state are covered. The destructive reliability pass behind `/TESTMEM:ON`, exact 6.22 version/API identity, defaults, and remaining machine-option parity still require reference work. |
| `MEM` | Existing `/C`, `/D`, `/F`, `/M`, and `/PROGRAM` views need differential validation against DOS 6.22's enhanced reports and EMM386 integration. |
| `SETVER` | Retail 6.2/6.22 defaults, persistent editing, driver loading, and 6.22 identity behavior are covered. |
| `UNDELETE` | DOS protection modes exist, but the enhanced 6.22 UI/configuration and Windows companion are absent. The Windows companion is out of scope. |
| `XCOPY` | Present: `/Y`, `/-Y`, `COPYCMD`, overwrite prompts, and hidden/system exclusion are covered. |

## Startup, drivers, and APIs

### CONFIG.SYS and boot

CONFIG.SYS `SET`, `NUMLOCK=ON|OFF`, named blocks, `[menu]`, `[common]`,
`MENUITEM`, `MENUDEFAULT`, `MENUCOLOR`, `SUBMENU`, and recursive `INCLUDE` are
present. Selection, invalid-key recovery, zero and finite timeouts, nesting,
source-order flattening, missing-submenu filtering, and the `CONFIG` variable
passed to AUTOEXEC.BAT have QEMU coverage.

Remaining work is a reference differential of exact diagnostics and parsing
boundaries. F5/Shift bypass menus completely; F8 selects a block before
stepping its flattened lines and AUTOEXEC.BAT. Selected `DEVICEHIGH`,
`INSTALL`, `SHELL`, and AUTOEXEC.BAT behavior is covered across fresh
multipass working images.

`DEVICEHIGH /L:region[,minsize][;...] /S` and the corresponding `LOADHIGH`
region grammar are already implemented and covered. `INSTALLHIGH` is a useful
repository extension, not a retail 6.22 directive.

### New driver and multiplex surfaces

- `INTERLNK.EXE`: block/character device behavior, serial and parallel
  transports, `/DRIVES`, `/NOPRINTER`, port selection, redirector semantics,
  drive/printer mapping, and unload/reconnect behavior.
- `POWER.EXE`: installation, runtime policy, INT 28h idleness, CPU halt, and APM
  fallback are present. Keyboard-poll and disk/video/DOS busy tracking plus the
  exact reference API remain.
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
