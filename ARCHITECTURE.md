# System architecture

This repository builds and tests a DOS 6.22-compatible system from the
maintained sources in `src/`. The production build is host-native: it does not
run DOS programs or proprietary Microsoft tools.

## Toolchain

| Role | Implementation |
| --- | --- |
| MASM-compatible assembly | pinned custom JWasm via `bin/jwasm-masm` |
| 16-bit C compilation | vendored Open Watcom via `bin/wcc` |
| OMF linking and libraries | vendored Open Watcom via `bin/wlink` and `bin/wlib` |
| Historical data/image tools | native programs and scripts under `bin/` |
| Runtime testing | kvikdos for fast command tests; QEMU for 386+ machines; 86Box for real-BIOS 286 acceptance |

Tool pins and provenance are recorded in [jwasm/README.md](jwasm/README.md) and
[watcom/README.md](watcom/README.md). The wrappers implement only the historical
command-line surface used by this tree and reject unknown options.

## Retained compatibility operations

Some narrow transformations remain part of the build contract:

- `fix-exepack` replaces a recognized defective EXEPACK decompressor stub;
- `exefix` changes requested MZ allocation fields;
- `patch-bpb` writes deployment geometry into the boot sector;
- `wlib` normalization clears nondeterministic archive timestamps;
- `wcc` provides a temporary case-insensitive include view;
- COMMAND derives its critical-message layout with
  `tools/layout_command_critical_catalog.py`.

Keep these transformations narrow and covered by focused tests. Production
assembly consumes the maintained source directly; experimental image builders
under `tests/` have separate layout and mutation contracts.

## Memory architecture

DOS conventional/UMB allocation and the HIMEM/EMM386 memory services share an
ownership model. The opt-in composed BIOS, COMMAND, and paired-provider layouts
are under stabilization and need separate qualification from the default image.
[MEMORY.md](MEMORY.md) records ownership and promotion constraints.

## Reproducibility and validation

Builds must remain parallel-safe. Validate a release with:

1. a pristine build with the pinned tools;
2. byte-identical declared artifacts across pristine `make -j1`, `-j4`, and `-j8`
   builds on the same host/toolset;
3. `FAIL_ON_SKIP=1 make test` with complete coverage manifests;
4. `make deploy` and `make distribution` for installation media;
5. the applicable QEMU and 86Box matrices for kernel, utilities, drivers,
   filesystems, and memory managers.

Automatic GitHub Actions are intentionally paused during active development.
Local results are the release authority until they are re-enabled.

Coverage is contract-based rather than line-based. Its enforced inventories
and commands are documented in [tests/COVERAGE.md](tests/COVERAGE.md).

## Maintenance direction

Current work should deepen behavioral compatibility, keep tool pins current,
or remove an adapter after its replacement passes the complete release gate.
Concrete gaps belong in [TODO.md](TODO.md); completed work belongs in Git
history.
