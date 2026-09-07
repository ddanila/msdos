# Custom JWasm assembler

The production assembler is the project JWasm fork, invoked through
`bin/jwasm-masm` in MASM 5.1 mode. C compilation, linking, and library creation
use the separate Open Watcom toolchain.

## Pin and provenance

| Item | Value |
| --- | --- |
| Branch | `ddanila/JWasm:custom` |
| Pin | `REVISION` in [build.sh](build.sh) |
| Supported hosts | Linux x86-64 and macOS arm64 |

Use the pinned custom assembler: upstream releases are not an equivalent
fallback for this tree's MASM compatibility and linked-layout requirements.

## Build

Host binaries are built locally and ignored by Git. The build script checks out
the exact pin and installs the binary for the current platform. From the repository
root:

```sh
./jwasm/build.sh
```

## Validation

`tests/test_toolchain_transforms.py` covers parsing and include lookup. The
release gate additionally requires reproducible `-j1`, `-j4`, and `-j8` builds
and the applicable emulator gates; see [ARCHITECTURE.md](../ARCHITECTURE.md).
