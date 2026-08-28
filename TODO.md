# Open work

The native-toolchain migration and its compatibility-layer cleanup are
complete. This file lists future work only; completed implementation history is
available from Git.

## Preserve the release gate

For changes that affect generated binaries or runtime behavior:

- keep focused host contracts and all strict coverage manifests green;
- prove pristine serial and parallel build reproducibility;
- run `make deploy` and the relevant QEMU suites;
- run the complete QEMU matrix before changing golden artifacts or declaring a
  toolchain update complete;
- require green `ddanila/msdos` CI for the exact pushed implementation commit.

## Extend behavioral depth

The current coverage inventories are complete for their declared interfaces.
Future tests should improve contract depth, especially at boundaries, recovery
paths, state transitions, and multi-component interactions. New coverage must
be source-derived where possible and represented in the appropriate JSON
manifest under `tests/`.

Do not add tests merely to raise a count. A useful test distinguishes behavior,
kills a plausible mutation, or protects a previously observed defect. Keep
fast deterministic command behavior in kvikdos and use QEMU for hardware,
kernel, filesystem, TSR, driver, and interactive behavior.

## Maintain tool pins

Periodically evaluate new snapshots of the three tool forks:

- `ddanila/JWasm:custom`;
- `ddanila/open-watcom-v2:custom`;
- `ddanila/kvikdos:custom`.

Update one tool family at a time. Record its exact source revision and host
binary hashes, rebuild from a pristine checkout, compare artifacts, and run the
full validation gate. Keep fork `master` branches clean for upstream sync; all
project changes belong on `custom`.

## Reduce retained adapters only with evidence

The retained operations are documented in `KEYNOTES.md` and `PLAN.md`. They are
small, explicit, and tested. Removing one is valuable only when the underlying
tool natively provides the same behavior and all focused, reproducibility, and
runtime gates still pass. Do not replace a documented adapter with an implicit
or host-specific workaround.

## Documentation maintenance

Keep documentation present tense and implementation backed:

- `README.md` is the user entry point;
- `PLAN.md` records architecture and durable decisions;
- `KEYNOTES.md` records maintainer constraints and diagnostic knowledge;
- component READMEs record exact tool provenance;
- `tests/COVERAGE.md` explains the enforced coverage model.

Do not append build diaries or completed task transcripts. Fold durable findings
into the appropriate document and rely on Git history for chronology.
