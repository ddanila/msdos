# MS-DOS 4.0 Build — TODO

## CMD Utilities

All CMD utilities have been built from source. ✅

## DEV Extras

| Item                      | Notes |
|---------------------------|-------|
| DEV/SMARTDRV/FLUSH13.EXE | Auxiliary utility for SMARTDRV; not currently built |

## Floppy Image

- Currently boots with all built utilities: IO.SYS, MSDOS.SYS, COMMAND.COM, SYS.COM, FORMAT.COM, CHKDSK.COM, DEBUG.COM, MEM.EXE, FDISK.EXE, MORE.COM, SORT.EXE, LABEL.COM, FIND.EXE, TREE.COM, COMP.COM, ATTRIB.EXE, EDLIN.COM, FC.EXE, NLSFUNC.EXE, ASSIGN.COM, XCOPY.EXE, DISKCOMP.COM, DISKCOPY.COM, APPEND.EXE, RECOVER.COM, FASTOPEN.EXE, PRINT.COM, FILESYS.EXE, REPLACE.EXE, JOIN.EXE, SUBST.EXE, BACKUP.COM, RESTORE.COM, GRAFTABL.COM, KEYB.COM, SHARE.EXE, EXE2BIN.EXE, GRAPHICS.COM + GRAPHICS.PRO, IFSFUNC.EXE, MODE.COM.

## Testing

- Extend `make test-sys` / add more e2e tests as more utilities are built.
- Add CI step for `make test-sys`.
