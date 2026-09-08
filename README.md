# MS-DOS 6.22-compatible system

This repository builds a DOS 6.22-compatible system from maintained sources in
`src/`. It uses custom JWasm and Open Watcom on Linux and macOS. The production
build is native and open source; runtime tests use emulators.

The default build selects the composed memory profile. Its qualification and
ownership constraints are recorded in [MEMORY.md](MEMORY.md).
See [TODO.md](TODO.md) for priorities and
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
export PATH="$(brew --prefix coreutils)/libexec/gnubin:$PATH"
```

The optional real-BIOS 286 acceptance suite also needs the 86Box cask and its
separately installed ROM set; see [EMULATION.md](EMULATION.md).

The tests require GNU utilities such as `timeout` and `dd`; keep the coreutils
path above in your test shell. Use `gmake` instead of `make` on macOS.

## Build and test

```sh
git clone --recurse-submodules https://github.com/ddanila/msdos.git
cd msdos
./jwasm/build.sh
make
make test
make deploy
```

See [tests/COVERAGE.md](tests/COVERAGE.md) for test scope and
[EMULATION.md](EMULATION.md) for additional emulator gates. Known blockers are
listed in [TODO.md](TODO.md). `make distribution` builds the installation disk
set under `out/distribution/`.

The selected memory core is built under `out/memory-production/files/` and used
consistently by deployment and installation media. Use
`make MEMORY_PROFILE=baseline all deploy distribution` for the baseline layout.

The deployed floppy is written to `out/floppy.img`. Boot it interactively with:

```sh
./run-qemu.sh
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
