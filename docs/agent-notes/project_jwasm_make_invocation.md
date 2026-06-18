---
name: project_jwasm_make_invocation
description: "how to build the tree through jwasm — Makefile defaults to wasm-masm, must override MASM"
metadata: 
  node_type: memory
  type: project
  originSessionId: bfcfc6fa-bc8b-44db-8a6c-ff0b70b3968b
---

The top `Makefile` hardcodes `MASM := $(BIN)/wasm-masm` (Open Watcom WASM, emits **E-codes** like E032/E065). The active jwasm-migration work targets `bin/jwasm-masm` (JWasm `-Zm`, emits **A2xxx codes**). The Makefile is NOT wired to jwasm.

To measure real jwasm-migration progress / the "N/24 failing targets" universe, drive make with a command-line override (command-line vars override `:=`):

`make -k MASM="$PWD/bin/jwasm-masm" all > build_jwasm_<date>.log 2>&1`

A plain `make all` builds the Open Watcom tree instead and produces a much larger, stale E-code failure flood that is NOT a regression — it just measures the wrong assembler. The "12/24 cleared" triage commits were jwasm sweeps, not `make all` runs.

Build logs contain binary OMF bytes, so grep needs `-a`. See [[feedback_build_log]] and [[feedback_build_metrics]]. Assembler wrappers each run a preprocessor: `wasm-masm`->`preprocess-wasm` (heavy), `jwasm-masm`->`preprocess-jwasm` (minimal, comma-sep only). End goal is retiring both: [[project_no_preprocessor_endstate]].
