# MS-DOS 4.0 Build — TODO

## CMD Utilities (not yet built from source)

Building each follows the standard pattern: BUILDMSG (if `.SKL` present) → MASM/CL → LINK → EXE2BIN/CONVERT.
Add rules to `mk/cmd.mk`, add the output to the floppy image in `Makefile`.

| Directory | Output        | Notes |
|-----------|---------------|-------|
| BACKUP    | backup.com    | depends on RESTORE message set |
| EXE2BIN   | exe2bin.exe   | we use the pre-built one in TOOLS/ — skip |
| GRAFTABL  | graftabl.com  | needs CPI/font data |
| GRAPHICS  | graphics.com  | needs graphics profile data files |
| IFSFUNC   | ifsfunc.exe   | IFS (Installable File System) support |
| KEYB      | keyb.com      | needs keyboard layout data (KEYBOARD.SYS already built) |
| MODE      | mode.com      | large — handles serial/parallel/display/codepage |
| RESTORE   | restore.com   | counterpart to BACKUP |
| SHARE     | share.exe     | file sharing / locking |

## DEV Extras

| Item                      | Notes |
|---------------------------|-------|
| DEV/SMARTDRV/FLUSH13.EXE | Auxiliary utility for SMARTDRV; not currently built |

## Floppy Image

- Currently boots with: IO.SYS, MSDOS.SYS, COMMAND.COM, SYS.COM, FORMAT.COM, CHKDSK.COM, DEBUG.COM, MEM.EXE, FDISK.EXE, MORE.COM, SORT.EXE, LABEL.COM, FIND.EXE, TREE.COM, COMP.COM, ATTRIB.EXE, EDLIN.COM, FC.EXE, NLSFUNC.EXE, ASSIGN.COM, XCOPY.EXE, DISKCOMP.COM, DISKCOPY.COM, APPEND.EXE, RECOVER.COM, FASTOPEN.EXE, PRINT.COM, FILESYS.EXE, REPLACE.EXE, JOIN.EXE, SUBST.EXE.
- As more utilities are built, decide which ones to include on the boot floppy.

## Testing

- Extend `make test-sys` / add more e2e tests as more utilities are built.
- Add CI step for `make test-sys`.
