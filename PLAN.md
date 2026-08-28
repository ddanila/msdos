# Native MS-DOS 4.0 toolchain architecture

This document records the finished toolchain design, the compatibility
operations that remain intentionally, and the rules for future evolution. It is
not a migration log.

Last reviewed: 2026-08-28.

## Goal and current state

The complete MS-DOS 4.0 image builds on Linux and macOS with an open-source,
host-native toolchain. The production build does not execute proprietary
Microsoft tools or DOS programs.

| Layer | Implementation | Status |
| --- | --- | --- |
| MASM-compatible assembler | pinned `ddanila/JWasm:custom`, through `bin/jwasm-masm` | complete |
| 16-bit C compiler | vendored custom Open Watcom `wcc`, through `bin/wcc` | complete |
| OMF linker | vendored custom Open Watcom `wlink`, through `bin/wlink` | complete |
| OMF library manager | vendored custom Open Watcom `wlib`, through `bin/wlib` | complete |
| Historical build utilities | native repository implementations | complete |
| DOS runtime testing | pinned `ddanila/kvikdos:custom` and QEMU | test-only |

Every production assembly file is assembled from its checked-in source path.
Every C-bearing target, including EMM386, uses Open Watcom. The build creates
the boot files, kernel, utilities, drivers, libraries, message data, SELECT
data, and deployable floppy without an emulator.

Exact tool revisions, provenance, and host binary hashes are maintained in
`jwasm/README.md` and `watcom/README.md`.

## Why JWasm and Open Watcom

MS-DOS 4.0 requires strong MASM 5.1 macro compatibility, 16-bit OMF output, a
16-bit real-mode C ABI, OMF libraries, and an MZ/COM-capable linker. Custom
JWasm and Open Watcom provide that combination natively on supported hosts.

Alternatives do not improve the complete system:

- UASM is JWasm-derived but does not remove the linker or C-runtime work.
- Asmc can replace the assembler under a different license policy, but the
  16-bit OMF linker remains Open Watcom and the source would require complete
  revalidation.
- gcc-ia16 uses a different object format and ABI.
- Digital Mars C requires a Windows or emulated host path.
- JWlink is useful diagnostically but is much less actively maintained than
  the Open Watcom linker used here.

The toolchain is therefore a deliberate system choice, not an interim
migration configuration.

## License policy

JWasm and Open Watcom use the Sybase Open Watcom Public License, an
OSI-approved license. This project targets the OSI-approved definition rather
than an FSF-free or Debian-main-only toolchain. Tool binaries are build inputs;
they are not linked into the distributed DOS programs.

Preserve all original source copyright notices and the licenses accompanying
vendored tools. Project-specific tool changes live in public `ddanila` forks.
No upstream interaction is authorized without explicit owner permission.

## Native historical build operations

The repository owns deterministic host implementations of the former
DOS-hosted build utilities:

- `buildmsg` and `buildidx` generate message assembly and index data;
- `nosrvbld`, `menubld`, `asc2hlp`, and `compress` generate utility data;
- `dbof` converts binary data to assembly include form;
- `exe2bin` converts valid MZ images to load images;
- `convert` creates self-relocating COM images from MZ executables;
- `mkcntry` extracts the source-built COUNTRY.SYS payload.

Their tests compare exact binary structure and relevant historical reference
outputs. They are implementations of required build formats, not source
preprocessors.

## Tool adapters

The wrappers expose only the Microsoft-style option subset used by the source
makefiles. They reject unknown arguments so new behavior cannot disappear as a
silent no-op.

`bin/jwasm-masm` translates MASM invocation syntax and runs custom JWasm in
MASM 5.1 mode. Custom JWasm supplies case-insensitive include resolution,
structured-macro whitespace parsing, correct OMF segment/fixup handling, and
the other compatibility behavior documented in `jwasm/README.md`.

`bin/wcc` translates the 16-bit memory model, calling convention, packing,
optimization, include, and output options. It builds a temporary
case-insensitive include view where DOS filename spelling requires it. It does
not alter the checked-in source tree.

