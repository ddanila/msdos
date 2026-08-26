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

The host binaries are currently built locally and gitignored, so the version is
not encoded in the repository other than by this documented source pin.

## Building (macOS arm64 / clang)

The vendored binary under `macos-arm64/` is gitignored (built locally). To
rebuild:

```sh
git clone --branch custom https://github.com/ddanila/JWasm.git
cd JWasm
git checkout f32b9dae220c2e2a11fd31ff7bfc47397c8908d5
make -f GccUnix.mak CC=clang        # compiles; link step uses Linux-only ld flags
clang build/GccUnixR/*.o -o jwasm   # link manually (drop -s / -Wl,-Map)
```

Resulting `jwasm` is a native arm64 Mach-O that emits 16-bit OMF. Copy it to
`jwasm/macos-arm64/jwasm`.

## Status

See `TODO.md` (JWasm experiment section) and the MS-DOS submodule
`jwasm-migration` branch for the STRUC.INC adaptations JWasm needs.
