# Repository consolidation plan

Last reviewed: 2026-08-29.

## Goal

Make `ddanila/msdos` the single canonical repository for the maintained DOS
system, its source, build environment, tests, documentation, and release
images. Preserve the complete history and provenance of `ddanila/MS-DOS`, then
archive that repository as a read-only historical source with a pointer to the
canonical project.

The custom JWasm, Open Watcom, and kvikdos forks remain separate repositories.
They have independent upstream histories, synchronization policies, and
release cycles, so folding them into the DOS repository would not improve the
source/build boundary.

## Why consolidate

The current submodule boundary reflects an earlier state in which `MS-DOS` was
an almost unchanged source publication and `msdos` was only its build and test
environment. That distinction no longer describes the project: DOS source,
tests, build rules, documentation, and deployed images now evolve together.

Consolidation provides:

- atomic source, test, build, and documentation changes;
- one repository to clone, build, report against, and release from;
- one CI result for the exact source and toolchain state;
- no submodule pointer updates or cross-repository ordering constraints;
- preserved historical provenance through a history-aware import.

This is a repository-layout migration. It must not deliberately change DOS
behavior, tool revisions, generated artifacts, or the release contract.

## Historical milestone tags

Create the following immutable annotated tags in `ddanila/msdos` before the
repository-layout change:

1. `milestone-golden-checksums` — the first verified state at which the
   original golden checksum target was achieved for its complete declared
   artifact set.
2. `milestone-help-and-fixes` — the verified state at which `/?` command help
   was implemented across its declared scope and the associated known defects
   were fixed.
3. `milestone-oss-toolchain` — the first verified state that built the complete
   system with the open-source native JWasm and Open Watcom toolchain and
   passed its full release gate without proprietary Microsoft build tools.
4. `milestone-umb` — the verified completion of the DOS 5-compatible HMA/UMB
   implementation, including the shipped provider, high loaders, memory APIs,
   diagnostics, compatibility tests, and green full CI.

The tags describe capabilities, not individual commits or internal migration
steps. Do not select commits from messages alone. For each milestone:

- inspect the implementation, documentation, tests, and CI history around the
  candidate boundary;
- identify the earliest commit that satisfies the complete milestone, unless
  a later corrective commit is required to make that state genuinely usable;
- reproduce the relevant build and tests where the historical toolchain still
  permits it;
- record the `msdos` commit, its `MS-DOS` gitlink commit, the acceptance
  criteria, and available CI or local verification evidence in the annotated
  tag message;
- review all four mappings together before publishing any tags;
- never move or overwrite a published milestone tag.

These are whole-project tags and therefore belong in `msdos`. Source commits
remain directly addressable through the preserved imported history and the
source commit recorded in each annotation.

## Phase 1: inventory and safety

1. Record the exact default branches, remotes, submodule commit, outstanding
   worktree state, tags, and branch protections in both repositories.
2. Confirm that every source commit reachable from the maintained `MS-DOS`
   branch is available locally and on `ddanila/MS-DOS`.
3. Create recoverable private backup refs for the pre-consolidation branch tips.
   These are operational safeguards, not additional public milestone tags.
4. Confirm that no build, CI, release, documentation, or external automation
   depends on cloning `MS-DOS` directly without an update path.
5. Resolve or preserve every intentional dirty/generated file before beginning
   the import. Do not let generated artifacts become part of the source
   history accidentally.

## Phase 2: reconstruct and publish milestones

1. Locate candidate commits for all four milestone definitions.
2. Build an evidence table containing the candidate `msdos` commit, referenced
   `MS-DOS` commit, relevant tests, and CI run.
3. Audit boundary commits to ensure each tag represents the complete named
   capability rather than the first partial implementation.
4. Create annotated tags locally and inspect their targets and messages.
5. Publish the four tags to `ddanila/msdos` only after the complete mapping is
   reviewed and accepted.

