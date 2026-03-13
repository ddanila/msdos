# MS-DOS 4.0 Build — TODO

## CMD Utilities (not yet built from source)

All 35 missing utilities live under `MS-DOS/v4.0/src/CMD/`. Building each follows the
standard pattern: BUILDMSG (if `.SKL` present) → MASM → LINK → EXE2BIN/CONVERT.
Add rules to `mk/cmd.mk`, add the output to the floppy image in `Makefile`.

| Directory  | Output          | Notes |
|------------|-----------------|-------|
| APPEND     | append.exe      | |
| ASSIGN     | assign.com      | |
| ATTRIB     | attrib.exe      | |
| BACKUP     | backup.com      | depends on RESTORE message set |
| ~~CHKDSK~~ | ~~chkdsk.com~~  | ✅ done |
| COMP       | comp.com        | |
| ~~DEBUG~~  | ~~debug.com~~   | ✅ done — 11 ASM files, BUILDMSG generates all CL files including CL1/CL2 |
| DISKCOMP   | diskcomp.com    | |
| DISKCOPY   | diskcopy.com    | |
| EDLIN      | edlin.com       | |
| EXE2BIN    | exe2bin.exe     | we use the pre-built one in TOOLS/ |
| FASTOPEN   | fastopen.exe    | |
| FC         | fc.exe          | |
| ~~FDISK~~  | ~~fdisk.exe~~   | ✅ done — NOSRVBLD+BUILDMSG+MENUBLD, 20 C files + 4 ASM, links MAPPER.LIB+COMSUBS.LIB; FDBOOT.OBJ/INC reused from SELECT |
| FILESYS    | filesys.exe     | |
| FIND       | find.exe        | |
| GRAFTABL   | graftabl.com    | needs CPI/font data |
| GRAPHICS   | graphics.com    | needs graphics profile data files |
| IFSFUNC    | ifsfunc.exe     | IFS (Installable File System) support |
| JOIN       | join.exe        | shared code with SUBST |
| KEYB       | keyb.com        | needs keyboard layout data (KEYBOARD.SYS already built) |
| LABEL      | label.com       | |
| ~~MEM~~    | ~~mem.exe~~     | ✅ done — C + 2 ASM, links against LIB/MEM.LIB; output is EXE (no CONVERT) |
| MODE       | mode.com        | large, handles serial/parallel/display/codepage |
| MORE       | more.com        | |
| NLSFUNC    | nlsfunc.exe     | NLS (National Language Support) |
| PRINT      | print.com       | |
| RECOVER    | recover.com     | |
| REPLACE    | replace.exe     | |
| RESTORE    | restore.com     | counterpart to BACKUP |
| SHARE      | share.exe       | file sharing / locking |
| SORT       | sort.exe        | |
| SUBST      | subst.exe       | shared code with JOIN |
| TREE       | tree.com        | |
| XCOPY      | xcopy.exe       | |

## DEV Extras

| Item                        | Notes |
|-----------------------------|-------|
| DEV/SMARTDRV/FLUSH13.EXE   | Auxiliary utility for SMARTDRV; not currently built |

## Floppy Image

- Currently boots with: IO.SYS, MSDOS.SYS, COMMAND.COM, SYS.COM, FORMAT.COM, CHKDSK.COM, DEBUG.COM, MEM.EXE, FDISK.EXE.
- As more utilities are built, decide which ones to include on the boot floppy.

## Testing

- Extend `make test-sys` / add more e2e tests as more utilities are built.
- Add CI step for `make test-sys`.
