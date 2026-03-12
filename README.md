# MS-DOS 4.0 Reproducible Build

Build MS-DOS 4.0 from source on Linux using original DOS compilers running under [kvikdos](https://github.com/pts/kvikdos) (a headless KVM-based DOS emulator).

## What this does

1. **Build**: Run the original MS-DOS 4.0 compilers (MASM, CL, LINK, LIB, etc.) under kvikdos to compile and link the OS from source — producing `io.sys`, `msdos.sys`, and `command.com`.
2. **Deploy**: Boot the result in headless QEMU.
3. **Verify**: Check that MS-DOS boots successfully via COM1 output.

## Status

Currently building the kernel modules using a Linux GNU Makefile that invokes kvikdos for each individual compilation step. BIOS (io.sys) and DOS (msdos.sys) modules are next.

## Repository layout

- `MS-DOS/` — fork of [microsoft/MS-DOS](https://github.com/microsoft/MS-DOS) (v4.0 source)
- `kvikdos/` — fork of [pts/kvikdos](https://github.com/pts/kvikdos) with modifications for this build
- `bin/` — wrapper scripts that invoke kvikdos for each DOS tool (masm, cl, link, lib, …)
- `mk/` — per-module Makefile fragments
- `Makefile` — Linux GNU Makefile orchestrating the full build

## Building

```sh
make          # build all modules
make messages # MESSAGES module (USA-MS.IDX)
make mapper   # MAPPER module (MAPPER.LIB)
make boot     # BOOT module (INC/boot.inc)
make inc      # INC module (shared kernel objects)
```

## Future plans

- BIOS (io.sys), DOS (msdos.sys), CMD (command.com) modules
- Boot in headless QEMU and verify via COM1
- More tests after boot
