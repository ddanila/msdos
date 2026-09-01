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

The system is substantially DOS 6.22-compatible, but it is not yet a complete
replacement for the retail product. The platform, maintenance, memory,
caching, diagnostics, connectivity, and CD-ROM stages are implemented. The
next stage is product completion: improve SETUP and recovery media and close
observable API gaps.
DriveSpace and QBASIC/EDIT are separate large epics.

| Area | Status | Current boundary |
| --- | --- | --- |
| Identity, kernel, and startup | Implemented | Reports 6.22; SETVER, configuration menus, startup bypass/stepping, and DOS 6 startup behavior are covered. The `MSDOS5.0` FAT OEM identifier is correct for 6.22. |
| Commands and maintenance | Implemented | CHOICE, DELTREE, LOADFIX, MOVE, COPY/XCOPY overwrite policy, ScanDisk, and Defrag ship with focused contracts. |
| Memory management | Implemented | HIMEM, EMM386, MEM, DEVICEHIGH/LOADHIGH, and MemMaker cover the intended 6.22 surface on the supported machine models. |
| Cache, diagnostics, and power | Implemented | SMARTDrive, MSD, and POWER ship. |
| Connectivity and CD-ROM | Implemented | INTERLNK, INTERSVR, and MSCDEX ship; a hardware-specific CD-ROM driver remains external. |
| Data protection | Implemented | UNDELETE implements all three DOS protection methods, the structured DOS recovery inventory, and retail Sentry storage. MSBACKUP, MSAV, and VSAFE are deliberate non-goals. |
| Installation | Partial | SETUP installs or upgrades a bootable 6.22 system with hardware-aware defaults and can create a minimal bootable recovery floppy; component selection and rollback remain. |
| Online Help | Implemented | HELP is an independent full-screen hypertext browser with keyboard/mouse navigation and full-corpus search; FASTHELP remains the compact redirectable interface. |
| EGA display-state driver | Implemented | EGA.SYS exposes the documented register-shadow, installation, version, custom-multiplex, and default-state contracts independently of Task Swapper. |
| Observable DOS internals | Partial | Documented and undocumented APIs and data structures are compatibility targets wherever applications can observe or depend on them. |
| Drive compression | Separate epic | DriveSpace is not implemented. |
| BASIC and Editor | Separate epic | QBASIC and the QBASIC-backed EDIT are not implemented. |
| Bundled applications | Non-goal | MSBACKUP, MSAV, VSAFE, DOSSHELL, and Task Swapper will not be implemented. |

“Implemented” means the repository ships the feature and its declared
interfaces have contract evidence. It does not claim byte-identical binaries,
identical presentation or every physical machine. Observable documented and
undocumented interfaces are targets; unobservable implementation identity is
not.

## Remaining product gaps

### Stage 4: product completion

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

The remaining durable gaps are:

- rollback/uninstall with recoverable startup-file and system backups.

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
memory/cache defaults without enabling Sentry. Rollback/uninstall remains.

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

### Known boundaries in shipped components

- `DIR` lacks compressed-volume ratios (`/C[H]`, `O:C`, and `O:-C`).
- FORMAT, ScanDisk, Defrag, SYS, and SETUP do not understand compressed or host
  volumes. These are DriveSpace dependencies, not independent gaps.
- HIMEM and EMM386 have real-BIOS 286 and emulated 386+ coverage, but unusual
  chipsets, real Weitek behavior, and broad physical-hardware timing remain
  validation limits.
- Locale-dependent presentation is not yet an exhaustive compatibility claim.

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

Supplemental Disk contents are not automatically parity requirements. Audit
them item by item and classify each as already covered, worth implementing,
superseded, a separate epic, or a non-goal.

## Delivery roadmap

| Stage | Scope | Status |
| --- | --- | --- |
| 1 | 6.22 identity, startup/configuration, command additions, and overwrite policy | Complete |
| 2 | ScanDisk, Defrag, memory-manager differences, and MemMaker | Complete |
| 3 | SMARTDrive, MSD, POWER, INTERLNK/INTERSVR, and MSCDEX | Complete |
| 4 | Improve SETUP/recovery media and close observable API gaps | Next |
| 5 | Retail-compatible DriveSpace and all compressed-volume integration | Separate epic |
| 6 | Optional versioned extended DriveSpace format | Follows Stage 5 |

QBASIC/EDIT remains an independent epic. MSBACKUP, MSAV, VSAFE, DOSSHELL, Task
Swapper, Windows-only companions, FAT32, VFAT long filenames, and Windows 9x
protected-mode extensions are out of scope. Supplemental Disk contents remain
undecided until their itemized audit.

Hosted CI is intentionally manual-only during active development. Local tests
are authoritative until the maintainer re-enables automatic CI. Every new
component still requires source-derived manifest coverage, focused success and
failure contracts, reproducible artifacts, and clean-room comparison with
user-supplied genuine media where exact behavior is uncertain.
