# MS-DOS 4.0 Reproducible Build

Build MS-DOS 4.0 from source on Linux and macOS using original DOS compilers running under [kvikdos](https://github.com/pts/kvikdos) (a headless DOS emulator — KVM on Linux, software 8086 CPU on macOS).

## What this does

1. **Build**: Run the original MS-DOS 4.0 compilers (MASM, CL, LINK, LIB, etc.) under kvikdos to compile and link the OS from source — producing `IO.SYS`, `MSDOS.SYS`, `COMMAND.COM` (with `/?' help for all built-in commands), `SYS.COM`, `FORMAT.COM`, all 11 device drivers, and more.
2. **Test**: Validate build outputs with integration tests — file existence checks, SHA256 golden checksums, COMMAND.COM smoke tests, /? help smoke tests for all 38 CMD tools under kvikdos, and E2E functional tests (MEM, FIND, FC, TREE) under kvikdos.
3. **Deploy**: Assemble a bootable 1.44MB floppy image (`out/floppy.img`) from the build outputs.
4. **Verify**: Boot the floppy headlessly in QEMU and confirm MS-DOS reports its version via COM1.
5. **E2E test**: Boot the floppy in QEMU and test built-in commands (VER, ECHO, SET, PATH, DIR, VOL via `make test-builtins`), /? help for 27 external tools on real DOS (`make test-help-qemu`), EXEPACK binary integrity (`make test-exepack`), and `FORMAT B:` → `SYS B:` on a blank image to verify it boots independently (`make test-sys`).
6. **CI**: Automated `make test` + `make deploy` + `make verify` + `make test-sys` + `make test-builtins` + `make test-exepack` + `make test-help-qemu` in GitHub Actions on every push.

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
make verify        # headless QEMU boot — checks COM1 output for "MS-DOS"
make test-sys      # e2e: FORMAT + SYS a blank floppy, verify it boots
make test-builtins  # e2e: QEMU boot, test built-in commands via COM1
make test-help-qemu # e2e: QEMU boot, /? help for 27 external CMD tools
make test-exepack   # e2e: QEMU boot, verify EXEPACK-patched binaries load
make gen-checksums  # regenerate tests/golden.sha256 (always run make clean first!)
make clean         # remove all generated files and floppy images
./run-qemu.sh      # boot floppy interactively in QEMU (graphical window)
```

Individual module targets: `messages`, `mapper`, `boot`, `inc`, `bios`, `dos`, `cmd`, `dev`, `select`, `memm`.
