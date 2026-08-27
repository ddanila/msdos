# Open Watcom V2 — Vendored Binaries

Pre-built host binaries from the project's
[custom Open Watcom V2 fork](https://github.com/ddanila/open-watcom-v2/tree/custom),
vendored for reproducible builds without requiring a system-level install.

## Source

Base build: **Current-build** (August 25 2026,
`7d1bc7c50a2a2ac6228c6323d916e7b8733e1d10`)
URL: https://github.com/open-watcom/open-watcom-v2/releases/tag/Current-build
Asset: `ow-snapshot.tar.xz`
Source fork: https://github.com/ddanila/open-watcom-v2/tree/custom
Linux build revision: `1e6b2b4d546ac5d60fafbb986d84c615fd4b26d0`

The macOS arm64 `wlink` is built from custom source revision
`b0c4a1ec0342ef14e9ff0df02e29a05e8fd0a620`. In addition to the oversized
real-mode-group compatibility fixes, it permits wrapped negative absolute OMF
fixups and preserves explicitly sized real-mode stacks. These are required
respectively by DISKCOMP's `FINE EQU -1` reference and PRINT's 200-byte resident
stack. Its SHA-256 is
`cd005b7805c69eac43db0c7278f39ffe0113fdecba21ab8cd3362f15e183c1d7`.

The Linux x86-64 `wcc`, `wlib`, and `wlink` were built together from the custom
revision by [workflow run 33046977965](https://github.com/ddanila/open-watcom-v2/actions/runs/33046977965).
Their SHA-256 hashes are respectively
`eb2ba16f29fce756e000258dd0baa519390416081c66c9da39e2cf6c9000ff7b`,
`816a07efddc00e43e973bea438bb34added9fa2b86d5a46df9a0e2ff1b9fa17e`,
and `f6699a32f53abc31888095790a58b9b95a477a38c864296d68872b44309e4721`.
The remaining macOS tools and both unused OW `wasm` binaries come from the base
release snapshot; production assembly uses the separately pinned custom JWasm.

## Layout

| Directory         | Platform           | Extracted from |
|-------------------|--------------------|----------------|
| `bin/linux-x64/`  | Linux x86-64       | `binl64/` snapshot plus custom wcc/wlib/wlink |
| `bin/macos-arm64/`| macOS Apple Silicon| `armo64/` snapshot plus custom WLINK |

## Tools included

| Binary  | Role                        | Replaces      |
|---------|-----------------------------|---------------|
| `wasm`  | Assembler (MASM-compatible) | MASM 5.x      |
| `wcc`   | 16-bit C compiler           | CL.EXE        |
| `wlink` | Linker                      | LINK.EXE      |
| `wlib`  | Library manager             | LIB.EXE       |

The vendored 16-bit DOS runtime under `lib286/` includes the model-specific C
libraries and `math87s.lib`, which Open Watcom links automatically for
small-model programs that use floating-point arithmetic.

Host builds are deterministic within each pinned toolset, but the independently
built Linux GCC and macOS Clang host compilers do not promise byte-identical
16-bit code generation. The behavioral suite therefore uses the Linux artifact
set as its canonical golden and a small macOS arm64 override file for the
artifacts known to differ after a clean build. Both sets execute the same QEMU
contracts; an unlisted platform difference remains a test failure.

## Updating release binaries

To update to a newer release:
1. Download `ow-snapshot.tar.xz` from the desired release tag
2. Extract: `tar -xJf ow-snapshot.tar.xz ./binl64/wasm ./binl64/wcc ./binl64/wlink ./binl64/wlib ./armo64/wasm ./armo64/wcc ./armo64/wlink ./armo64/wlib`
3. Copy into the respective `bin/` subdirs
4. Update this README with the new tag
