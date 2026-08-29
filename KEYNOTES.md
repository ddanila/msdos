# Maintainer notes

These notes capture constraints that are easy to violate and difficult to
rediscover.

## Build architecture

The default Makefile is the only production build path:

- `bin/jwasm-masm` translates the historical MASM invocation and runs the
  pinned custom JWasm in MASM 5.1 mode.
- `bin/wcc`, `bin/wlink`, and `bin/wlib` translate the Microsoft-style command
  forms used by the source makefiles and run vendored Open Watcom tools.
- `bin/buildmsg`, `bin/buildidx`, `bin/exe2bin`, `bin/convert`, `bin/dbof`,
  `bin/nosrvbld`, `bin/menubld`, `bin/asc2hlp`, `bin/compress`, and
  `bin/mkcntry` are native implementations of required historical build
  operations.
- kvikdos is used only by `make test`. Production targets do not execute DOS
  programs.

The wrappers reject unknown options. If a newly encountered option has real
semantics, translate it and add a focused contract. Do not silently ignore it.

## Retained compatibility operations

The cleanup deliberately retains a small set of transformations:

- `bin/wcc` creates a temporary case-insensitive include view because the DOS
  sources do not use host-consistent filename case. The source tree itself is
  not rewritten.
- `bin/wlib` clears OMF library-member timestamps for reproducible archives.
- `bin/fix-exepack` replaces a known broken decompressor stub in affected
  packed executables. It is idempotent and limited to recognized images.
- `bin/exefix` updates only the requested MZ allocation fields for targets whose
  runtime contract requires them.
- `bin/patch-bpb` constructs the deployment image's BIOS parameter block.
- `buildidx` treats the checked-in message catalog as read-only.

Focused contracts for these operations live in
`tests/test_toolchain_transforms.py`, `tests/test_kernel_layout.py`, and
`tests/test_native_build_tools.sh`. Any attempt to remove or broaden a retained
operation must update those contracts and pass the full runtime gate.

There is no assembly shadow preprocessor, generated-message rewriter, kernel
entry-byte patch, or global MZ-header canonicalizer. JWasm consumes the actual
source paths and native `exe2bin` accepts valid compact MZ headers.

## Source bytes and line endings

MS-DOS assembly and data files are not uniformly UTF-8. Some contain CP437
banner bytes. For a text-level edit, Latin-1 provides a one-byte round trip:

```python
from pathlib import Path

path = Path("src/path/to/file.asm")
text = path.read_text(encoding="latin-1")
text = text.replace("old", "new")
path.write_text(text, encoding="latin-1")
```

Compute replacement content before opening a file for writing. Afterward,
inspect `git diff --stat` and the exact diff; widespread comment changes usually
mean an encoding mistake.

The MS-DOS `.gitattributes` policy is significant:

- assembly, C, headers, and includes use LF;
- DOS message and build-control text may require CRLF because native message
  tools compute byte offsets from the on-disk representation.

`USA-MS.MSG` uses historical CRLF bytes because message offsets depend on its
on-disk representation.

Keep new source, comments, documentation, commit messages, and automation text
ASCII unless a historical file specifically requires other bytes.

## Parallel-build isolation

Build recipes and tests may run concurrently. Temporary files, floppy images,
serial logs, sockets, and kvikdos working directories must be private to one
invocation. Never use a shared fixed scratch name for a parallel target.

`bin/dos-run` serializes the unavoidable host-backed kvikdos directory behavior
while preserving parallel execution elsewhere. QEMU tests that mutate an image
must copy the canonical deployed image and honor their `FLOPPY_IMAGE` override.
The canonical `out/floppy.img` is immutable test input once deployment finishes.

The reproducibility gate compares pristine `-j1`, `-j4`, and `-j8` builds.
QEMU itself should run at moderate concurrency on small hosts; emulator timeout
under CPU oversubscription is not evidence of a build race.

## Message generation

`.SKL` files plus `src/MESSAGES/USA-MS.MSG` produce `.CTL` and `.CL*` assembly
includes. A direct one-file assembler experiment can therefore fail because it
did not run the prerequisite message rule. Reproduce the Make dependency chain
before diagnosing such an error as an assembler problem.

Raw BUILDMSG output is the supported input. COMMAND, SYS, and FORMAT assemble
and link it without a post-generation rewrite.

When diagnosing include lookup, reproduce the module's Make rule, including
its source directory and include arguments; an isolated assembler invocation
may exercise a different search path.

## Kernel and executable layout

The source-defined kernel START segment begins at load offset zero and contains
the near jump to `DOSINIT`. Shared DOSGROUP data must retain the same offsets in
the kernel and resident programs; moving CODE ahead of shared data can produce
a bootable kernel that corrupts utilities such as SHARE. The layout contract in
`tests/test_kernel_layout.py` checks both properties.

Do not infer a load offset from a hard-coded 512-byte MZ header. Read
`e_cparhdr` and the other MZ fields. The native `exe2bin` implementation and its
focused tests support compact valid headers emitted by WLINK.

## Testing model

`make test` is a test target, not a build dependency. Build first. It runs fast
kvikdos behavior plus strict machine-readable coverage checks. The QEMU targets
test behavior that needs a real DOS machine model: boot, interrupts, block
devices, filesystem mutation, drivers, TSRs, interactive I/O, and EMM386.

Coverage is contract based rather than source-line based. The manifests derive
their inventories from source and build metadata, reject stale evidence, and
require runnable tests wired into CI. See `tests/COVERAGE.md`.

## Repository ownership

All project-specific work stays under `github.com/ddanila`:

- `ddanila/msdos:master` for the maintained system, source,
  build, tests, documentation, and releases;
- archived `ddanila/MS-DOS:main` commits remain provenance for source history;
- `ddanila/JWasm:custom` for assembler compatibility;
- `ddanila/open-watcom-v2:custom` for compiler/linker/library changes;
- `ddanila/kvikdos:custom` for emulator test support.

The `master` branches of the Open Watcom and kvikdos forks are reserved for
upstream synchronization; project-specific changes live on `custom`.
Do not send project changes to upstream repositories without maintainer
approval.

## Expensive diagnostics

Capture an expensive command once, then inspect its log:

```sh
make -k -j8 2>&1 | tee /tmp/msdos-build.log
rg -a 'error|warning|failed' /tmp/msdos-build.log
```

Compare clean-file, failed-target, crash, artifact, and runtime results rather
than relying on raw assembler error count. A fix can expose more diagnostics by
allowing a file to progress farther.
