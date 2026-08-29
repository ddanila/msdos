# MS-DOS 5.0-compatible system

This is the canonical source, build, test, and release repository for the
maintained DOS system. It builds on Linux and macOS with custom JWasm and Open
Watcom. The maintained source lives directly under `src`; the system reports
DOS 5.00 and implements its UMB/HMA memory surface. The build is fully native
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

- [PLAN.md](PLAN.md) - toolchain architecture and design rationale.
- [TODO.md](TODO.md) - open work.
- [REPOSITORY_CONSOLIDATION_PLAN.md](REPOSITORY_CONSOLIDATION_PLAN.md) -
  consolidation history and acceptance contract.
- [KEYNOTES.md](KEYNOTES.md) - maintainer constraints and diagnostics.
- [UMB_PLAN.md](UMB_PLAN.md) - UMB/HMA compatibility contract and delivery plan.
- [DOS5_PARITY_MATRIX.md](DOS5_PARITY_MATRIX.md) - version gate and known gaps.
- [tests/COVERAGE.md](tests/COVERAGE.md) - behavioral coverage and traceability.
- [jwasm/README.md](jwasm/README.md) and [watcom/README.md](watcom/README.md) -
  exact tool provenance.
