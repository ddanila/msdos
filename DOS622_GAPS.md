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
| Disk health and performance | Partial | ScanDisk has a shipped FAT12/FAT16 logical-repair core, repair log, stale-safe undo flow, and surface recovery. Defrag has byte-preserving FAT12/FAT16 `/U` relocation, `/F` compaction, physical directory sorting, hidden/nested coverage, reboot behavior, and recoverable transaction boundaries. Remaining reference UI and compatibility details are listed below. |
| Memory optimization | Partial | Strong HMA/UMB base plus a reversible MemMaker startup-file/reboot workflow with measured baseline, post-CONFIG, and post-AUTOEXEC memory states and per-candidate Custom driver/TSR placement; size ordering and remaining DOS 6 EMM386/MEM/HIMEM differentials remain. |
| SMARTDrive | Partial | `SMARTDRV.EXE` controls live per-drive policy, delayed writes, flushing, and status over the compatibility driver. Runtime self-installation, effective sizing/read-ahead controls, CD-ROM caching, and a single dual-purpose binary remain. |
| Diagnostics and power | Partial | `MSD` ships with interactive and report modes. POWER has an installable driver, all controller modes, application-idle and keyboard-poll detection, disk/video/DOS activity resets, CPU-idle action, APM discovery, and a status API; exact reference behavior remains. |
| Machine-to-machine and CD-ROM access | Partial | `INTERLNK.EXE` and `INTERSVR.EXE` discover and redirect multiple remote FAT volumes with byte-exact access over selectable COM1-COM4, while `MSCDEX.EXE` installs over an external device driver and exposes its ISO and driver APIs. Parallel transport, printer mapping, DOS-visible CD-ROM filesystem access, and media control remain. |
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
| `DEFRAG` | Partial | `/U` relocates fragmented FAT12/FAT16 file chains into contiguous free runs; `/F` compacts movable clusters and `/S[:]order` physically sorts directory entries while preserving byte-exact files. Nested and hidden-file policy and `/B` reboot are covered. Divergent FAT copies, lost allocations, and invalid chains are refused. Every `/U` and `/F` relocation write boundary is fault-injected and proven byte-preserving and ScanDisk-recoverable. Remaining: meaningful display modes, exhaustive errorlevels, broader corruption corpora, and the reference full-screen interface. |
| `DELTREE` | Present | Recursive and wildcard deletion, multiple targets, protected attributes, prompting, and `/Y` are covered. |
| `DRVSPACE` | Separate epic | Interactive and command-line DriveSpace manager; `/AUTOMOUNT`, `/CHKDSK`, `/COMPRESS`, `/CREATE`, `/DELETE`, `/FORMAT`, `/INFO`, `/MOUNT`, `/RATIO`, `/SIZE`, `/UNCOMPRESS`, `/UNMOUNT`, host-drive swapping, and the driver/format/API integration listed below. |
| `FASTHELP` | Present | Compact command list/topic interface backed by the lean text Help database. |
| `INTERLNK` | Partial | The dual-purpose EXE installs as a multi-unit block-device client, discovers up to five server volumes, negotiates an independent BPB for each, forwards sector reads/writes, and reports the live drive count and port. CONFIG.SYS accepts an effective `/DRIVES:1..5` cap, drive-only `/NOPRINTER`, `/COM:1..4`, the five retail `/BAUD` rates, polling-only `/V`, `/AUTO`, and `/NOSCAN`; without `/COM`, it probes COM1 through COM4 with bounded waits. Default and `/NOSCAN` installations remain resident offline with placeholder BPBs, while `/AUTO` declines installation without a server. Request headers and sector payloads are checksummed; corrupt reads are rejected and force a reconnect, while corrupt writes are rejected before server disk I/O and retried once without advancing the caller's buffer. Remaining: `/LOW`, `/LPT`, printer redirection, unload, and broader line-fault recovery. |
| `INTERSVR` | Partial | Up to five selected DOS volumes are exported over `/COM:1..4` at the five retail `/BAUD` rates. With no explicit list, available drives are enumerated and `/X=` exclusions are applied. `/B` selects the text-only monochrome-compatible display and `/V` selects the already polling-only timer-safe transport. Discovery, per-volume geometry, and checksummed byte-exact sector I/O work between independent machines; Alt+F4 exits cleanly to DOS. Floppy exports use physical BIOS I/O so A: and B: remain distinct even under single-drive DOS aliasing. UART waits are bounded, overlapping sync prefixes are retained, and truncated or corrupt request headers are discarded before dispatch; corrupt write payloads are rejected before disk I/O and the client resynchronizes and retries them. Remaining: printers, `/LPT`, full connection UI/status, parallel transport, broader line-fault recovery, and `/RCOPY` bootstrap transfer. |
| `LOADFIX` | Present | Placement above the first 64 KiB, argument forwarding, and child exit propagation are covered. |
| `MEMMAKER` | Partial | Express and interactive Custom rewriting, byte-exact backups and `/UNDO`, scheduled CONFIG `/SESSION` and AUTOEXEC `/FINAL` passes, `/SWAP`, memory-manager insertion, retail leading-entry ordering, DEVICEHIGH/INSTALLHIGH, and eligible TSR `LH` conversion are live. `SIZER.EXE` measures TSR resident deltas; the final pass uses an exact subset-sum optimizer to maximize measured TSR paragraphs placed within available UMB capacity. The CONFIG pass matches selected drivers to the loader's live `DEVMARK` records and records their exact resident paragraphs. Custom independently includes or excludes every eligible driver and TSR and selects EMS and monochrome-region use. `WINDIR` discovery identifies Windows 3.0 from `WIN.COM`, preserves `SYSTEM.INI` as `SYSTEM.UMB`, and transactionally applies `SYSTEMROMBREAKPOINT`, `EMMEXCLUDE`, and option-derived `EMMINCLUDE`, `DUALDISPLAY`, and `NOEMMDRIVER` settings while preserving unrelated include ranges; Windows 3.1 and unknown installations remain unchanged. DOS allocation probes record baseline, post-CONFIG, and final post-TSR UMB/conventional blocks plus actual gain and `/W` reserve accounting while restoring allocation state; fault injection covers every commit boundary. Remaining: optimal address-region placement across fragmented UMB regions and exact retail UI behavior. |
| `MOVE` | Present | Files, directory rename, multiple sources, prompts, `/Y`, `/-Y`, `COPYCMD`, cross-drive recursion, and errorlevels are covered. |
| `MSAV` | Missing | Interactive scanning and `drive:`, `/S`, `/C`, `/R`, `/A`, `/L`, `/N`, `/P`, `/F`, `/VIDEO` and its display switches; removal, reports, checksums, exit code 86, configuration, and signature database. |
| `MSBACKUP` | Missing | Interactive backup/restore/compare, `.SET` setup and catalog files, full/incremental/differential sets, compression, verification, scheduling, spanning, destination devices, and `setup_file`, `/BW`, `/LCD`, `/MDA`. DOS 5 `RESTORE` remains responsible for old `BACKUP` sets. |
| `MSCDEX` | Partial | `/D`, `/L`, `/M`, `/E`, `/S`, `/V`, and `/K` parsing; multi-subunit DOS device-header discovery; residency; drive assignment; and `INT 2Fh` functions 1500h through 1508h and 150Bh through 1510h are live. This includes per-subunit routing, ISO metadata, indexed VTOC reads, READ LONG conversion, an effective bounded `/M` sector cache retained conventionally or in allocated EMS with `/E`, per-drive PVD/SVD selection with PVD fallback, nested/version-aware ISO path traversal, and transparent direct-driver requests. Media coverage includes play/stop/resume, eject/close, lock/unlock, reset, channel control, head position, volume size, media change, disc/track/Q-channel, audio status, and invalid-subunit errors. Remaining: DOS-visible redirector file access, preserving a pre-existing third-party EMS physical-page mapping, and network sharing. A hardware-specific CD-ROM device driver remains external. |
| `MSD` | Partial | A lean interactive/report implementation covers the reference-derived `/B`, `/I`, prompted `/F`, direct `/P`, and summary `/S` grammar plus processor generation, BIOS identity/date/equipment/base memory/display/game-adapter state, active and alternate video adapters, text geometry, COM/LPT bases and BIOS status, keyboard and mouse presence, DOS identity/OEM, allocation/UMB/VERIFY/BREAK/code-page/country/date-format/environment state, XMS/EMS versions, A20 state, and available memory, IRQ, driver, FAT-drive geometry, SUBST/JOIN/network mappings, video, and network reporting. Retail screen layout, exhaustive device detail, and field-by-field report parity remain. |
| `POWER` | Partial | One dual-purpose `POWER.EXE` installs through CONFIG.SYS and controls status, `OFF`, `STD`, `ADV`, and `ADV:MIN|REG|MAX`. The resident service recognizes DOS and keyboard idleness, resets on activity, and performs level-dependent CPU halts. Its APM path verifies installation and connection before advertising availability, enables or disables management with the selected mode, and issues CPU-idle notifications. INT 2Fh 5400h/5401h/5403h/5481h identity and core results match a genuine 6.22 capture. Remaining: physical-hardware threshold calibration and retail diagnostics. |
| `SCANDISK` | Partial | FAT12/FAT16 traversal, allocation and directory repair, wildcard `/FRAGMENT`, free and occupied-cluster `/SURFACE` verification with live-file relocation, bounded BIOS reset/retry for transient physical floppy failures, repair logging, stale-safe `/UNDO`, and uncompressed-volume `SCANDISK.INI` policies are live. Remaining: physical timeout calibration, graphical mouse/display behavior, exact multi-drive/parser/UI behavior, broader hardware-fault corpora, and `CheckHost`/compressed policies in the DriveSpace epic. |
| `SMARTDRV` | Partial | `SMARTDRV.EXE` supplies status, fixed-drive read/read-write/off selection, `/C`, `/F`, `/L`, `/N`, `/Q`, `/R`, `/S`, `/U`, `/V`, `/X`, live cache resizing within its resident allocation, cache locking, real dirty-track write-behind, and explicit/timer/INT 19h reboot flushing over `SMARTDRV.SYS`. `/B` and `/E` are parsed but do not yet change cache behavior. Remaining: runtime self-installation, effective read-ahead/element controls, CD-ROM caching, non-reboot shutdown paths, and one dual-purpose EXE. |
| `VSAFE` | Missing | Resident monitoring options `1` through `8`, `/NE`, `/NX`, `/Ax`, `/Cx`, `/N`, `/D`, `/U`, hotkeys, checksums, network monitoring, and MSAV signature sharing. |

