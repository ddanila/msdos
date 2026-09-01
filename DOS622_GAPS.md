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
main product gap is Stage 4 data protection. Installation and Help are also
less complete than the retail experience. DriveSpace and QBASIC are separate
large epics.

| Area | Status | Current boundary |
| --- | --- | --- |
| Identity, kernel, and startup | Implemented | Reports 6.22; SETVER, configuration menus, startup bypass/stepping, and DOS 6 startup behavior are covered. The `MSDOS5.0` FAT OEM identifier is correct for 6.22. |
| Commands and maintenance | Implemented | CHOICE, DELTREE, LOADFIX, MOVE, COPY/XCOPY overwrite policy, ScanDisk, and Defrag ship with focused contracts. |
| Memory management | Implemented | HIMEM, EMM386, MEM, DEVICEHIGH/LOADHIGH, and MemMaker cover the intended 6.22 surface on the supported machine models. |
| Cache, diagnostics, and power | Implemented | SMARTDrive, MSD, and POWER ship. |
| Connectivity and CD-ROM | Implemented | INTERLNK, INTERSVR, and MSCDEX ship; a hardware-specific CD-ROM driver remains external. |
| Data protection | Missing/partial | MSBACKUP is absent. UNDELETE has DOS protection modes but lacks the enhanced 6.22 interface. MSAV and VSAFE are absent and optional to the roadmap. |
| Installation and Help | Partial | SETUP remains closer to the DOS 5 two-disk installer. HELP is a lean text implementation rather than the complete retail full-screen system. |
| Drive compression | Separate epic | DriveSpace is not implemented. |
| BASIC and Editor | Separate epic | QBASIC and the QBASIC-backed EDIT are not implemented. |
| DOSSHELL and Task Swapper | Non-goal | These will not be implemented. EGA.SYS and the Shell task-switching surface are excluded with them. |

“Implemented” means the repository ships the feature and its declared
interfaces have contract evidence. It does not claim byte-identical binaries,
identical presentation, every physical machine, or every undocumented internal
field.

## Remaining product gaps

### Stage 4: data protection

`MSBACKUP` is missing. A compatible implementation needs:

- interactive backup, restore, and compare workflows;
- `.SET` setup files and catalog files;
- full, incremental, and differential sets;
- compression, verification, scheduling, and media spanning;
- supported destination-device behavior; and
- `setup_file`, `/BW`, `/LCD`, and `/MDA` command-line forms.

The DOS 5 `BACKUP` and `RESTORE` pair remains available for its own historical
format; it is not a substitute for Microsoft Backup.

`UNDELETE` supports FAT12/FAT16 recovery, `/LIST`, `/ALL`, `/DOS`, and `/DT`,
including tracked chains and names. It still lacks the enhanced DOS 6.22
interface and configuration. The Windows companion is outside this project's
scope.

`MSAV` and `VSAFE` are not implemented. They should be accepted as Stage 4
work only if their historical compatibility value justifies maintaining an
obsolete signature database and resident scanner. Their missing surfaces are:

| Program | Unsupported surface |
| --- | --- |
| `MSAV` | Interactive scanning; `drive:`, `/S`, `/C`, `/R`, `/A`, `/L`, `/N`, `/P`, `/F`, `/VIDEO` and display forms; removal, reports, checksums, exit code 86, configuration, and signatures. |
| `VSAFE` | Resident modes `1` through `8`; `/NE`, `/NX`, `/Ax`, `/Cx`, `/N`, `/D`, `/U`; hotkeys, checksums, network monitoring, and shared MSAV signatures. |

### Installation and Help

The remaining durable gaps are:

- 6.22-style install and upgrade behavior rather than only the current DOS 5
  two-disk compressed installation;
- rollback/uninstall, emergency/startup-disk, and recovery workflows;
- SETUP integration for the implemented memory, cache, and protection tools;
- a complete 6.22 Help topic corpus; and
- the retail full-screen hypertext, mouse, link, and search experience, which
  belongs with the QBASIC/editor UI epic.

`FASTHELP` and the current searchable text `HELP` remain useful lightweight
interfaces and should grow as components are added.

### Known boundaries in shipped components

- `DIR` lacks compressed-volume ratios (`/C[H]`, `O:C`, and `O:-C`).
- FORMAT, ScanDisk, Defrag, SYS, and SETUP do not understand compressed or host
  volumes. These are DriveSpace dependencies, not independent gaps.
- HIMEM and EMM386 have real-BIOS 286 and emulated 386+ coverage, but unusual
  chipsets, real Weitek behavior, and broad physical-hardware timing remain
  validation limits.
- Locale-dependent presentation and exhaustive undocumented DOS internal
  layouts are not current compatibility claims.

## Separate epics

### DriveSpace

No DriveSpace implementation ships. The epic includes:

- `DRVSPACE.EXE` interactive operation and `/AUTOMOUNT`, `/CHKDSK`,
  `/COMPRESS`, `/CREATE`, `/DELETE`, `/FORMAT`, `/INFO`, `/MOUNT`, `/RATIO`,
  `/SIZE`, `/UNCOMPRESS`, and `/UNMOUNT`;
- boot-time `DRVSPACE.BIN`, `DRVSPACE.SYS`, CVF mounting, drive-letter and host
  swapping, and `DRVSPACE.INI`;
- compression, resizing, repair, conversion, DoubleSpace coexistence, IOCTL,
  multiplex, and ratio-query contracts; and
- integration with DIR, FORMAT, SYS, SETUP, ScanDisk, Defrag, and recovery
  media, including torn-write and low-space behavior.

### QBASIC, EDIT, and full-screen Help

This epic includes the BASIC interpreter and runtime, IDE/editor, QBASIC-backed
`EDIT`, and reusable full-screen Help UI. It is intentionally independent of
the operating-system stages.

## Delivery roadmap

| Stage | Scope | Status |
| --- | --- | --- |
| 1 | 6.22 identity, startup/configuration, command additions, and overwrite policy | Complete |
| 2 | ScanDisk, Defrag, memory-manager differences, and MemMaker | Complete |
| 3 | SMARTDrive, MSD, POWER, INTERLNK/INTERSVR, and MSCDEX | Complete |
| 4 | MSBACKUP and enhanced UNDELETE; decide whether MSAV/VSAFE are worthwhile | Next |
| 5 | DriveSpace and all compressed-volume integration | Separate epic |

QBASIC/EDIT/full-screen Help remains an independent epic. Installation and
reference-corpus improvements can proceed alongside Stage 4. DOSSHELL, Task
Swapper, EGA.SYS, Windows-only companions, Supplemental Disk utilities, FAT32,
VFAT long filenames, and Windows 9x protected-mode extensions are out of scope.

Hosted CI is intentionally manual-only during active development. Local tests
are authoritative until the maintainer re-enables automatic CI. Every new
component still requires source-derived manifest coverage, focused success and
failure contracts, reproducible artifacts, and clean-room comparison with
user-supplied genuine media where exact behavior is uncertain.
