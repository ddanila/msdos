---
name: feedback_dev_sweep_include_depth
description: Correct jwasm include-flag depth per source subdir; wrong depth fakes a flood of A2199 control-flow errors by hiding STRUC.INC
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 75a4ec5d-2e90-4df4-a646-46b051dcfb8d
---

When sweeping a file with `bin/jwasm-masm`, the `-I` depth MUST match the
file's directory depth under `v4.0/src`, or includes silently fail to resolve.

- `src/BIOS`, `src/DOS` (depth 1): `-I. -I..\INC -I..\HINC`
- `src/DEV/<drv>`, `src/CMD/<util>` (depth 2): `-I. -I..\..\INC -I..\..\HINC`
- `src/DEV/DISPLAY/EGA|LCD`, `src/DEV/PRINTER/<model>` (depth 3): `-I..\..\..\INC`

**Why it matters:** if the depth is too deep, `STRUC.INC` (and the other shared
INCs) aren't found, so the custom `.IF`/`.WHILE`/`.REPEAT` structured-programming
MACROS never load. jwasm `-Zm` then parses bare `.IF` with its OWN built-in HLL
directive engine and emits a flood of bogus **A2199 "Syntax error in
control-flow directive."** Those A2199s are an artifact of the wrong flags, NOT
a real jwasm/MASM structured-directive incompatibility -- they all vanish at the
correct depth. (Discovered Jun 11 2026: a wrong depth-3 sweep made ANSI/DISPLAY/
PRINTER look badly broken; at the right depth-2 they are source-clean.)

**How to apply:** before declaring a subsystem "not migrated," confirm the
`-I` depth is right and filter the message-file noise (`A2106` on `.CTL`/`.CL*`
and the `$M_NUM_CLS` `A2102` cascade -- see [[msdos-message-file-generation]]).
RAMDRIVE/XMAEM can pass with WRONG depth because they include local copies via
`-I.`; that masks the depth error for those two only. See
[[wasm-source-fix-patterns]] for the real per-construct fixes.
