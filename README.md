# MS-DOS 4.0 Reproducible Build

Build MS-DOS 4.0 from source on Linux using original DOS compilers running under [kvikdos](https://github.com/pts/kvikdos) (a headless KVM-based DOS emulator).

## What this does

1. **Build**: Run the original MS-DOS 4.0 compilers (MASM, CL, LINK, LIB, etc.) under kvikdos to compile and link the OS from source — producing `io.sys`, `msdos.sys`, and `command.com`.
2. **Deploy**: Boot the result in headless QEMU.
3. **Verify**: Check that MS-DOS boots successfully via COM1 output.

## Status

All 10 modules build successfully:

| Module   | Output                        |
|----------|-------------------------------|
| MESSAGES | `MESSAGES/USA-MS.IDX`         |
| MAPPER   | `MAPPER/MAPPER.LIB`           |
| BOOT     | `INC/boot.inc`                |
| INC      | shared kernel objects         |
| BIOS     | `BIOS/IO.SYS`                 |
| DOS      | `DOS/MSDOS.SYS`               |
| CMD      | `CMD/COMMAND/COMMAND.COM`     |
| DEV      | `DEV/*/\*.SYS` (10 drivers)   |
| SELECT   | `SELECT/SELECT.{EXE,COM,HLP,DAT}` |
| MEMM     | `MEMM/MEMM/EMM386.SYS`        |

## Repository layout

- `MS-DOS/` — fork of [microsoft/MS-DOS](https://github.com/microsoft/MS-DOS) (v4.0 source)
- `kvikdos/` — fork of [pts/kvikdos](https://github.com/pts/kvikdos) with modifications for this build
- `bin/` — wrapper scripts that invoke kvikdos for each DOS tool (masm, cl, link, lib, …)
- `mk/` — per-module Makefile fragments
- `Makefile` — Linux GNU Makefile orchestrating the full build
- `tests/` — integration tests (file existence, SHA256 golden checksums, kvikdos smoke tests)

## Building

```sh
make           # build all modules
make test      # build + run integration tests
make clean     # remove all generated files
```

Individual module targets: `messages`, `mapper`, `boot`, `inc`, `bios`, `dos`, `cmd`, `dev`, `select`, `memm`.

## Future plans

- Boot in headless QEMU and verify via COM1
- CI integration for `make test`
