# DOS 6.22 compatibility scope

The system targets the retail English DOS 6.22 operating system and observable
application interfaces, including undocumented interfaces used by DOS software.
Exact binaries, private algorithms, and retail screen presentation are not
compatibility requirements. Reference material is listed in
[REFERENCE.md](REFERENCE.md).

The build, [distribution inventory](distribution/files.json), and
[test manifests](tests/COVERAGE.md) describe shipped features and their coverage.
Commands, drivers, setup/recovery, Help, and memory services exist, but their
presence does not establish complete retail parity. Memory composition's
qualification scope is recorded in [MEMORY.md](MEMORY.md). Inherited validation limits
are in [DOS5_GAPS.md](DOS5_GAPS.md).

## Separate epics

| Epic | Boundary |
| --- | --- |
| DriveSpace | Retail-compatible compressed volumes, boot support, management tools, and system-wide integration. |
| QBASIC/EDIT | BASIC interpreter/runtime, IDE and editor, examples, Help, and Hercules display support. |
| AccessDOS | Accessibility tools, Dvorak layouts, and documentation. |
| Microsoft Network Client | Client applications, protocols, and configuration; kernel redirector compatibility stays in core scope. |
| Additional DOS 6 locales | KEYBRD2.SYS, EGA2.CPI, EGA3.CPI, ISO.CPI, and associated data. Localized messages are outside the retail English baseline. The optional [Russian / CP866 increment](RUSSIAN.md) is qualified; its RU-only KEYBRD2.SYS does not complete the retail supplemental packs. The [Baltic / CP775 plan](BALTIC.md) covers Estonian, Latvian and Lithuanian as the next scoped locale increment. |

DriveSpace must read and write genuine DOS 6.22 CVFs and provide mounting,
host-drive mapping, compression, recovery, and boot media. DIR compressed ratios
(`/C[H]`, `O:C`, `O:-C`) and compressed-volume support in FORMAT, SYS, SETUP,
ScanDisk, Defrag, and recovery tools depend on this epic and are currently absent.
Include torn writes and low-space behavior in its acceptance criteria.

An optional extended compression format may follow retail compatibility. It
must be explicitly versioned and must never silently convert a retail CVF.

## Non-goals

MSBACKUP, MSAV, VSAFE, DOSSHELL, Task Swapper, and Windows-only companion tools
are excluded. DOS BACKUP/RESTORE and the independent EGA.SYS driver remain in
scope. FAT32, VFAT long filenames, and Windows 9x protected-mode extensions are
also excluded. Windows installer acceptance does not expand that scope.

Supplemental Disk exceptions are KBDBUF.SYS, CV.COM, and PRINTFIX.COM: their
legacy hardware/debugger workarounds are non-goals. DRVBOOT.BAT belongs with
DriveSpace; MSHERC.COM and BASIC samples belong with QBASIC/EDIT. Retail setup
batches and disk-identification helpers are replaced by the native distribution
process.

## Remaining qualification

Unusual A20 controllers, real Weitek hardware, physical storage, printer/display
combinations, and hardware timing remain validation limits. HIMEM has 286 tests;
EMM386 is 386-only. Emulator roles are defined in [EMULATION.md](EMULATION.md).
The Windows 95 external-media acceptance scope is recorded in
[tests/WINDOWS95-SETUP.md](tests/WINDOWS95-SETUP.md).

Use the [local release gates](ARCHITECTURE.md) for changes. Source-derived
coverage tracks interfaces this tree declares; it cannot discover every
missing retail interface. Use clean-room comparisons with user-supplied media
where behavior is uncertain. Do not commit commercial binaries or derived
product content.
