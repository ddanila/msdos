---
name: MS-DOS submodule branch policy
description: WASM-migration source edits go on the MS-DOS submodule's `watcom-migration` branch (built on top of `dos4-enhancements`); never commit migration work to `dos4-enhancements` itself
type: feedback
originSessionId: 0cdbc900-a2ce-42fb-b7e4-c361a32f1de6
---
In the MS-DOS submodule (`MS-DOS/`), there are FOUR long-lived branches:

- **`main`** — mostly the original Microsoft sources, baseline.
- **`dos4-enhancements`** — built on top of `main`. Real source-code modifications: bug fixes, `/?` help additions, DOS-side fixes that should be candidate-shape for upstreaming. **No WASM/MASM-divergence accommodations here.** Stays MASM-buildable.
- **`watcom-migration`** — built on top of `dos4-enhancements`. The OLD Open-Watcom-WASM migration edits. **Effectively superseded** by the jwasm path (Jun 2026). Do NOT commit new work here.
- **`jwasm-migration`** — the CURRENT active branch for the JWasm migration. Branched off `dos4-enhancements`, parallel to `watcom-migration` (they have diverged: ~80 vs ~101 unique commits as of Jun 2026). ALL jwasm source fixes go here.

**CRITICAL (learned Jun 13 2026 — cost a wrong-branch build):** the superproject is on branch `jwasm-migration`, and its MS-DOS submodule gitlink must point at the submodule's **`jwasm-migration`** tip, with `MS-DOS/` checked out on `jwasm-migration`. The build (`Makefile SRC := MS-DOS/v4.0/src`) ALWAYS reads from `MS-DOS/`, so if it's on the wrong branch the whole tree is wrong source.

Two traps that actually happened:
1. The jwasm source lived only in a separate worktree (`../msdos-jwasm` on `jwasm-migration`) while `MS-DOS/` sat on `watcom-migration`. A full `make` then built WASM-era source with the jwasm assembler and died immediately (FORMAT Sublist A2164). Fix was to remove the worktree and `git -C MS-DOS checkout jwasm-migration`.
2. Several superproject "Bump MS-DOS submodule" commits were MISLABELED: their messages described jwasm work but the gitlink was frozen at `watcom-migration` commits (8ba76f7d / 125b0d0d). Verify a bump actually moved the pointer: `git ls-tree HEAD MS-DOS` and confirm that commit is on `jwasm-migration` (`git -C MS-DOS merge-base --is-ancestor <sha> jwasm-migration`).

**How to apply:**
- Before committing in the MS-DOS submodule, check `git -C MS-DOS branch --show-current`. For migration work it must be `jwasm-migration` (NOT `watcom-migration`, NOT `dos4-enhancements`).
- Non-migration bug fixes still go on `dos4-enhancements`.
- After bumping the superproject, confirm the gitlink lands on a `jwasm-migration` commit, not a stale watcom one.
- See [[wasm-source-fix-patterns]] for the jwasm `-Zm` source fixes themselves.
