# MS-DOS 4.0 Build — TODO

## CMD Utilities

All 38 CMD utilities have been built from source. ✅

## DEV Device Drivers

All 11 device drivers built from source. ✅
DEV/SMARTDRV/FLUSH13.EXE (auxiliary cache control utility) also built. ✅

## Core Modules

All core modules built from source: BIOS/IO.SYS, DOS/MSDOS.SYS, BOOT, INC, MAPPER, MESSAGES, SELECT, MEMM/EMM386.SYS. ✅

## Source Audit Notes

- `INC/STRING.C` — not a build target; referenced only as a comment in KSTRING.C; superseded code.
- `INC/KSTRING.C` — built on-demand for FC.EXE (not a standalone `inc` target); covered.
- `TOOLS/` — pre-built compiler toolchain (MASM, CL, LINK, etc.), not MS-DOS OS source.
- `DEV/SMARTDRV/SMARTDRV.SYS` — already built by `dev` target. ✅

## Floppy Image

- Currently boots with all built utilities: IO.SYS, MSDOS.SYS, COMMAND.COM, SYS.COM, FORMAT.COM, CHKDSK.COM, DEBUG.COM, MEM.EXE, FDISK.EXE, MORE.COM, SORT.EXE, LABEL.COM, FIND.EXE, TREE.COM, COMP.COM, ATTRIB.EXE, EDLIN.COM, FC.EXE, NLSFUNC.EXE, ASSIGN.COM, XCOPY.EXE, DISKCOMP.COM, DISKCOPY.COM, APPEND.EXE, RECOVER.COM, FASTOPEN.EXE, PRINT.COM, FILESYS.EXE, REPLACE.EXE, JOIN.EXE, SUBST.EXE, BACKUP.COM, RESTORE.COM, GRAFTABL.COM, KEYB.COM, SHARE.EXE, EXE2BIN.EXE, GRAPHICS.COM + GRAPHICS.PRO, IFSFUNC.EXE, MODE.COM.

## Testing

- Extend `make test-sys` / add more e2e tests.
- Add CI step for `make test-sys`.
