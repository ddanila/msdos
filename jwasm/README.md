# JWasm (experimental assembler path)

Experimental alternative to the Open Watcom `wasm` assembler for the MS-DOS
source. JWasm targets MASM compatibility much more closely than `wasm -zcm=masm`
(notably `-Zm` = MASM 5.1 mode, multi-pass, full macro engine), which lets us
drop `bin/preprocess-wasm` and most WASM-specific source edits. C compilation
still uses Open Watcom (`bin/cl` -> `wcc`); JWasm and wcc both emit OMF, so they
interoperate and link with `wlink`/MS LINK.

Used via `bin/jwasm-masm` (drop-in for `bin/masm`/`bin/wasm-masm`).

## Required version

The migration was developed and validated with **JWasm v2.21pre1**, upstream
commit `72446dfe74f200b52d0b5d54193d23f8287b57d5`. Use that exact revision until
an upgrade has passed a clean full-tree build. In particular, v2.20 is not an
equivalent fallback for this branch: it emits many macro-argument warnings and
the resulting BIOS objects fail to link with missing symbols.

The host binaries are currently built locally and gitignored, so the version is
not encoded in the repository other than by this documented source pin.

## Building (macOS arm64 / clang)

The vendored binary under `macos-arm64/` is gitignored (built locally). To
rebuild:

```sh
git clone --depth 1 --branch v2.21pre1 https://github.com/Baron-von-Riedesel/JWasm.git
cd JWasm
# macOS uses <alloca.h>, not <malloc.h>: patch src/H/memalloc.h
#   in the __GNUC__ branch, replace
#     #ifndef __FreeBSD__
#     #include <malloc.h>
#     #endif
#   with
#     #if defined(__APPLE__)
#     #include <alloca.h>
#     #elif !defined(__FreeBSD__)
#     #include <malloc.h>
#     #endif
make -f GccUnix.mak CC=clang        # compiles; link step uses Linux-only ld flags
clang build/GccUnixR/*.o -o jwasm   # link manually (drop -s / -Wl,-Map)
```

Resulting `jwasm` is a native arm64 Mach-O that emits 16-bit OMF. Copy it to
`jwasm/macos-arm64/jwasm`.

## Status

See `TODO.md` (JWasm experiment section) and the MS-DOS submodule
`jwasm-migration` branch for the STRUC.INC adaptations JWasm needs.
