# Maintaining the system

Use the release gates in [ARCHITECTURE.md](ARCHITECTURE.md) and keep open work in
[TODO.md](TODO.md). Markdown should retain scope, rationale, and operational
constraints; implementation inventories belong in code/tests and completed work
in Git history.

## Preserve source bytes

Historical source contains non-UTF-8 bytes, including CP437 comments. Use
byte-preserving edits. For a targeted text replacement, Latin-1 round-trips each
byte without changing existing line endings:

```python
from pathlib import Path

path = Path("src/path/to/file.asm")
text = path.read_bytes().decode("latin-1")
updated = text.replace("old", "new")
path.write_bytes(updated.encode("latin-1"))
```

Compute the replacement before writing. Inspect the exact diff for unintended
encoding or line-ending changes. Follow [src/.gitattributes](src/.gitattributes):
source generally uses LF, while message/build-control files preserve required
DOS bytes. Message offsets depend on the on-disk representation.
Keep new project text ASCII unless historical content requires other bytes.

## Build and test isolation

Temporary files, images, logs, sockets, and emulator working directories must
be private to a run. `bin/dos-run` serializes its shared host-backed DOS boundary.
Tests that mutate deployed media must copy it and honor their image override.
Do not redeploy an image while tests are using it.

Use moderate QEMU concurrency on small hosts. Timeouts under oversubscription
do not by themselves establish a build race. Run pristine reproducibility
builds in separate clean checkouts or sequentially after cleaning.

Build before testing and select gates appropriate to the change; see
[tests/COVERAGE.md](tests/COVERAGE.md) and [EMULATION.md](EMULATION.md).

## Generated messages and linked layouts

Reproduce a module's Make rule before diagnosing an isolated assembler failure:
message prerequisites, working directory, and include paths affect the result.
BUILDMSG produces message includes; COMMAND also derives a critical-message
layout through `tools/layout_command_critical_catalog.py`.

The kernel entry must stay at load offset zero. Shared DOSGROUP offsets must
agree between the kernel and resident consumers such as SHARE and IFSFUNC;
a bootable image can still corrupt those consumers if linked layouts differ.
Rebuild them together after changing shared data. See
[MEMORY.md](MEMORY.md) for relocation constraints.

Read MZ header fields when computing executable load offsets; do not assume a
512-byte header. Keep compatibility adapters narrow and remove one only after
its replacement passes the applicable release gates.

## Repository ownership

Maintained system work belongs in `ddanila/msdos:master`, directly under `src/`.
The archived `ddanila/MS-DOS:main` is source provenance, not a build dependency.
Custom tool changes belong in `ddanila/JWasm:custom`,
`ddanila/open-watcom-v2:custom`, and `ddanila/kvikdos:custom`.
Open Watcom and kvikdos `master` branches are reserved for upstream sync.
Do not send project changes upstream without maintainer approval.

Capture expensive diagnostics once in a private log and inspect that log.
Judge failures by failed targets, artifacts, and runtime behavior as well as
individual assembler diagnostics.
