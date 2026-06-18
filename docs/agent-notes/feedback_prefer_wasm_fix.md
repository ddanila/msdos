---
name: Prefer fixing WASM over source workarounds
description: When a build error looks like a WASM bug, propose an upstream/fork fix first; do source workarounds only after the user decides it's not worth it
type: feedback
originSessionId: 0cdbc900-a2ce-42fb-b7e4-c361a32f1de6
---
When the WASM build hits an error, **first check whether the error is a WASM bug** (genuine assembler bug, not a stricter-but-correct MASM-compat divergence). If it is, propose a fix to WASM itself (file in `ddanila/open-watcom-v2`, or upstream `open-watcom/open-watcom-v2`) and let the user decide if it's worth it. Only do source-side workarounds in the MS-DOS submodule after the user decides against the WASM fix.

**Why:** User prefers root-cause fixes over patching MS-DOS to dodge WASM bugs. The MS-DOS sources should look as much like the original Microsoft code as possible; the toolchain is the place to make accommodations.

**How to apply:**
- For each new build error, classify: (a) WASM bug — wrong/broken behavior in the assembler; (b) WASM-stricter-than-MASM — correct rejection of code MASM happened to accept. (a) → propose WASM fix; (b) → source edit is fine.
- When unsure, present the analysis to the user with a recommendation and ask.
- Don't silently apply workarounds. Even when I think source edit is small, surface it.
