# Project context for Claude (MS-DOS 4.0 open-source toolchain migration)

This file replaces Claude's per-repo auto-memory. Keep durable project notes
HERE (and in `docs/agent-notes/`), not in `~/.claude` memory. When you learn
something worth persisting for this repo, edit this file or a file under
`docs/agent-notes/` -- do not write it to Claude memory.

## What this project is

Replacing the proprietary MS-DOS 4.0 build tools (run under kvikdos) with a
native open-source toolchain. Status (2026-08-26):

- **Assembler = DONE.** The pinned custom JWasm (`bin/jwasm-masm`, `-Zm` MASM
  5.1 mode) assembles all `.ASM` with 0 errors. `jwasm/build.sh` provisions the
  exact fork revision; clean `-j1`, `-j4`, and `-j8` builds and the full QEMU
  boot stack pass.
- **Linker = DONE for pure-asm.** `bin/wlink` (Open Watcom wlink wrapper) links
  the pure-assembly targets and is byte-identical to MS LINK. The SELECT wlink
  SIGSEGV is fixed (`.ALPHA`->`.SEQ`); RESTORE is triaged (C-runtime dep).
- **Stage B (wcc port of the ~30 C-hybrid utilities) = DEFERRED.** Builds+links
  clean and `/?` works, but ATTRIB's core path still hangs in the SAL
  message-substitution layer. It's a deep, multi-layered per-utility effort;
  poor ROI. Pure-asm (jwasm+wlink) is the shippable milestone; C-hybrids stay
  on MS CL/LINK for now.
- Still proprietary: MS CL/LIB/EXE2BIN + MS LINK for C-hybrids, and the 7
  kvikdos-run build utilities (BUILDMSG, NOSRVBLD, EXE2BIN, CONVERT, BUILDIDX,
  DBOF, MENUBLD) -- a separate future effort.

Detailed running log: `TODO.md`. Deep notes: `docs/agent-notes/`.

## Working conventions (follow these)

- **Branch policy (MS-DOS submodule).** Four long-lived branches: `main`
  (original MS sources), `dos4-enhancements` (non-migration bug fixes,
  MASM-buildable), `watcom-migration` (OLD WASM path, superseded -- do NOT
  commit here), `jwasm-migration` (CURRENT -- ALL jwasm source fixes go here).
  The superproject is on `jwasm-migration` and its `MS-DOS/` gitlink must point
  at the submodule's `jwasm-migration` tip. Before committing in the submodule,
  check `git -C MS-DOS branch --show-current`. After a superproject submodule
  bump, confirm the gitlink lands on a `jwasm-migration` commit. Do not push to
  `master`/`main`. See `docs/agent-notes/feedback_msdos_branch_policy.md`.
- **CP437 byte-preserving edits.** MS-DOS sources contain CP437 high-bit bytes
  (box-drawing glyphs in banner comments). The UTF-8 Edit/Write tools re-encode
  every high-bit byte and corrupt the file. Edit MS-DOS sources byte-preserving
  via Python latin-1:
  `s=open(p,encoding='latin-1').read(); ...; open(p,'w',encoding='latin-1').write(s)`
  (compute the new content BEFORE opening for write -- opening `'wb'`/`'w'`
  truncates immediately). Verify with `git diff --stat`; unrelated comment-line
  churn means encoding corruption -- restore from git and redo via latin-1.
- **ASCII only.** No unicode ellipsis `...` (use three dots) or em-dash (use
  `--`/`-`) in code, comments, commit messages, or PR text.
- **Build log discipline.** Run the build once to a log
  (`make -k ... 2>&1 | tee /tmp/build.log`), then grep/sed/awk that log. Do not
  re-run a full build just to grep differently. Logs contain binary OMF bytes,
  so grep needs `-a`.
- **jwasm make invocation.** Plain `make` is the production JWasm build. Run
  `./jwasm/build.sh` once when the ignored host binary is absent.
- **Include depth.** With `bin/jwasm-masm`, `-I` depth must match the file's
  dir depth under `v4.0/src` or `STRUC.INC` won't resolve and you get a flood of
  bogus A2199 control-flow errors. depth-1 (`BIOS`,`DOS`): `-I. -I..\INC
  -I..\HINC`; depth-2 (`DEV/<drv>`,`CMD/<util>`): `-I. -I..\..\INC -I..\..\HINC`;
  depth-3 (`DEV/DISPLAY/EGA|LCD`,`DEV/PRINTER/<model>`): `-I..\..\..\INC`.
- **Build metrics.** Total error count is NOT a reliable progress metric (fixing
  a crash can raise it as files now run to completion). Track clean-file count,
  segfault count, and failed-target count together; compare the same assembler
  version.
- **Prefer toolchain fix.** Classify each build error: (a) genuine assembler bug
  -> propose a fix to the tool; (b) tool-stricter-than-MASM (correct rejection)
  -> a source edit is fine. When unsure, surface the analysis and recommend; do
  not silently apply source workarounds.
- **Tool forks.** File toolchain bugs/PRs against the user's forks
  (`github.com/ddanila/open-watcom-v2`, `github.com/ddanila/kvikdos`), never
  upstream. Vendored binaries under `watcom/bin/` are upstream snapshots.

## docs/agent-notes/ index

Migrated from Claude memory (2026-06-18). Some `project_wasm_*` /
`project_struc_inc_*` notes describe the superseded WASM path and are historical
-- jwasm cleared those blockers; trust `TODO.md` and `project_jwasm_*` /
`project_toolchain_migration.md` for current reality.

- `project_toolchain_migration.md` -- toolchain status, SELECT fix, RESTORE
  triage, Stage B / ATTRIB deep-debug findings (most current).
- `project_jwasm_deep_set.md`, `project_jwasm_make_invocation.md` -- jwasm path.
- `project_message_file_generation.md` -- `.CTL`/`.CL*` make-flow step.
- `project_no_preprocessor_endstate.md` -- goal of retiring the preprocessor.
- `project_wasm_blockers.md`, `project_wasm_source_patterns.md`,
  `project_struc_inc_investigation.md` -- historical WASM-era detail.
- `feedback_*.md` -- the conventions above, in full.
