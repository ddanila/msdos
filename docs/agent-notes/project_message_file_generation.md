---
name: msdos-message-file-generation
description: "How MS-DOS .CTL/.CL* message files are generated (BUILDMSG/BUILDIDX/NOSRVBLD via kvikdos); the .CTL 'cannot open' failures across jwasm sweeps are this make-flow step, not source bugs."
metadata: 
  node_type: memory
  type: project
  originSessionId: 75a4ec5d-2e90-4df4-a646-46b051dcfb8d
---

The `.CTL` / `.CL*` "Cannot open file" errors that appear in EVERY jwasm
subsystem sweep (DOS DOSMES, BIOS MSBIO2/SYSIMES/SYSINIT1/MSLOAD, CHKDSK
CHKDISP, FORMAT DISPLAY/MSFOR, etc.) are a single **already-tooled make-flow
step**, not source bugs and not jwasm-migration work. A standalone file sweep
just doesn't run the message compiler.

Generation (recipes in `v4.0/src/TOOLS/TOOLS.INI`):
- `.msg.idx`:  `buildidx $*.msg`                        -> `bin/buildidx`
- `.skl.ctl`:  `buildmsg $(msg)\$(COUNTRY) $*.skl`      -> `bin/buildmsg`
- `.skl.cl1`:  `nosrvbld $*.skl $(msg)\$(COUNTRY).msg`  -> `bin/nosrvbld`

`$(msg)` = `..\..\MESSAGES`, `$(COUNTRY)` = `usa-ms`. The tools are DOS exes
(`TOOLS/BUILDIDX.EXE`/`BUILDMSG.EXE`/`NOSRVBLD.EXE`) run through `bin/dos-run`
-> `kvikdos` (or `kvikdos-soft`, the software-CPU build, when `/dev/kvm` is
absent -- so it runs on **macOS**). Inputs: checked-in per-utility `*.skl`
plus `v4.0/src/MESSAGES/USA-MS.MSG` (and `USA-MS.IDX`, itself built by
buildidx). `bin/dos-run` mounts the **in-place `MS-DOS` submodule checkout**
as C: (not the `../msdos-jwasm` worktree) and derives the DOS cwd from the
Linux subdir.

Verified Jun 5 2026 on macOS: `bin/buildidx USA-MS.MSG` (idx already current)
+ `bin/buildmsg '..\..\MESSAGES\usa-ms' FORMAT.SKL` from `CMD/FORMAT/` produced
FORMAT.CTL + FORMAT.CL1/CL2/CLA/CLB/CLC. The generated `.ctl`/`.cl*` are
**gitignored build artifacts -- never commit them**.

Consequence for the migration: every subsystem reported "source-clean except
the .CTL/.CL files" is fully source-clean once this step runs. BUT generating
the `.CTL` UNMASKS the next real source blocker -- e.g. FORMAT/DISPLAY.ASM
then hits `FORMSG.INC(859): A2164 No segment information to create fixup:
Sublist`.

**Sublist A2164 root cause (diagnosed Jun 5 2026, deep SHARED blocker):**
FORMSG.INC sets `Sublist = No_Replace` (=0, absolute) or `Sublist =
Sublist_msgXxx` (relocatable label), then `Create_Msg` emits `dw Sublist`.
jwasm locks a redefinable `=` symbol's type on first assignment; a symbol
assigned BOTH absolute (0) and relocatable (label) values across reassignments
can't be made into a fixup -> A2164 at `data ends`. Order-independent;
`offset` doesn't help; all-absolute or all-relocatable both assemble, only the
MIX fails (MASM 5.10 allowed it). Minimal repro: `X=0` then `X=<label>`, each
followed by `dw X` in a macro, inside one segment. Fix is NOT small: No_Replace
must stay 0 (runtime check), and the `Sublist`/`Create_Msg` pattern is shared
across many utilities. Best options: a jwasm-engine fix (let `=` switch
absolute<->relocatable like MASM), or restructure Create_Msg to emit a literal
`dw 0` for the no-replace case. Deferred -- needs a design decision.

**DEFINITIVE (Jun 6 2026, via a jwasm `-Fl` listing of the real FORMSG):**
the `=` absolute/relocatable MIX is confirmed the cause; my "external-offset"
revision above was wrong (plain `dw offset <extern>` and `dw <segment>` both
assemble fine in isolation). The listing shows: `Sublist` is typed **Number**
(final value 0, from the many `Sublist = No_Replace` assignments), yet the
Create_Msg expansions do `dw Sublist` while Sublist holds a DATA-label offset
(e.g. `dw Sublist` emits `9A00` = offset of Sublist_MsgVerify). jwasm wants a
segment-relative fixup for those reloc-valued `dw Sublist`, but the symbol's
segment was lost through the absolute(0)/relocatable(label) mixing -> A2164.
Tried and RULED OUT (all three): IFE-conditional emission (`IFE Parm4/dw 0/
ELSE/dw Parm4`) -- count unchanged, reloc cases still `dw Sublist`; `Sublist =
OFFSET <label>` -- still segment-relative, still A2164; and `dw Parm4 AND
0FFFFh` -- A2065 "Constant expected" (can't AND a relocatable). No macro-
expression coercion of the `=` symbol works. A plain
`X = <label>; dw X` (no 0 mixing) works; only the 0+label MIX breaks it.
Real fix: a jwasm-engine change (let `=` carry a relocatable's segment, or
allow the fixup), OR restructure Define_Msg/Create_Msg to pass the sublist
LABEL directly to a `dw <label>` (bypassing the reused `=` symbol). NOTE the
broader "deep set" (max_pknum/switch_count/XMAEM-RAMDRIVE long-jumps) is a
SEPARATE root (external `$-OFFSET`/displacement), NOT this one.

**FIXED (Jun 6 2026) -- the simple source fix is a TEXT EQUATE.** Change the
per-message `Sublist = X` (numeric `=`) to `Sublist EQU <X>` (text equate).
Then `dw Sublist` text-substitutes to `dw Sublist_msgXxx` (a DIRECT label ref
-> proper fixup) or `dw No_Replace` -> `dw 0` -- the relocatable label never
passes through a numeric `=` symbol, so no lost-segment fixup. Done for FORMAT
(FORMSG.INC, 61 assignments): DISPLAY.ASM now FULLY assembles with the
generated FORMAT.CTL. Watch for label names containing `?`/`@`/`$` (MASM-legal,
e.g. `Sublist_msgWhatIsVolumeId?`) -- keep the whole name inside `< >`. The
same one-line-per-assignment conversion applies to the other Sublist message
files (MODE/MODEMES, etc.). So Sublist is NO LONGER a deep blocker -- it's a
mechanical source edit. Only the external-`$-OFFSET` class remains deep.

See [[wasm-source-fix-patterns]] for the per-construct jwasm source fixes, and
[[wasm-migration-end-state-no-preprocessor]] for the overall goal.
