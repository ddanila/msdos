# Open Watcom V2 — Vendored Binaries

Pre-built host binaries from the [Open Watcom V2](https://github.com/open-watcom/open-watcom-v2)
project, vendored for reproducible builds without requiring a system-level install.

## Source

Base release tag: **2026-03-01-Build**
URL: https://github.com/open-watcom/open-watcom-v2/releases/tag/2026-03-01-Build
Asset: `ow-snapshot.tar.xz`

Current repo state:
- `bin/macos-arm64/` still matches the release snapshot.
- `bin/linux-x64/wasm` is currently replaced with a locally built `open-watcom-v2` fork binary so in-flight WASM fixes can be tested in this tree before a new upstream release is vendored.
- `bin/linux-x64/wcc`, `wlink`, and `wlib` still come from the release snapshot.

## Layout

| Directory         | Platform           | Extracted from |
|-------------------|--------------------|----------------|
| `bin/linux-x64/`  | Linux x86-64       | `binl64/`      |
| `bin/macos-arm64/`| macOS Apple Silicon| `armo64/`      |

## Tools included

| Binary  | Role                        | Replaces      |
|---------|-----------------------------|---------------|
| `wasm`  | Assembler (MASM-compatible) | MASM 5.x      |
| `wcc`   | 16-bit C compiler           | CL.EXE        |
| `wlink` | Linker                      | LINK.EXE      |
| `wlib`  | Library manager             | LIB.EXE       |

## Updating

To update to a newer release:
1. Download `ow-snapshot.tar.xz` from the desired release tag
2. Extract: `tar -xJf ow-snapshot.tar.xz ./binl64/wasm ./binl64/wcc ./binl64/wlink ./binl64/wlib ./armo64/wasm ./armo64/wcc ./armo64/wlink ./armo64/wlib`
3. Copy into the respective `bin/` subdirs
4. Update this README with the new tag
