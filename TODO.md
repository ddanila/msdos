# MS-DOS 4.0 Build — TODO

## CMD Utilities (not yet built from source)

Building each follows the standard pattern: BUILDMSG (if `.SKL` present) → MASM/CL → LINK → EXE2BIN/CONVERT.
Add rules to `mk/cmd.mk`, add the output to the floppy image in `Makefile`.

| Directory | Output        | Notes |
|-----------|---------------|-------|
| GRAPHICS  | graphics.com  | 14 ASM, complex — .EXT/.STR aux files, 3 SKL classes |
| IFSFUNC   | ifsfunc.exe   | 10 ASM, links 7 INC/DOS kernel objects |
| MODE      | mode.com      | 16 ASM, 4 SKL classes — large, handles serial/parallel/display/codepage |

## DEV Extras

| Item                      | Notes |
|---------------------------|-------|
| DEV/SMARTDRV/FLUSH13.EXE | Auxiliary utility for SMARTDRV; not currently built |

## Floppy Image

- Currently boots with: IO.SYS, MSDOS.SYS, COMMAND.COM, SYS.COM, FORMAT.COM, CHKDSK.COM, DEBUG.COM, MEM.EXE, FDISK.EXE, MORE.COM, SORT.EXE, LABEL.COM, FIND.EXE, TREE.COM, COMP.COM, ATTRIB.EXE, EDLIN.COM, FC.EXE, NLSFUNC.EXE, ASSIGN.COM, XCOPY.EXE, DISKCOMP.COM, DISKCOPY.COM, APPEND.EXE, RECOVER.COM, FASTOPEN.EXE, PRINT.COM, FILESYS.EXE, REPLACE.EXE, JOIN.EXE, SUBST.EXE, BACKUP.COM, RESTORE.COM, GRAFTABL.COM, KEYB.COM, SHARE.EXE, EXE2BIN.EXE.
- As more utilities are built, decide which ones to include on the boot floppy.

## Testing

- Extend `make test-sys` / add more e2e tests as more utilities are built.
- Add CI step for `make test-sys`.
