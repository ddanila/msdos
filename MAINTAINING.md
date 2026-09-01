# Maintaining the system

The architecture and release contract are in [ARCHITECTURE.md](ARCHITECTURE.md).
This file records operational constraints that are easy to violate.

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
kvikdos behavior plus strict machine-readable coverage checks. QEMU tests 386+
machine behavior; 86Box is authoritative for real-BIOS 286 behavior. See
`EMULATION.md` for the backend split.

Coverage is contract based rather than source-line based. The manifests derive
their inventories from source and build metadata, reject stale evidence, and
require runnable tests wired into the local test graph. Automatic CI is paused;
see `tests/COVERAGE.md`.

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
