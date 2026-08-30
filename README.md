# MS-DOS 6.22-compatible system

This is the canonical source, build, test, and release repository for the
maintained DOS system. It builds on Linux and macOS with custom JWasm and Open
Watcom. The maintained source lives directly under `src`; the system reports
DOS 6.22 and implements its UMB/HMA memory surface. The build is fully native
and open source; it does not execute Microsoft build tools or DOS emulators.

## Requirements

Debian/Ubuntu:

```sh
sudo apt install build-essential git nasm python3 qemu-system-x86 mtools
```

macOS with Homebrew:

```sh
brew install coreutils git make mtools nasm python qemu
```

Use `gmake` instead of `make` on macOS when Homebrew installs GNU Make under
that name.

## Build and test

```sh
git clone --recurse-submodules https://github.com/ddanila/msdos.git
cd msdos
./jwasm/build.sh
make
make test
make deploy
```

The deployed floppy is written to `out/floppy.img`. Boot it interactively with:

```sh
./run-qemu.sh
```

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - system and toolchain design.
- [TODO.md](TODO.md) - open work.
- [MAINTAINING.md](MAINTAINING.md) - maintainer constraints and diagnostics.
- [MEMORY.md](MEMORY.md) - DOS 5 HMA/UMB/XMS/EMS invariants.
- [DOS5_GAPS.md](DOS5_GAPS.md) - complete known DOS 5 feature and tooling gaps.
- [DOS622_GAPS.md](DOS622_GAPS.md) - staged delta from the current system to
  MS-DOS 6.22 compatibility.
- [tests/COVERAGE.md](tests/COVERAGE.md) - behavioral coverage and traceability.
- [jwasm/README.md](jwasm/README.md) and [watcom/README.md](watcom/README.md) -
  exact tool provenance.
