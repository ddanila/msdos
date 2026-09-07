# Vendored Open Watcom V2

Pre-built host binaries from the project's
[custom Open Watcom V2 fork](https://github.com/ddanila/open-watcom-v2/tree/custom),
vendored for reproducible builds without requiring a system-level install.

## Source

Base build: upstream **Current-build** snapshot from August 25 2026,
revision `7d1bc7c50a2a2ac6228c6323d916e7b8733e1d10`, distributed as
`ow-snapshot.tar.xz`.

Project source fork: [`ddanila/open-watcom-v2:custom`](https://github.com/ddanila/open-watcom-v2/tree/custom).
Linux custom build revision: `1e6b2b4d546ac5d60fafbb986d84c615fd4b26d0`.

The macOS arm64 `wlink` is built from custom source revision
`b0c4a1ec0342ef14e9ff0df02e29a05e8fd0a620`. Its compatibility fixes support
oversized real-mode groups, wrapped negative absolute OMF fixups, and explicitly
sized real-mode stacks required by this tree.

The Linux x86-64 `wcc`, `wlib`, and `wlink` were built together from the custom
revision by [workflow run 33046977965](https://github.com/ddanila/open-watcom-v2/actions/runs/33046977965).
The remaining macOS tools and both unused OW `wasm` binaries come from the base
release snapshot; production assembly uses the separately pinned custom JWasm.

## Use

`bin/linux-x64/` and `bin/macos-arm64/` contain the host tools selected by the
parent repository's wrappers. Production uses `wcc`, `wlink`, and `wlib`;
the included `wasm` binaries are unused. `lib286/` supplies the DOS C runtime.

Host builds are deterministic within each pinned toolset, but independently
built Linux GCC and macOS Clang host compilers do not promise byte-identical
16-bit code generation. Every supported host runs the applicable behavioral
and emulator contracts.

## Updating the vendored tools

Treat a refresh as a toolchain change, not a binary-copy operation:

1. synchronize the fork's `master` from upstream without custom commits;
2. rebase or update the fork's `custom` branch and build from an exact revision;
3. extract only the required host tools and copy them into the matching
   `watcom/bin/` directories;
4. record source revisions and build provenance here; derive binary hashes
   from the vendored files when needed;
5. run focused adapter tests and the release gates in
   [ARCHITECTURE.md](../ARCHITECTURE.md).
