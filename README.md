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

### Core (kernel, boot)

| Module   | Output                            |
|----------|-----------------------------------|
| MESSAGES | `MESSAGES/USA-MS.IDX`             |
| MAPPER   | `MAPPER/MAPPER.LIB`               |
| BOOT     | `INC/boot.inc`                    |
| INC      | shared kernel objects             |
| BIOS     | `BIOS/IO.SYS`                     |
| DOS      | `DOS/MSDOS.SYS`                   |
| MEMM     | `MEMM/MEMM/EMM386.SYS`            |
| SELECT   | `SELECT/SELECT.{EXE,COM,HLP,DAT}` |

### CMD utilities (built so far)

| Utility  | Output                         |
|----------|--------------------------------|
| COMMAND  | `CMD/COMMAND/COMMAND.COM`      |
| FORMAT   | `CMD/FORMAT/FORMAT.COM`        |
| SYS      | `CMD/SYS/SYS.COM`              |
| CHKDSK   | `CMD/CHKDSK/CHKDSK.COM`        |
| DEBUG    | `CMD/DEBUG/DEBUG.COM`          |
| MEM      | `CMD/MEM/MEM.EXE`              |
| FDISK    | `CMD/FDISK/FDISK.EXE`          |
| MORE     | `CMD/MORE/MORE.COM`            |
| SORT     | `CMD/SORT/SORT.EXE`            |
| LABEL    | `CMD/LABEL/LABEL.COM`          |
| FIND     | `CMD/FIND/FIND.EXE`            |
| TREE     | `CMD/TREE/TREE.COM`            |
| COMP     | `CMD/COMP/COMP.COM`            |

25 more CMD utilities are listed in [TODO.md](TODO.md).

### DEV (device drivers — all 11 built)

`ANSI.SYS`, `COUNTRY.SYS`, `DISPLAY.SYS`, `DRIVER.SYS`, `KEYBOARD.SYS`, `PRINTER.SYS`, `RAMDRIVE.SYS`, `SMARTDRV.SYS`, `VDISK.SYS`, `XMA2EMS.SYS`, `XMAEM.SYS`

## Repository layout

- `MS-DOS/` — fork of [microsoft/MS-DOS](https://github.com/microsoft/MS-DOS) (v4.0 source)
- `kvikdos/` — fork of [pts/kvikdos](https://github.com/pts/kvikdos) with modifications for this build
- `bin/` — wrapper scripts that invoke kvikdos for each DOS tool (masm, cl, link, lib, …)
- `mk/` — per-module Makefile fragments
- `Makefile` — Linux GNU Makefile orchestrating the full build
- `tests/` — integration tests (file existence, SHA256 golden checksums, kvikdos smoke tests, SYS e2e)
- `run-qemu.sh` — launch the floppy image in a graphical QEMU window for manual testing
- `KEYNOTES.md` — build notes, tips, and architecture decisions
- `TODO.md` — remaining utilities to build from source

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