`bin/wlink` parses the response-file and comma-field command forms used by the
historical build. It translates meaningful LINK semantics including DOSSEG,
stack, packing, ordering, case handling, and library lookup. It leaves valid MZ
header sizing intact.

`bin/wlib` translates the library command form and normalizes OMF member
timestamps after creation so repeated builds are deterministic.

## Retained binary and image operations

Four narrow operations remain because the output format or real DOS behavior
requires them:

1. `fix-exepack` replaces the recognized defective EXEPACK decompressor stub.
   It is idempotent and does not modify unrelated executables.
2. `exefix` changes only requested MZ `MINALLOC` and `MAXALLOC` fields for
   targets with explicit memory-allocation requirements.
3. `patch-bpb` writes deployment geometry into the boot sector as part of
   constructing the FAT image.
4. WLIB timestamp normalization clears nondeterministic archive metadata.

`buildidx` treats the checked-in message catalog as read-only.

Focused tests define the permitted byte changes and idempotence. These
operations may be removed when the underlying format no longer requires them;
they must not be generalized into broad post-link rewriting.

## Explicitly retired mechanisms

The production tree has none of the following:

- an assembly shadow-tree preprocessor;
- a generated-message forward-reference rewriter;
- a post-`exe2bin` kernel entry-byte patch;
- global expansion of WLINK output to a 512-byte MZ header;
- Microsoft CL, LINK, LIB, or helper binaries;
- kvikdos in a production recipe;
- Homebrew-specific macro or source rewriting.

Custom JWasm emits the historical source-defined segment order. The unpatched
kernel starts with its source `JMP DOSINIT`, and replicated DOSGROUP variables
retain the same offsets in resident programs. Native `exe2bin` reads MZ fields
rather than assuming a fixed header size.

## Parallelism and reproducibility

Production recipes may execute concurrently. Each wrapper invocation owns its
temporary directories and output files. Test runners isolate mutable images,
logs, sockets, and host-backed DOS directories. The small unavoidable kvikdos
host-directory critical section is serialized without serializing the build or
the rest of the test suite.

The reproducibility contract is exact equality of the complete artifact set
across pristine `-j1`, `-j4`, and `-j8` builds using one pinned host toolset.
Cross-host differences are investigated when updating the toolchain, while
behavioral contracts remain the release criterion on every supported host.

## Validation model

No single smoke test proves this toolchain. The release gate is:

1. focused native-tool and compatibility-transform contracts;
2. a pristine build with the exact custom JWasm and vendored Open Watcom pins;
3. deterministic `-j1`, `-j4`, and `-j8` artifact sets;
4. the complete fast kvikdos behavior suite and strict coverage manifests;
5. `make deploy` from clean generated inputs;
6. the complete QEMU runtime matrix, including kernel APIs, SYS, FORMAT,
   FDISK, C utilities, drivers, TSRs, filesystems, and EMM386;
7. green GitHub Actions for the exact implementation commit.

The cleanup implementation at `953332b` passed all 39 jobs in
[GitHub Actions run 33117104290](https://github.com/ddanila/msdos/actions/runs/33117104290).
That run built the pinned custom JWasm, built all modules, passed `make test`,
deployed the images, and passed the complete QEMU matrix.

Coverage completeness is enforced by source-derived JSON inventories and
strict verifiers under `tests/`. `tests/COVERAGE.md` is the authoritative
description of that model.

## Maintenance direction

The migration and cleanup milestones are closed. Future work falls into three
categories:

- deepen behavioral contracts where a boundary, recovery path, or interaction
  can be distinguished more precisely;
- evaluate newer custom tool snapshots without weakening deterministic or
  runtime validation;
- retire a documented adapter only after the underlying tool supplies
  equivalent behavior and every validation layer passes without it.

Concrete open work belongs in `TODO.md`. Completed task chronology belongs in
Git history, not in documentation.
