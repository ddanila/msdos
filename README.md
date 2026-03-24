# MS-DOS 4.0 — Buildable Fork with Full Test Coverage

A working fork of MS-DOS 4.0 that builds from source on Linux and macOS, boots in QEMU, and has full E2E test coverage — intended as a stable base for OS-level experiments.

The build currently uses the original DOS compilers (MASM, CL, LINK) running under [kvikdos](https://github.com/pts/kvikdos) (a headless DOS emulator — KVM on Linux, software 8086 CPU on macOS). A migration to [Open Watcom V2](https://github.com/open-watcom/open-watcom-v2) (native Linux toolchain, no emulation) is in progress on the `watcom-migration` branch — all 53 modules assemble cleanly (58 WASM compat issues fixed), COMMAND.COM/IO.SYS/MSDOS.SYS all boot from clean build (tests A–E pass). Full E2E test suite pending.

## What's here beyond the stock source

- **`/?` help for every tool** — all 38 CMD utilities and all COMMAND.COM built-in commands have `/? ` usage text (none existed in the original source)
- **Bug fixes** — FOR/SET/PROMPT hang (ES register corruption), COMMAND.COM parser crash (signed comparison overflow), FDISK R6001 and semicolon bugs, EDLIN binary mode fixes
- **Full E2E test suite** — kvikdos fast tests for all built-ins and most tools; QEMU+serial tests for disk ops, TSRs, interactive prompts, FORMAT geometry, FDISK partitioning, driver loading
- **CI** — GitHub Actions on every push; parallel QEMU jobs cover all test targets

## What's built

### Kernel and boot
`IO.SYS`, `MSDOS.SYS`, `EMM386.SYS`, `MAPPER.LIB`, `boot.inc`, shared kernel objects, `SELECT.{EXE,COM,HLP,DAT}`, `USA-MS.IDX`

### CMD utilities (all 38)
`COMMAND.COM`, `FORMAT.COM`, `SYS.COM`, `CHKDSK.COM`, `DEBUG.COM`, `MEM.EXE`, `FDISK.EXE`, `MORE.COM`, `SORT.EXE`, `LABEL.COM`, `FIND.EXE`, `TREE.COM`, `COMP.COM`, `ATTRIB.EXE`, `EDLIN.COM`, `FC.EXE`, `NLSFUNC.EXE`, `ASSIGN.COM`, `XCOPY.EXE`, `DISKCOMP.COM`, `DISKCOPY.COM`, `APPEND.EXE`, `RECOVER.COM`, `FASTOPEN.EXE`, `PRINT.COM`, `FILESYS.EXE`, `REPLACE.EXE`, `JOIN.EXE`, `SUBST.EXE`, `BACKUP.COM`, `RESTORE.COM`, `GRAFTABL.COM`, `KEYB.COM`, `SHARE.EXE`, `EXE2BIN.EXE`, `GRAPHICS.COM`, `IFSFUNC.EXE`, `MODE.COM`

### Device drivers (all 12)
`ANSI.SYS`, `COUNTRY.SYS`, `DISPLAY.SYS`, `DRIVER.SYS`, `KEYBOARD.SYS`, `PRINTER.SYS`, `RAMDRIVE.SYS`, `SMARTDRV.SYS`, `VDISK.SYS`, `XMA2EMS.SYS`, `XMAEM.SYS`, `FLUSH13.EXE`

## Quick start

```sh
make               # build everything
make test          # kvikdos integration tests (fast)
make deploy        # create out/floppy.img
./run-qemu.sh      # boot interactively in QEMU
```

Full E2E test targets:

```sh
make test-sys
make test-help-qemu
make test-format
make test-backup-restore
make test-diskcomp-diskcopy
make test-share-nlsfunc-exe2bin
make test-append
make test-label
make test-fdisk
make test-recover
make test-assign-subst-join
make test-debug-qemu
make test-drivers-qemu
make test-misc-qemu
```

## Dependencies

**Linux**
```sh
sudo apt install nasm gcc make python3 qemu-system-x86 mtools
```

**macOS**
```sh
brew install nasm gcc make python3 qemu mtools
```

## Repository layout

- `MS-DOS/` — fork of [microsoft/MS-DOS](https://github.com/microsoft/MS-DOS) (`dos4-enhancements` branch)
- `kvikdos/` — fork of [pts/kvikdos](https://github.com/pts/kvikdos) with DOS 4.0 compatibility stubs and macOS support
- `bin/` — wrapper scripts invoking kvikdos for each DOS tool (masm, cl, link, lib, …)
- `mk/` — per-module Makefile fragments
- `Makefile` — GNU Makefile orchestrating the full build
- `tests/` — all test scripts (kvikdos E2E, QEMU serial, /? smoke tests)
- `KEYNOTES.md` — build notes, architecture decisions, tips and tricks
- `TODO.md` — current work in progress