Known gaps in commands already shipped:

| Existing command | Missing 6.22 behavior |
| --- | --- |
| `COMMAND` | `/K`, `/Y` batch single-stepping, F5/Shift startup bypass, F8 CONFIG/AUTOEXEC confirmation, and selected-configuration propagation are present. |
| `COPY` | Present: `/Y`, `/-Y`, overwrite prompting, `COPYCMD`, and command-line precedence are covered. |
| `DIR` | `/C[H]` compression ratios and `O:C`/`O:-C`; these depend on DriveSpace. |
| `EMM386` | DOS 6 command-mode statistics and diagnostics, ON/OFF/AUTO state transitions, application-handle-driven AUTO activation/release, W= handling, EMS/UMB modes, memory regions, M1-M14 frame selection, and LIM 4.0 APIs are covered, including safe rejection of corrupt external page maps. Remaining compatibility limits are real Weitek behavior and physical-hardware timing validation. |
| `FORMAT` | `/C` retests previously marked bad clusters, while normal formatting preserves their marks. Compressed/host-drive interaction depends on the DriveSpace epic. |
| `HELP` | The current searchable text database lacks the retail full-screen hypertext UI, complete 6.22 topic corpus, mouse navigation, syntax/notes/examples links, and full-text search. The UI belongs to the QBASIC epic; lean text topics can grow with each stage. |
| `HIMEM.SYS` | XMS 3.00 identity and 32-bit functions 88h, 89h, 8Eh, and 8Fh match DOS 6.22 reference behavior within the manager's 64 MiB pool. The DOS 5 options, `/EISA`, diagnostics, and destructive `/TESTMEM:ON|OFF` paths are covered. Remaining gaps are machine-specific option behavior and physical-hardware validation. |
| `MEM` | Summary, `/C`, `/D`, `/F`, `/M`, and `/PROGRAM` use the DOS 6.22 report structure and include XMS 3 identity/free space, device detail, HMA state, and split EMM386 UMB accounting. Locale-dependent spacing and physical-machine totals are not compatibility claims. |
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
- `POWER.EXE`: installation, runtime policy, application-idle and keyboard-poll
  detection, disk/video/DOS activity resets, CPU halt, and APM fallback are
  present. Exact reference thresholds, diagnostics, APM lifecycle, and API
  behavior remain.
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
