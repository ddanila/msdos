# Custom JWasm assembler

The production assembler is the project JWasm fork, invoked through
`bin/jwasm-masm` in MASM 5.1 mode. C compilation, linking, and library creation
use the separate Open Watcom toolchain.

## Pin and provenance

| Item | Value |
| --- | --- |
| Branch | `ddanila/JWasm:custom` |
| Required commit | `4c2f0a2f7440ca40a8cfa6718ac3ffd74ca1f9d9` |
| Upstream base | 2026-07-01 snapshot, `7f6f32e` |
| Supported hosts | Linux x86-64 and macOS arm64 |

Upstream v2.20 is not an equivalent fallback. The custom revision supplies the
MASM compatibility required by this source tree:

- case-insensitive include lookup and structured-macro whitespace arguments;
- PUBLIC-name casing and MASM-compatible explicit external OMF frames;
- forward jump and conditional-branch sizing;
- indexed structure-member sizing and scalar types through `EQU` aliases;
- synchronized `.ALPHA` segment indices and saved fixup frames;
- native macOS `alloca` support.

These behaviors preserve the required layouts in KEYB, MODE, DISKCOMP, and
SELECT without a generated source tree.

## Build

Host binaries are built locally and ignored by Git. The build script checks out
the exact pin and installs the binary for the current platform:

```sh
./jwasm/build.sh
```

## Validation

`tests/test_toolchain_transforms.py` covers parsing and include lookup. The
release gate additionally requires reproducible `-j1`, `-j4`, and `-j8` builds
and a booting QEMU image; see [ARCHITECTURE.md](../ARCHITECTURE.md).
