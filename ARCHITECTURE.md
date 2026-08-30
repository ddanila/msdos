# System architecture

This repository builds and tests a DOS 6.22-compatible system from the
maintained sources in `src/`. The production build is host-native: it does not
run DOS programs or proprietary Microsoft tools.

## Toolchain

| Role | Implementation |
| --- | --- |
| MASM-compatible assembly | pinned custom JWasm via `bin/jwasm-masm` |
| 16-bit C compilation | vendored custom Open Watcom via `bin/wcc` |
| OMF linking and libraries | vendored custom Open Watcom via `bin/wlink` and `bin/wlib` |
| Historical data/image tools | native programs and scripts under `bin/` |
| Runtime testing | kvikdos for fast command tests; QEMU for the complete machine |

Exact tool revisions and provenance are recorded in `jwasm/README.md` and
`watcom/README.md`. The wrappers implement only the historical command-line
surface used by this tree and reject unknown options.

## Retained compatibility operations

Some narrow transformations remain part of the build contract:

- `fix-exepack` replaces a recognized defective EXEPACK decompressor stub;
- `exefix` changes requested MZ allocation fields;
- `patch-bpb` writes deployment geometry into the boot sector;
- `wlib` normalization clears nondeterministic archive timestamps;
- `wcc` provides a temporary case-insensitive include view.

Focused tests constrain each operation. Do not broaden them into general
post-processing or source rewriting. The production tree has no assembly
shadow tree, generated-message rewriter, kernel entry patch, global MZ-header
rewrite, or DOS-emulated build step.

## Memory architecture

The kernel implements DOS 5 allocation strategies and conventional/UMB arena
linking. SYSINIT acquires UMB extents through standard XMS, and the repository
HIMEM/EMM386 pair provides XMS 3.00, HMA ownership, stable UMB mappings, and EMS
isolation. `DOS=HIGH`, `DOS=UMB`, `DEVICEHIGH`, `INSTALLHIGH`, `LOADHIGH`/`LH`,
and UMB-aware `MEM` use that shared model. See [MEMORY.md](MEMORY.md) for the
invariants maintainers must preserve.

## Reproducibility and validation

Production recipes are parallel-safe and keep temporary state private to each
invocation. The release contract is:

1. a pristine build with the pinned tools;
2. byte-identical declared artifacts across `make -j1`, `-j4`, and `-j8`;
3. `make test` with complete coverage manifests and no unexpected skips;
4. `make deploy`;
5. the complete QEMU matrix for kernel, utilities, drivers, filesystems, and
   memory managers;
6. green GitHub Actions for the exact commit.

Coverage is contract-based rather than line-based. Its enforced inventories
and commands are documented in [tests/COVERAGE.md](tests/COVERAGE.md).

## Maintenance direction

Current work should deepen behavioral compatibility, keep tool pins current,
or remove an adapter after its replacement passes the complete release gate.
Concrete gaps belong in [TODO.md](TODO.md); completed work belongs in Git
history.
