# Open Watcom V2 — Vendored Binaries

Pre-built host binaries from the [Open Watcom V2](https://github.com/open-watcom/open-watcom-v2)
project, vendored for reproducible builds without requiring a system-level install.

## Source

Base build: **Current-build** (August 25 2026,
`7d1bc7c50a2a2ac6228c6323d916e7b8733e1d10`)
URL: https://github.com/open-watcom/open-watcom-v2/releases/tag/Current-build
Asset: `ow-snapshot.tar.xz`
Source fork: https://github.com/ddanila/open-watcom-v2/tree/custom
Custom revision: `990174aef057a5be9a5868bc17b55e2e404ec66a`

The macOS arm64 `wlink` is built from the custom revision. It preserves the
release snapshot's behavior while adding Microsoft LINK-compatible handling
for oversized 16-bit real-mode groups, including member-relative external
frames and relocation locations beyond 64 KiB. Its SHA-256 is
`1b3e77a2f5cb5acc4098c25d7202acd17ea63aa3b12a2abad628fcab053109c7`.

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
