# Repository instructions

This file contains durable project constraints for coding agents. It is not a
status log. Current architecture is documented in `PLAN.md`; open work belongs
in `TODO.md`.

## Project state

The production build is fully native and open source:

- custom JWasm assembles every assembly source through `bin/jwasm-masm`;
- custom Open Watcom `wcc`, `wlink`, and `wlib` compile C, link images, and
  create libraries;
- native repository tools replace all historical DOS-hosted build utilities;
- kvikdos is test-only and is never part of the production build path;
- clean serial and parallel builds, `make test`, deployment, and the complete
  QEMU matrix are the release gates.

Do not reintroduce Microsoft build binaries, DOS execution in build recipes,
shadow source trees, broad post-link rewriting, or host-specific preprocessing.

## Repository and branch policy

- Work only in repositories under `github.com/ddanila` unless the owner gives
  explicit permission to interact with an upstream project.
- The superproject branch is `ddanila/msdos:master`.
- MS-DOS source changes belong in `ddanila/MS-DOS:main`; update the superproject
  gitlink only after that commit is pushed.
- JWasm changes belong in `ddanila/JWasm:custom`.
- Open Watcom and kvikdos changes belong in each fork's `custom` branch. Their
  `master` branches are upstream synchronization branches and must not receive
  custom commits.
- Preserve unrelated working-tree changes, especially generated or
  line-ending-sensitive files inside submodules.

## Source integrity

Many MS-DOS sources contain CP437 high-bit bytes and DOS text files require
specific line endings. Never decode and rewrite an entire historical source as
UTF-8 merely to change one line. Use a byte-preserving or Latin-1 round trip,
and inspect the resulting diff for unrelated high-bit changes.

The `.gitattributes` file in the MS-DOS fork defines line-ending policy. In
particular, message inputs and build-control files may require CRLF while
assembly and C sources require LF. Do not normalize these files casually.

Keep source, comments, documentation, commit messages, and automation text
ASCII unless a file's historical byte content specifically requires otherwise.

## Build and diagnostic conventions

- Run `./jwasm/build.sh` when the ignored host assembler is absent. The script
  checks out and builds the exact revision documented in `jwasm/README.md`.
- Plain `make` is the production path. Do not override the assembler or linker
  to reproduce an obsolete migration configuration.
- Capture expensive builds once and inspect the saved log. OMF output may
  contain binary bytes, so use binary-safe search options when needed.
- Use the module's Make rule when diagnosing include lookup. Hand-written JWasm
  invocations must reproduce its source directory and include arguments.
- Treat binary changes as evidence to investigate and validate with focused
  behavior, pristine reproducibility builds, and the complete QEMU matrix.
- When a tool compatibility problem is real, prefer a focused fix in the
  appropriate `ddanila` tool fork. Source changes are appropriate for actual
  source defects or deliberate MS-DOS behavior changes.

## Validation expectations

Choose validation proportional to the change, but the complete release gate is:

1. a pristine build using the pinned tools;
2. identical artifacts across `-j1`, `-j4`, and `-j8` builds;
3. `make test` with no unexpected skips;
4. `make deploy`;
5. the complete QEMU target matrix;
6. green GitHub Actions in the `ddanila/msdos` repository.

Coverage claims must be represented in the machine-readable manifests under
`tests/`, cite runnable evidence, and pass their `--require-complete` verifier.
See `tests/COVERAGE.md` for the coverage model.

## Documentation policy

Documentation describes the current system, durable design rationale, or
concrete open work. Do not append session transcripts, dated debugging diaries,
or already-completed checklists. Git history preserves chronology. When a
finding remains useful, fold it into `PLAN.md`, `KEYNOTES.md`, a component
README, or `tests/COVERAGE.md` in present-tense form.
