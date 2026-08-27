# Custom JWasm assembler

The production assembler for the MS-DOS source. JWasm targets MASM
compatibility much more closely than `wasm -zcm=masm`
(notably `-Zm` = MASM 5.1 mode, multi-pass, full macro engine). The custom fork
also implements MASM 5.10 structured-macro whitespace arguments and
case-insensitive DOS include lookup, so the assembler consumes the real source
tree without a generated shadow/preprocessor tree. C compilation, linking, and
library creation use the pinned custom Open Watcom toolchain.

Used via `bin/jwasm-masm` as the build's MASM-compatible assembler wrapper.

## Required version

The migration uses the project fork's **`custom` branch**, currently commit
`4c2f0a2f7440ca40a8cfa6718ac3ffd74ca1f9d9`. It is based on upstream's
2026-07-01 snapshot (`7f6f32e`, 11 commits
newer than `v2.21pre1`) and carries the MS-DOS compatibility fixes, including
MASM-compatible PUBLIC-name casing, native macOS `alloca` support, MASM 5.1
forward-JMP sizing, forward-conditional-branch sizing, and indexed
structure-member operand sizing. It also preserves a structure member's scalar
type through an `EQU` alias, as MASM 5.1 does. The current revision additionally
keeps `.ALPHA` segment indices and saved fixup frames synchronized and emits
MASM-compatible explicit external OMF frames. These fixes prevent runtime
parser corruption in KEYB and MODE and restore DISKCOMP's volume-serial
comparison behavior, and keep SELECT's external data offsets member-relative
when its historical real-mode group exceeds 64 KiB, while retaining short
forward conditional branches. It additionally accepts the structured macro
syntax and case-insensitive include spelling used by the historical tree. In
particular, upstream v2.20 is not an equivalent fallback for this branch.

The host binaries are built locally and gitignored. `jwasm/build.sh` clones and
checks out the exact source pin before installing the binary for the current
host, so no persistent source checkout or manual patch is required.

## Building (macOS arm64 / clang)

The vendored binary under `macos-arm64/` is gitignored (built locally). To
rebuild:

```sh
./jwasm/build.sh
```

The script supports macOS arm64 and Linux x86-64 and installs the native binary
under the matching `jwasm/` platform directory.

## Validation

The pinned custom build completes clean full-tree builds with GNU Make at
`-j1`, `-j4`, and `-j8`. A deployed FAT12 image boots the JWasm-built IO.SYS,
MSDOS.SYS, and COMMAND.COM stack in QEMU. See `TODO.md` and the MS-DOS
submodule's `jwasm-migration` branch for the compatibility changes and
validation history.
