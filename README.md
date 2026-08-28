# MS-DOS 4.0 build and test environment

Builds the maintained `ddanila/MS-DOS` 4.0 source fork on Linux and macOS with
custom JWasm and Open Watcom. The build is fully native and open source: it does
not execute Microsoft build tools or DOS emulators.

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
git submodule update --init --recursive
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
- [KEYNOTES.md](KEYNOTES.md) - maintainer constraints and diagnostics.
- [tests/COVERAGE.md](tests/COVERAGE.md) - behavioral coverage and traceability.
- [jwasm/README.md](jwasm/README.md) and [watcom/README.md](watcom/README.md) -
  exact tool provenance.
