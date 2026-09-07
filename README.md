# MS-DOS 6.22-compatible system

This is the canonical source, build, test, and release repository for the
maintained DOS system. It builds on Linux and macOS with custom JWasm and Open
Watcom. The maintained source lives directly under `src`; the system reports
DOS 6.22 and implements its UMB/HMA memory surface. The build is fully native
and open source; it does not execute Microsoft build tools or DOS emulators.

Core commands, drivers, installation, Help, and memory services are implemented.
The composed memory layout is under stabilization; it is not the default
deployment. See [TODO.md](TODO.md) for priorities and
[DOS622_GAPS.md](DOS622_GAPS.md) for compatibility scope and limitations.

## Requirements

Supported hosts are Linux x86-64 and macOS arm64.

Debian/Ubuntu:

```sh
sudo apt install build-essential git nasm python3 qemu-system-x86 mtools
```

macOS requires Xcode Command Line Tools and Homebrew:

```sh
brew install coreutils git make mtools nasm python qemu
```

The optional real-BIOS 286 acceptance suite also needs the 86Box cask and its
separately installed ROM set; see [EMULATION.md](EMULATION.md).

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

`make test` includes native checks, kvikdos, selected QEMU suites, and coverage
verifiers. Additional emulator gates are described in
[EMULATION.md](EMULATION.md). `make distribution` builds the installation disk
set under `out/distribution/`.

The deployed floppy is written to `out/floppy.img`. Boot it interactively with:

```sh
./run-qemu.sh
```

Run the local IBM AT acceptance suite with:

```sh
FAIL_ON_SKIP=1 make test-286-acceptance
```

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - system and toolchain design.
- [TODO.md](TODO.md) - open work.
- [MAINTAINING.md](MAINTAINING.md) - maintainer constraints and diagnostics.
- [MEMORY.md](MEMORY.md) - memory constraints and stabilization scope.
- [EMULATION.md](EMULATION.md) - emulator roles and 286 prerequisites.
- [DOS5_GAPS.md](DOS5_GAPS.md) - inherited DOS 5 compatibility limits.
- [DOS622_GAPS.md](DOS622_GAPS.md) - 6.22 scope and separate epics.
- [REFERENCE.md](REFERENCE.md) - external compatibility references.
- [tests/WINDOWS95-SETUP.md](tests/WINDOWS95-SETUP.md) - external-media acceptance.
- [tests/COVERAGE.md](tests/COVERAGE.md) - behavioral coverage and traceability.
- [jwasm/README.md](jwasm/README.md) and [watcom/README.md](watcom/README.md) -
  exact tool provenance.
