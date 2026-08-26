# Custom JWasm assembler

The production assembler for the MS-DOS source. JWasm targets MASM
compatibility much more closely than `wasm -zcm=masm`
(notably `-Zm` = MASM 5.1 mode, multi-pass, full macro engine), which lets us
drop `bin/preprocess-wasm` and most WASM-specific source edits. C compilation
still uses Microsoft C 5.10 through kvikdos; migrating the C-hybrid targets to
Open Watcom `wcc` is the separate Stage B described in `PLAN.md`.

Used via `bin/jwasm-masm` (drop-in for `bin/masm`/`bin/wasm-masm`).

## Required version

The migration uses the project fork's **`custom` branch**, currently commit
`9222ac7327f5cc23300181ab1ef8d7fdabc2fd0a`. It is based on upstream's
2026-07-01 snapshot (`7f6f32e`, 11 commits
newer than `v2.21pre1`) and carries the MS-DOS compatibility fixes, including
MASM-compatible PUBLIC-name casing, native macOS `alloca` support, MASM 5.1
forward-JMP sizing, forward-conditional-branch sizing, and indexed
structure-member operand sizing. It also preserves a structure member's scalar
type through an `EQU` alias, as MASM 5.1 does. These fixes prevent runtime
parser corruption in KEYB and MODE and restore DISKCOMP's volume-serial
comparison behavior while retaining short forward conditional branches. In
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
