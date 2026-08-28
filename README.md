# MS-DOS 4.0 build and test environment

This repository builds the `ddanila/MS-DOS` 4.0 source fork on current Linux
and macOS hosts. The production path is fully native and open source: custom
JWasm assembles the historical MASM sources, and custom Open Watcom provides
the 16-bit C compiler, linker, library manager, and runtime libraries. No
Microsoft build binary or DOS emulator is executed while building.

The repository also contains two runtime test layers:

- kvikdos provides fast command-level tests;
- QEMU boots the deployed floppy and exercises the kernel, utilities, drivers,
  filesystem behavior, disk operations, and EMM386.

The exact tool revisions and the compatibility operations that remain are
documented in [PLAN.md](PLAN.md). Detailed test traceability is in
[tests/COVERAGE.md](tests/COVERAGE.md).

## Quick start

Initialize submodules before the first build, then provision the pinned JWasm
host binary:

```sh
git submodule update --init --recursive
./jwasm/build.sh
make
make test
make deploy
```

`make` builds the complete tree. `make test` runs the fast host-side behavioral
suite and all strict coverage-manifest checks. `make deploy` creates
`out/floppy.img`. To boot that image interactively:

```sh
./run-qemu.sh
```

The CI workflow runs the production build, `make test`, deployment, and the
complete QEMU matrix. Individual QEMU targets are listed by:

```sh
make -qp | sed -n 's/^\(test-[[:alnum:]_-]*\):.*/\1/p' | sort -u
```

## Dependencies

Linux (Debian/Ubuntu):

```sh
sudo apt install build-essential git nasm python3 qemu-system-x86 mtools
```

macOS with Homebrew:

```sh
brew install coreutils git make mtools nasm python qemu
```

The Makefile expects GNU Make. On macOS, invoke `gmake` if Homebrew installs it
under that name. The repository does not use Homebrew-specific preprocessors or
source-rewriting utilities.

## What is built

The build produces the DOS boot sector, `IO.SYS`, `MSDOS.SYS`, `EMM386.SYS`,
the shared libraries and data files, SELECT, all command utilities, and all
shipped device drivers from the checked-in source tree. The authoritative
artifact inventory is `ARTIFACTS` in [Makefile](Makefile); the checksum oracle
is [tests/golden.sha256](tests/golden.sha256), with a narrow macOS override for
host-tool output differences.

## Repository layout

- `MS-DOS/` - pinned `ddanila/MS-DOS` source fork; development branch `main`.
- `kvikdos/` - pinned `ddanila/kvikdos` fork; development branch `custom`.
- `bin/` - strict tool adapters and native replacements for historical build
  utilities.
- `jwasm/` - exact custom-JWasm source pin and host build script.
- `watcom/` - vendored Open Watcom host tools, libraries, headers, and source
  revision documentation.
- `mk/` - module-specific build rules.
- `tests/` - fast behavioral tests, QEMU tests, coverage manifests, and golden
  artifacts.
- [PLAN.md](PLAN.md) - current architecture, compatibility rationale, and
  maintenance direction.
- [TODO.md](TODO.md) - concise open work only.
- [KEYNOTES.md](KEYNOTES.md) - durable maintainer constraints and diagnostics.

## Branch and contribution policy

Work in this repository lands on `ddanila/msdos` `master`. Changes to the
source or tool forks land only in the corresponding repositories and branches
under `github.com/ddanila`. Do not open issues, push branches, or submit changes
to an upstream project without explicit permission from the repository owner.