Tag reconstruction is independent of the source import. If a historical state
cannot be rebuilt on a current host, document the exact limitation and use
repository evidence; do not silently weaken the milestone definition.

## Phase 3: import the source history

Use a history-preserving Git merge/subtree procedure without squashing. A plain
filesystem copy is not acceptable.

1. Fetch `ddanila/MS-DOS:main` into a temporary local ref.
2. Remove the `MS-DOS` gitlink in a dedicated migration commit while retaining
   its final commit identity in the commit message.
3. Merge the source repository's history into `msdos` with unrelated-history
   ancestry preserved, placing the maintained source tree under `src/`.
4. Initially retain the source tree's internal `v4.0` layout. Flattening or
   renaming that historical layout is optional follow-up work and must not be
   mixed with the history import.
5. Update build paths, scripts, coverage inventories, CI, release workflows,
   and documentation from the submodule path to `src/v4.0`.
6. Remove `.gitmodules` and all submodule initialization instructions once no
   tracked gitlink remains.
7. Keep source attribution, copyright notices, and license files intact.

The import commit must make it possible to trace any maintained source file
back into the original `MS-DOS` commit graph. Record the exact import method and
old/new branch tips in its commit message.

## Phase 4: make the monorepo self-consistent

Update the repository as one product:

- make `README.md` describe a single source/build/test repository;
- update `PLAN.md`, `TODO.md`, `KEYNOTES.md`, coverage documentation, and tool
  provenance paths;
- replace source-repository URLs intended for contributors with paths in the
  canonical repository while retaining provenance links where historically
  useful;
- make clean checkout, build, test, deploy, and release instructions contain
  no submodule step;
- ensure scripts derive paths from the repository root and do not retain a
  hidden assumption about the former `MS-DOS` directory;
- update CI caches and path filters so source changes trigger every required
  build and runtime gate;
- keep custom tool forks pinned exactly as before the migration.

Do not combine unrelated source cleanup, feature development, tool upgrades,
or generated-file normalization with this phase.

## Phase 5: acceptance gate

The consolidated repository is acceptable only when all of the following hold:

1. A fresh clone requires no submodule initialization and contains all DOS
   source needed for the build.
2. The native toolchain builds the complete artifact set from clean inputs.
3. Serial and parallel builds retain their existing reproducibility contract.
4. `make test` and every strict coverage manifest pass.
5. `make deploy` produces the expected bootable images.
6. The complete QEMU matrix, independent UMB-provider check, and recorded
   cycle-accurate gate remain satisfied.
7. Representative pre-import and post-import binaries are byte-identical. Any
   unavoidable metadata difference must be isolated, explained, and approved.
8. All repository documentation and release automation refer to the canonical
   layout.
9. Git history can trace imported source files to commits formerly in
   `ddanila/MS-DOS`.
10. GitHub Actions is green for the exact final consolidation commit.

The existing split repositories remain authoritative until this entire gate
passes. A failed migration can therefore be abandoned without changing either
published branch.

## Phase 6: handoff and archive

After the acceptance gate is green:

1. Make `ddanila/msdos` the documented canonical clone, development, issue,
   release, and CI location.
2. Replace the active `ddanila/MS-DOS` README with a concise archival notice
   that identifies its final active commit and links to the imported source in
   `ddanila/msdos`.
3. Disable active CI or release automation in the historical repository where
   it would otherwise create misleading results.
4. Archive `ddanila/MS-DOS` on GitHub without deleting its branches, tags, or
   releases.
5. Verify that old commit URLs remain accessible and that the four milestone
   tags resolve in the canonical repository.

Do not delete `ddanila/MS-DOS`. Its retained repository and the imported commit
graph provide complementary provenance and a straightforward recovery path.

## Completion definition

Consolidation is complete when `ddanila/msdos` alone can be cloned, audited,
built, tested, and released; the four capability milestones are immutably
tagged with evidence; imported source history is traceable; exact final CI is
green; and `ddanila/MS-DOS` is preserved as a clearly marked read-only archive.
