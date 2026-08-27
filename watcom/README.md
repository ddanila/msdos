# Open Watcom V2 — Vendored Binaries

Pre-built host binaries from the [Open Watcom V2](https://github.com/open-watcom/open-watcom-v2)
project, vendored for reproducible builds without requiring a system-level install.

## Source

Base build: **Current-build** (August 25 2026,
`7d1bc7c50a2a2ac6228c6323d916e7b8733e1d10`)
URL: https://github.com/open-watcom/open-watcom-v2/releases/tag/Current-build
Asset: `ow-snapshot.tar.xz`
Source fork: https://github.com/ddanila/open-watcom-v2/tree/custom
Custom revision: `daae27ce5b7abbb2a0c08a3fef179ea79b0d73d3`

The macOS arm64 `wlink` is built from the custom revision. In addition to the
oversized real-mode-group compatibility fixes, it permits wrapped negative
absolute OMF fixups and preserves explicitly sized real-mode stacks. These are
required respectively by DISKCOMP's `FINE EQU -1` reference and PRINT's
200-byte resident stack. Its SHA-256 is
`cd005b7805c69eac43db0c7278f39ffe0113fdecba21ab8cd3362f15e183c1d7`.

The remaining macOS tools and the Linux x86-64 tools come from the release
snapshot. The Linux custom WLINK rebuild is tracked as a portability gate; the
release WLINK remains vendored there until that native build has passed the
same SELECT runtime regression.

## Layout

| Directory         | Platform           | Extracted from |
|-------------------|--------------------|----------------|
| `bin/linux-x64/`  | Linux x86-64       | `binl64/` release snapshot |
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

## Updating release binaries

To update to a newer release:
1. Download `ow-snapshot.tar.xz` from the desired release tag
2. Extract: `tar -xJf ow-snapshot.tar.xz ./binl64/wasm ./binl64/wcc ./binl64/wlink ./binl64/wlib ./armo64/wasm ./armo64/wcc ./armo64/wlink ./armo64/wlib`
3. Copy into the respective `bin/` subdirs
4. Update this README with the new tag
