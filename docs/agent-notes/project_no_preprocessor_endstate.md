---
name: wasm-migration-end-state-no-preprocessor
description: End-state goal for the OpenWatcom migration -- retire bin/preprocess-wasm entirely. Update cadence -- whenever preprocessor edits are proposed.
metadata: 
  node_type: memory
  type: project
  originSessionId: 45f64af6-6163-4c5e-9add-1e611b08b310
---

## Goal

The OpenWatcom migration should end with **no `bin/preprocess-wasm`** at
all. Two paths to get there, in preferred order:

1. **wasm <-> masm parity upstream.** When a preprocessor pass exists
   solely to compensate for a wasm/masm behavioral difference, the
   long-term fix is to file the bug against
   [[feedback_openwatcom_fork]], land it, and then retire the
   preprocessor pass. Concrete example currently outstanding: macro
   parameter substitution doesn't whitespace-split args in MASM mode
   (drives `bin/preprocess-wasm` _comma_sep_struc_args).

2. **MS-DOS source edits on `watcom-migration`.** When the upstream
   parity gap is contentious or the pattern is uniquely Microsoft-MASM,
   bake the equivalent transform into the source files. The
   [[feedback_msdos_branch_policy]] branch already accumulates these
   edits; the only reason a preprocessor pass should stay long-term is
   if neither (1) nor (2) is feasible.

## How to apply

When extending or fixing `bin/preprocess-wasm`:

* Treat any preprocessor edit as a **temporary** intermediate state.
  Acceptable as a stepping stone, but every pass added should have a
  paired plan for retirement -- either an upstream bug filed against
  the fork or a direct source-edit campaign tracked in TODO.md.
* When a preprocessor pass turns out to be buggy (e.g. produces
  blank macro args), prefer fixing the bug rather than removing the
  pass outright -- removing it now would block the build until the
  paired upstream/source fix lands.
* When the underlying upstream parity fix ships in a vendored Current-
  build, retire the corresponding preprocessor pass in the same
  commit/PR that bumps the binaries -- so the dependency is obvious in
  history.
* When _adding_ a new preprocessor pass becomes tempting, ask first
  whether a direct source edit on `watcom-migration` would be cleaner.
  Direct edits show up in `git log` / `git blame` and don't require
  reasoning about shadow-directory magic at debug time. The TODO.md
  "Source editing policy: direct edits over preprocessor passes"
  section captures the same principle from the other direction.
