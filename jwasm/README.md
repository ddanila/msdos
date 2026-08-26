# JWasm (experimental assembler path)

Experimental alternative to the Open Watcom `wasm` assembler for the MS-DOS
source. JWasm targets MASM compatibility much more closely than `wasm -zcm=masm`
(notably `-Zm` = MASM 5.1 mode, multi-pass, full macro engine), which lets us
drop `bin/preprocess-wasm` and most WASM-specific source edits. C compilation
still uses Open Watcom (`bin/cl` -> `wcc`); JWasm and wcc both emit OMF, so they
interoperate and link with `wlink`/MS LINK.

Used via `bin/jwasm-masm` (drop-in for `bin/masm`/`bin/wasm-masm`).

## Required version

The migration uses the project fork's **`custom` branch**, currently commit
`f32b9dae220c2e2a11fd31ff7bfc47397c8908d5`. It is based on upstream's
2026-07-01 snapshot (`7f6f32e`, 11 commits
newer than `v2.21pre1`) and carries the MS-DOS compatibility fixes, including
MASM-compatible PUBLIC-name casing and native macOS `alloca` support. In
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

## Status

See `TODO.md` (JWasm experiment section) and the MS-DOS submodule
`jwasm-migration` branch for the STRUC.INC adaptations JWasm needs.
