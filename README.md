# MS-DOS 4.0 Reproducible Build

Build MS-DOS 4.0 from source on Linux using original DOS compilers running under [kvikdos](https://github.com/pts/kvikdos) (a headless KVM-based DOS emulator).

## What this does

1. **Build**: Run the original MS-DOS 4.0 compilers (MASM, CL, LINK, LIB, etc.) under kvikdos to compile and link the OS from source — producing `IO.SYS`, `MSDOS.SYS`, `COMMAND.COM`, `SYS.COM`, `FORMAT.COM`, all 11 device drivers, and more.
2. **Test**: Validate build outputs with integration tests — file existence checks, SHA256 golden checksums, and COMMAND.COM smoke tests.
3. **Deploy**: Assemble a bootable 1.44MB floppy image (`out/floppy.img`) from the build outputs.
4. **Verify**: Boot the floppy headlessly in QEMU and confirm MS-DOS reports its version via COM1.
5. **E2E test**: Boot the floppy in QEMU, run `FORMAT B:` on a blank image then `SYS B:`, and verify the result boots MS-DOS independently (`make test-sys`).
6. **CI**: Automated `make test` + `make verify` in GitHub Actions on every push.

## Status

All modules built from source. Full source audit complete.

### Core (kernel, boot)

`IO.SYS`, `MSDOS.SYS`, `EMM386.SYS`, `MAPPER.LIB`, `boot.inc`, shared kernel objects, `SELECT.{EXE,COM,HLP,DAT}`, `USA-MS.IDX`

### CMD utilities (all 36 built)

`COMMAND.COM`, `FORMAT.COM`, `SYS.COM`, `CHKDSK.COM`, `DEBUG.COM`, `MEM.EXE`, `FDISK.EXE`, `MORE.COM`, `SORT.EXE`, `LABEL.COM`, `FIND.EXE`, `TREE.COM`, `COMP.COM`, `ATTRIB.EXE`, `EDLIN.COM`, `FC.EXE`, `NLSFUNC.EXE`, `ASSIGN.COM`, `XCOPY.EXE`, `DISKCOMP.COM`, `DISKCOPY.COM`, `APPEND.EXE`, `RECOVER.COM`, `FASTOPEN.EXE`, `PRINT.COM`, `FILESYS.EXE`, `REPLACE.EXE`, `JOIN.EXE`, `SUBST.EXE`, `BACKUP.COM`, `RESTORE.COM`, `GRAFTABL.COM`, `KEYB.COM`, `SHARE.EXE`, `EXE2BIN.EXE`, `GRAPHICS.COM`, `IFSFUNC.EXE`, `MODE.COM`

### DEV (device drivers — all 11 built)

`ANSI.SYS`, `COUNTRY.SYS`, `DISPLAY.SYS`, `DRIVER.SYS`, `KEYBOARD.SYS`, `PRINTER.SYS`, `RAMDRIVE.SYS`, `SMARTDRV.SYS`, `VDISK.SYS`, `XMA2EMS.SYS`, `XMAEM.SYS`, `FLUSH13.EXE`

## Repository layout

- `MS-DOS/` — fork of [microsoft/MS-DOS](https://github.com/microsoft/MS-DOS) (v4.0 source)
- `kvikdos/` — fork of [pts/kvikdos](https://github.com/pts/kvikdos) with modifications for this build
- `bin/` — wrapper scripts that invoke kvikdos for each DOS tool (masm, cl, link, lib, …)
- `mk/` — per-module Makefile fragments
- `Makefile` — Linux GNU Makefile orchestrating the full build
- `tests/` — integration tests (file existence, SHA256 golden checksums, kvikdos smoke tests, SYS e2e)
- `run-qemu.sh` — launch the floppy image in a graphical QEMU window for manual testing
- `KEYNOTES.md` — build notes, tips, and architecture decisions
- `TODO.md` — build notes and completed tasks log

## Dependencies

```sh
# Build tools
sudo apt install nasm gcc make python3

# DOS emulator (kvikdos uses KVM — requires /dev/kvm access)
# kvikdos is built from the kvikdos/ submodule (see kvikdos/Makefile)

# Deploy and verify
sudo apt install qemu-system-x86 mtools
```

## Building

```sh
make               # build all modules
make test          # build + run integration tests
make deploy        # create bootable floppy image at out/floppy.img
make verify        # headless QEMU boot — checks COM1 output for "MS-DOS"
make test-sys      # e2e: FORMAT + SYS a blank floppy, verify it boots
make gen-checksums # regenerate tests/golden.sha256 (always run make clean first!)
make clean         # remove all generated files and floppy images
./run-qemu.sh      # boot floppy interactively in QEMU (graphical window)
```

Individual module targets: `messages`, `mapper`, `boot`, `inc`, `bios`, `dos`, `cmd`, `dev`, `select`, `memm`.
