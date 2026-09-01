# MS-DOS 6.22 parity

This is the canonical product-level comparison with the retail English
MS-DOS 6.22 base system. The live source, `distribution/files.json`, and the
strict manifests under `tests/` are authoritative for implementation and test
status. [DOS5_GAPS.md](DOS5_GAPS.md) records inherited DOS 5 compatibility.

The reference baseline is Microsoft's 1994
[MS-DOS 6.22 User's Guide](https://bitsavers.trailing-edge.com/pdf/microsoft/msdos_6.22/DOS_6.22_Users_Manual_1994.pdf)
and the archived
[MS-DOS 6.22 Help corpus](https://www.infania.net/misc/dos622help/).

## Current position

The command, driver, installation, Help, observable-API, memory, and tooling
contracts are substantially complete. The system is not a complete replacement
for every bundled retail product: DriveSpace,
QBASIC/EDIT, and the other explicitly classified additions are separate epics,
while the listed non-goals remain excluded.

| Area | Status | Current boundary |
| --- | --- | --- |
| Identity, kernel, and startup | Implemented | Reports 6.22; SETVER, configuration menus, startup bypass/stepping, and DOS 6 startup behavior are covered. The `MSDOS5.0` FAT OEM identifier is correct for 6.22. |
| Commands and maintenance | Implemented | CHOICE, DELTREE, LOADFIX, MOVE, COPY/XCOPY overwrite policy, ScanDisk, and Defrag ship with focused contracts. |
| Memory management | Implemented | HIMEM, EMM386, MEM, DEVICEHIGH/LOADHIGH, and MemMaker are functional. EMM386 uses 33,280 conventional bytes in the comparison configuration and is gated below 40 KiB; exact whole-system MCB layout is not a parity requirement. |
| Cache, diagnostics, and power | Implemented | SMARTDrive, MSD, and POWER ship. |
| Connectivity and CD-ROM | Implemented | INTERLNK, INTERSVR, and MSCDEX ship; a hardware-specific CD-ROM driver remains external. |
| Data protection | Implemented | UNDELETE implements all three DOS protection methods, the structured DOS recovery inventory, and retail Sentry storage. MSBACKUP, MSAV, and VSAFE are deliberate non-goals. |
| Installation | Implemented | SETUP installs or upgrades a bootable 6.22 system, selects core components, creates a minimal recovery floppy, and generates a tested one-shot rollback image. |
| Online Help | Implemented | HELP is an independent full-screen hypertext browser with keyboard/mouse navigation and full-corpus search; FASTHELP remains the compact redirectable interface. |
| EGA display-state driver | Implemented | EGA.SYS exposes the documented register-shadow, installation, version, custom-multiplex, and default-state contracts independently of Task Swapper. |
| Observable DOS internals | Implemented | Interrupt, error, device-request, internal-structure, redirector, and LIM EMS 4.0 contracts are covered. |
| National-language support | Implemented core | COUNTRY, KEYB, DISPLAY, PRINTER, EGA/LCD fonts, and supported code-page switching are covered. Additional DOS 6 locale packs remain a separate data-focused epic. |
| Drive compression | Separate epic | DriveSpace is not implemented. |
| BASIC and Editor | Separate epic | QBASIC and the QBASIC-backed EDIT are not implemented. |
| Bundled applications | Non-goal | MSBACKUP, MSAV, VSAFE, DOSSHELL, and Task Swapper will not be implemented. |

“Implemented” means the repository ships the feature and its declared
interfaces have contract evidence. It does not claim byte-identical binaries,
identical presentation or every physical machine. Observable documented and
undocumented interfaces are targets; unobservable implementation identity is
not.

## Completed core work and excluded product gaps

### Stage 4: completed product work

`UNDELETE` supports FAT12/FAT16 recovery, `/LIST`, `/ALL`, `/DOS`, and `/DT`,
including tracked chains and names. Retail `/Tdrive[-entries]`, `/STATUS`, and
`/UNLOAD` manage Delete Tracker, and `/LOAD` applies tracker-drive and default
settings from `UNDELETE.INI`. Delete Sentry `/S` intercepts handle and FCB
deletion, preserves exact file data in a hidden SENTRY area, takes priority for
automatic recovery, and supports `/DS`, `/LIST`, restoration, `/PURGE`, status,
and unload. Sentry-mode `/LOAD` creates or reads the five-section
`UNDELETE.INI`, including drive selection, file filters, archive policy, expiry,
and disk-percentage limits with oldest-first purging. Its `CONTROL.FIL`, fixed
records, linked active/free lists, stored names, and padded paths interoperate in
both directions with genuine DOS 6.22 UNDELETE. `UNDELETE.INI` is resolved beside
the executable, as in the retail tool. Recovery uses the retail-style structured
textual directory, filespec, method, metadata, protection, and result report—not
a full-screen interface. The Windows companion is outside this project's scope.

The following retail programs remain absent by decision, not as open work:

| Program | Excluded surface |
| --- | --- |
| `MSBACKUP` | Microsoft Backup UI, set/catalog formats, scheduling, compression, verification, spanning, and device support. DOS 5 BACKUP/RESTORE continues to support its historical format. |
| `MSAV` | Interactive scanning; `drive:`, `/S`, `/C`, `/R`, `/A`, `/L`, `/N`, `/P`, `/F`, `/VIDEO` and display forms; removal, reports, checksums, exit code 86, configuration, and signatures. |
| `VSAFE` | Resident modes `1` through `8`; `/NE`, `/NX`, `/Ax`, `/Cx`, `/N`, `/D`, `/U`; hotkeys, checksums, network monitoring, and shared MSAV signatures. |
| `DOSSHELL` and Task Swapper | Shell UI and suspended-application switching. |

### Installation and Help

Standalone `HELP` now provides the full-screen browser independently of
QBASIC: an alphabetized topic index, full-corpus search, keyboard paging,
bracketed topic links, mouse selection, and clean return to DOS. Its 137-topic
clean-room corpus covers every shipped loadable driver and CONFIG.SYS directive
plus core conceptual topics. `FASTHELP` remains the separate compact text entry
point, and redirected `HELP` output remains script-friendly.

The current installer identifies itself as 6.22 and its fresh-install defaults
load HIMEM, upper-memory DOS, and SMARTDrive; on a 386 or newer it also selects
EMM386 with `NOEMS`, while 286 startup files omit the incompatible driver. It
accepts the retail `/B` display form, and `/F` creates a self-contained bootable
recovery floppy without references to omitted Disk 2 components. Retail `/E`
configures excluded Windows companions and therefore reports that boundary
explicitly. Upgrade mode deliberately preserves user startup files
byte-for-byte. Interactive fresh installation selects memory management,
SMARTDrive startup, and Delete Sentry independently; `/Y` applies the safe
memory/cache defaults without enabling Sentry.

Before an upgrade, SETUP renames the complete prior DOS directory intact and
copies the previous root system sources into it with their attributes and
timestamps. It installs root-level `UNINSTAL.EXE` plus its destination record.
UNINSTAL swaps the preserved tree back, uses the restored `SYS.COM` and exact
system-file sources to rebuild the boot layout, preserves startup files, and
keeps the replaced installation as `NEW_DOS.1` for recovery. Byte-exact root
and command restoration, metadata, repeat-run refusal, and fixed-disk boot are
covered in QEMU.

### EGA.SYS

`EGA.SYS` is implemented as the isolated driver/API compatibility feature from
the 6.22 Supplemental Disk. It supports `FUNC=80..FF`, INT 2Fh installation and
version queries, and the INT 10h EGA Register Interface for single, range, and
record-set access plus caller-defined default-state restoration. Its register
shadow is resynchronized after BIOS mode, palette, font, and alternate-function
calls. DOSSHELL and Task Swapper remain excluded.

### Observable APIs and internals

Compatibility includes documented and undocumented behavior visible to DOS
applications. Use published technical references and clean-room behavioral
contracts for interrupts, multiplex APIs, IOCTLs, device requests, error and
register behavior, and structures such as the list of lists, PSP, MCB, SFT,
CDS, DPB, SDA, and device chain. Version and SETVER-dependent behavior is also
in scope. Internal layouts or algorithms that no program can observe are not.

The PSP, owning MCB, List of Lists, DPB and CDS links, live JFT-to-SFT mapping,
SDA, and device chain now have one executable layout contract. The clean-room
probe passes both this system and genuine DOS 6.22; its source-derived inventory
is enforced by `tests/internal_structure_coverage.json`.

The installed MSCDEX redirector drives ordinary DOS path dispatch, remote SFT
and CDS state, IOCTL classification, sharing, open/read/seek/close, and failure
paths. EMM386's source-derived inventory covers every LIM EMS 4.0 function from
`40h` through `5Dh`, including map-and-jump/call, memory transfer, raw pages,
alternate register sets, warm boot, and OS/E access control. Shipping the
Microsoft Network Client remains a separate application-suite epic, not a
kernel API gap.

### Known boundaries in shipped components

- `DIR` lacks compressed-volume ratios (`/C[H]`, `O:C`, and `O:-C`).
- FORMAT, ScanDisk, Defrag, SYS, and SETUP do not understand compressed or host
  volumes. These are DriveSpace dependencies, not independent gaps.
- HIMEM and EMM386 have real-BIOS 286 and emulated 386+ coverage, but unusual
  chipsets, real Weitek behavior, and broad physical-hardware timing remain
  validation limits.
- The supported national-language records and code pages are covered, but the
  additional `KEYBRD2.SYS`, `EGA2.CPI`, `EGA3.CPI`, and `ISO.CPI` locale packs
  are a separate data-focused epic. Localized message catalogs are not part of
  the retail English baseline.

## Separate epics

### DriveSpace

No DriveSpace implementation ships. The epic includes:

- exact read/write compatibility with CVFs produced by genuine DOS 6.22;
- `DRVSPACE.EXE` interactive operation and `/AUTOMOUNT`, `/CHKDSK`,
  `/COMPRESS`, `/CREATE`, `/DELETE`, `/FORMAT`, `/INFO`, `/MOUNT`, `/RATIO`,
  `/SIZE`, `/UNCOMPRESS`, and `/UNMOUNT`;
- boot-time `DRVSPACE.BIN`, `DRVSPACE.SYS`, CVF mounting, drive-letter and host
  swapping, and `DRVSPACE.INI`;
- compression, resizing, repair, conversion, DoubleSpace coexistence, IOCTL,
  multiplex, and ratio-query contracts; and
- integration with DIR, FORMAT, SYS, SETUP, ScanDisk, Defrag, and recovery
  media, including torn-write and low-space behavior.

An optional extended mode may add faster or denser compression and stronger
integrity. It must use an explicit versioned format, never silently convert a
retail-compatible CVF, and remain clearly distinguishable from media that
genuine DOS 6.22 can mount.

### QBASIC and EDIT

This epic includes the BASIC interpreter and runtime, IDE/editor, QBASIC-backed
`EDIT`, bundled examples, and their own online Help. It is intentionally
independent of the operating-system stages.

### Supplemental Disk audit

The archived [Microsoft KB Q117600 inventory](https://ftp.zx.net.nz/pub/archive/ftp.microsoft.com/MISC/KB/en-us/117/600.HTM)
is fully classified below.
Compressed copies, setup batches, readme files, and disk-identification helpers
are packaging rather than independent product features.

| Contents | Decision |
| --- | --- |
| ASSIGN, BACKUP/RESTORE, COMP, EDLIN, EXE2BIN, GRAFTABL, JOIN, MIRROR, CHOICE, and EXPAND | Implemented and shipped. |
| EGA.SYS | Implemented and shipped independently of DOSSHELL. |
| PRINTER.SYS, 4201.CPI, 4208.CPI, 5202.CPI, and LCD.CPI | Implemented and shipped; every added printer/display data path has a live prepare/select contract. |
| AccessDOS (`ADOS`, `AM`, and FAKEMOUS), Dvorak layouts, and their documentation | Separate accessibility epic; not core DOS parity. |
| KBDBUF.SYS | Non-goal legacy BIOS keyboard-buffer workaround; supported emulators do not lose keystrokes through the ROM buffer. |
| DRVBOOT.BAT | Part of the DriveSpace epic because its purpose is creating compressed boot media. |
| CV.COM | Non-goal compatibility launcher for obsolete CodeView 3.00-3.13. |
| PRINTFIX.COM | Non-goal workaround for parallel-port hardware that rejects DOS extended status checks. |
| MSHERC.COM and the BASIC samples | Part of the QBASIC/EDIT epic and its Hercules-display support. |
| Microsoft Network Client files (`NET`, NETBEUI, NETWKSTA, REDIR, and SETNAME) | Separate networking-product epic; kernel redirector compatibility remains a core API target. |
| DOSSHELL, DOSSWAP, and `.GRB`/`.INI`/`.VID` display resources | Permanent DOSSHELL/Task Swapper non-goal. |

`ISO.CPI` belongs with the additional DOS 6 locale packs rather than the core
English system. Installer-only `SETUP.BAT`, `SD6COPY.BAT`, `GET_FUNC.COM`, and
disk ID files are superseded by this repository's reproducible distribution.

## Delivery roadmap

| Stage | Scope | Status |
| --- | --- | --- |
| 1 | 6.22 identity, startup/configuration, command additions, and overwrite policy | Complete |
| 2 | ScanDisk, Defrag, memory-manager differences, and MemMaker | Complete |
| 3 | SMARTDrive, MSD, POWER, INTERLNK/INTERSVR, and MSCDEX | Complete |
| 4 | Close observable API, internal-structure, locale, and Supplemental gaps | Complete |
| 5 | Retail-compatible DriveSpace and all compressed-volume integration | Separate epic |
| 6 | Optional versioned extended DriveSpace format | Follows Stage 5 |

QBASIC/EDIT remains an independent epic. MSBACKUP, MSAV, VSAFE, DOSSHELL, Task
Swapper, Windows-only companions, FAT32, VFAT long filenames, and Windows 9x
protected-mode extensions are out of scope. AccessDOS, the Microsoft Network
Client, and the additional DOS 6 locale packs are separate epics.

Hosted CI is intentionally manual-only during active development. Local tests
are authoritative until the maintainer re-enables automatic CI. Every new
component still requires source-derived manifest coverage, focused success and
failure contracts, reproducible artifacts, and clean-room comparison with
user-supplied genuine media where exact behavior is uncertain.
