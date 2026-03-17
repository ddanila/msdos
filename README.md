# MS-DOS 4.0 Reproducible Build

Build MS-DOS 4.0 from source on Linux and macOS using original DOS compilers running under [kvikdos](https://github.com/pts/kvikdos) (a headless DOS emulator — KVM on Linux, software 8086 CPU on macOS).

## What this does

1. **Build**: Run the original MS-DOS 4.0 compilers (MASM, CL, LINK, LIB, etc.) under kvikdos to compile and link the OS from source — producing `IO.SYS`, `MSDOS.SYS`, `COMMAND.COM` (with `/?' help for all built-in commands), `SYS.COM`, `FORMAT.COM`, all 11 device drivers, and more.
2. **Test**: Validate build outputs with integration tests — file existence checks, SHA256 golden checksums, COMMAND.COM smoke tests, /? help smoke tests for all 38 CMD tools under kvikdos, and E2E functional tests (MEM, FIND, FC, TREE, SORT, COMP, ATTRIB, MORE, DEBUG, LABEL, EDLIN, GRAFTABL, etc.) under kvikdos.
3. **Deploy**: Assemble a bootable 1.44MB floppy image (`out/floppy.img`) from the build outputs.
4. **E2E test**: Boot the floppy in QEMU and run a suite of functional tests — built-in commands (VER, ECHO, SET, PATH, DIR, VOL, IF, FOR, COPY, REN, DEL, MD/CD/RD, TYPE, CLS, ERASE, ATTRIB, FIND, CHKDSK, etc.) via `make test-builtins`; /? help + EXEPACK integrity for 27 external tools via `make test-help-qemu`; FORMAT variants (8 tests, parallelized) via `make test-format`; BACKUP/RESTORE, DISKCOMP/DISKCOPY, SHARE/NLSFUNC/EXE2BIN, APPEND, and LABEL interactive via dedicated test targets; and `FORMAT B:` → `SYS B:` boot verification via `make test-sys`.
5. **CI**: GitHub Actions on every push — build + `make test` (kvikdos integration tests), then 11 parallel E2E jobs: `test-sys`, `test-builtins`, `test-help-qemu`, `test-format` (4-way parallel matrix), `test-backup-restore`, `test-diskcomp-diskcopy`, `test-share-nlsfunc-exe2bin`, `test-append`, `test-label`.

## Status

All modules built from source. Full source audit complete. Builds and tests pass on both Linux (KVM) and macOS (software CPU backend).

### Core (kernel, boot)

`IO.SYS`, `MSDOS.SYS`, `EMM386.SYS`, `MAPPER.LIB`, `boot.inc`, shared kernel objects, `SELECT.{EXE,COM,HLP,DAT}`, `USA-MS.IDX`

### CMD utilities (all 38 built)

`COMMAND.COM`, `FORMAT.COM`, `SYS.COM`, `CHKDSK.COM`, `DEBUG.COM`, `MEM.EXE`, `FDISK.EXE`, `MORE.COM`, `SORT.EXE`, `LABEL.COM`, `FIND.EXE`, `TREE.COM`, `COMP.COM`, `ATTRIB.EXE`, `EDLIN.COM`, `FC.EXE`, `NLSFUNC.EXE`, `ASSIGN.COM`, `XCOPY.EXE`, `DISKCOMP.COM`, `DISKCOPY.COM`, `APPEND.EXE`, `RECOVER.COM`, `FASTOPEN.EXE`, `PRINT.COM`, `FILESYS.EXE`, `REPLACE.EXE`, `JOIN.EXE`, `SUBST.EXE`, `BACKUP.COM`, `RESTORE.COM`, `GRAFTABL.COM`, `KEYB.COM`, `SHARE.EXE`, `EXE2BIN.EXE`, `GRAPHICS.COM`, `IFSFUNC.EXE`, `MODE.COM`

### DEV (device drivers — all 11 built)

`ANSI.SYS`, `COUNTRY.SYS`, `DISPLAY.SYS`, `DRIVER.SYS`, `KEYBOARD.SYS`, `PRINTER.SYS`, `RAMDRIVE.SYS`, `SMARTDRV.SYS`, `VDISK.SYS`, `XMA2EMS.SYS`, `XMAEM.SYS`, `FLUSH13.EXE`

## Repository layout

- `MS-DOS/` — fork of [microsoft/MS-DOS](https://github.com/microsoft/MS-DOS) (v4.0 source)
- `kvikdos/` — fork of [pts/kvikdos](https://github.com/pts/kvikdos) with modifications for this build (`--dos-version`, GETPID/NLS/boot-drive/disk-serial stubs, macOS support)
- `bin/` — wrapper scripts that invoke kvikdos for each DOS tool (masm, cl, link, lib, …)
- `mk/` — per-module Makefile fragments
- `Makefile` — Linux GNU Makefile orchestrating the full build
- `tests/` — integration tests (file existence, SHA256 golden checksums, /? help under kvikdos and QEMU, kvikdos E2E, QEMU built-in E2E, EXEPACK verification, SYS e2e)
- `run-qemu.sh` — launch the floppy image in a graphical QEMU window for manual testing
- `KEYNOTES.md` — build notes, tips, and architecture decisions
- `TODO.md` — build notes and completed tasks log

## Dependencies

### Linux

```sh
# Build tools
sudo apt install nasm gcc make python3

# DOS emulator (kvikdos uses KVM — requires /dev/kvm access)
# kvikdos is built from the kvikdos/ submodule (see kvikdos/Makefile)

# Deploy and verify
sudo apt install qemu-system-x86 mtools
```

### macOS

```sh
brew install nasm gcc make python3 qemu mtools
# kvikdos uses the software 8086 CPU backend (XTulator) — no KVM required
```

## Building

```sh
make               # build all modules
make test          # build + run integration tests
make deploy        # create bootable floppy image at out/floppy.img
make test-sys      # e2e: FORMAT + SYS a blank floppy, verify it boots
make test-builtins  # e2e: QEMU boot, test built-in commands via COM1
make test-help-qemu # e2e: QEMU boot, /? help for 27 external CMD tools + EXEPACK check
make test-format    # e2e: FORMAT B: with all flag variants (8 tests, 4 parallel QEMU jobs)
make test-backup-restore       # e2e: BACKUP and RESTORE with all flag variants
make test-diskcomp-diskcopy    # e2e: DISKCOPY and DISKCOMP
make test-share-nlsfunc-exe2bin # e2e: SHARE, NLSFUNC, EXE2BIN
make test-append    # e2e: APPEND flag variants
make test-label     # e2e: LABEL interactive (serial_expect.py)
make gen-checksums  # regenerate tests/golden.sha256 (always run make clean first!)
make clean         # remove all generated files and floppy images
./run-qemu.sh      # boot floppy interactively in QEMU (graphical window)
```

Individual module targets: `messages`, `mapper`, `boot`, `inc`, `bios`, `dos`, `cmd`, `dev`, `select`, `memm`.
