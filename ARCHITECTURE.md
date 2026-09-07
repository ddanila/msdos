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
[watcom/README.md](watcom/README.md). The adapters support the historical command
forms used by this tree; they are not general replacements for Microsoft tools. Keep compatibility transformations
narrow and covered by focused tests. Experimental image builders under `tests/`
have separate layout and mutation contracts.

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

Concrete open work belongs in [TODO.md](TODO.md).
