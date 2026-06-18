---
name: wasm-migration-remaining-blockers
description: "Upstream WASM bugs blocking the remaining build failures, with what was tried and why it failed. Update cadence after each binary update or upstream fix."
metadata: 
  node_type: memory
  type: project
  originSessionId: 45f64af6-6163-4c5e-9add-1e611b08b310
---

## WASM Migration Status (May 28 2026 snapshot)

Binary: upstream Current-build May 13 2026, vendored at `watcom/bin/`.
Now includes upstream PRs #1614, #1615, **#1617** (IFDEF-name macro
SIGSEGV), **#1618** (struct label init), **#1621** (trailing-comma line
joining outside WATCOM mode), and **#1622** (TC_STRING macro
substitution drops quote delimiters).

**Build state after the May 28 source-side grind (~50 commits):**
- Failed make targets: 157 -> **52** (-67%)
- ASM files with errors: 103 -> **19** (-82%)
- Of the 19 remaining, **16 are STRUC.INC `&` substitution blocked**
  (single upstream bug -- see "Open WASM bugs" section #1 below).
- 3 source-fixable still open: DEV/DISPLAY/DISPLAY.ASM (FTBLK STRUC
  recursive-SIZE in own body), GSHARE.ASM (DOSAssume Table SEGMENT/
  ends inside macro body), GSHARE2.ASM (IF/ENDIF block nesting).

Source-only ceiling effectively hit. The single biggest remaining lever
is the STRUC.INC `&` substitution upstream WASM fix -- it would cascade
~16 files clean.

`inc` subsystem: builds **fully clean serially**. Parallel `-j4` runs
show 4 transient INC failures (CDS/ERRTST/SYSVAR/DPB) -- these are
kvikdos CL.EXE intermediate-file collisions on the `INIT` path, not
wasm regressions.

Other subsystems (mapper, boot, bios, dos, cmd, dev, select, memm) still
have not been swept since the May 7 binary + source-fix round. May 13
full-tree parallel build: 97 ASM files with non-zero wasm errors, 167
make targets failed.

## Dominant remaining wasm E-codes (May 13 build)

| E-code | Count | Likely cause |
|--------|------:|--------------|
| E032   | 296   | STRUC.INC `&` substitution (unfiled) |
| E230   | 61    | (mixed; needs triage) |
| E050   | 59    | Offset-size mismatches |
| E225   | 52    | (mixed) |
| E066   | 50    | (mixed) |
| E236   | 38    | Forward-ref macro -- some may be STRUC.INC family |
| E040   | 35    | Operand size |
| E020   | 22    | mostly SELECT/`MACROS.INC:327`, not the old IRP/single-quote case |

Subsystem failure counts: SELECT 31, MEMM/MEMM 20, CMD/FDISK 18,
CMD/MODE 13, CMD/RESTORE 12, DEV/XMAEM 8, CMD/GRAPHICS 7, MEMM/EMM 5,
CMD/KEYB 5, CMD/FC 5, INC 4 (kvikdos, not wasm), DEV/ANSI 4,
CMD/IFSFUNC 4, then single-digit tail.

**Update Jun 4 2026:** DEV/XMAEM now builds **fully clean** (0 errors,
all 11 makefile objects + INDEMSUS/INDEMAUS verified individually via
`bin/wasm-masm -I. -I..\..\INC -I..\..\H`). Cleared by the INDEINS.MAC
`.XLIST`/`.LIST` source fix (`.MAC` is not a preprocessed extension)
plus earlier RECORD-comment / TYPE->SIZE edits. The committed `.err`
files in that dir are stale pre-fix artifacts. Also fixed this session:
CMD/EXE2BIN/LOCMES.ASM (`addr` macro -> `set_addr`, 10 E094 -> 0); its
companion LOCATE.ASM still has ~18 E032 (STRUC.INC `&`, upstream).
Validation method that works well per-file: `bin/wasm-masm` directly
with the subsystem makefile's `inc`/`hinc` include dirs.

**Orphaned old-version files (Jun 4):** probing *all* `.ASM` files
surfaces superseded files that are NOT makefile targets and NOT included
anywhere -- e.g. DEV/PRINTER has CPSPI.ASM (live: CPSPI07.ASM),
PARSE4E.ASM (live: PARSER.ASM), CPSFONT.ASM (live: CPSFONT3.ASM),
PTRMSG.ASM; also CMD/EXE2BIN/LOCMES+LOCATE (separate LOCATE tool, not in
EXE2BIN.LNK), XMAEM/INDEMSUS.ASM (live: INDEMSG). Some never assembled
even in MASM (e.g. CPSPI.ASM's HWCP_1 label shadows a CPSPEQU.INC DW
var). Cross-check `MAKEFILE`/`*.LNK` before investing: real targets are
higher value. All 5 real DEV/PRINTER targets build clean; PRINTER,
XMAEM, MAPPER, and MEMM/MEMM real targets are now clean. Remaining real-
target failures (SELECT/MODE/GRAPHICS/KEYB/FDISK) are STRUC.INC `&`
(E032, upstream) -- the source-fixable real-target surface is largely
exhausted.

Core OS still boots (QEMU validated under earlier binaries; not
re-validated against May 13).

## Open WASM bugs

### 0. Macro arg substitution doesn't split on whitespace in MASM mode (FILED)

Fork PR https://github.com/ddanila/open-watcom-v2/pull/24 opened May 13 2026
with minimal repro at `bld/wasmtest/devel/macargws.asm`. In `-zcm=masm`
mode, wasm keeps a substituted macro arg as a single positional token
where MASM 5.10 and TASM 4.1 both re-tokenise on whitespace. This is the
underlying parity gap that `bin/preprocess-wasm`'s
`_comma_sep_struc_args` pass exists to compensate for. Once #24 lands,
that preprocessor pass can retire (see [[project_no_preprocessor_endstate]]).

### 1. STRUC.INC `&` parameter substitution (DOMINANT REMAINING; not filed)

STRUC.INC is a structured-programming macro library (`.IF`/`.WHILE`/
`.REPEAT`) used across SELECT, MODE, GRAPHICS, KEYBOARD, ANSI, DISPLAY,
PRINTER. The macros rely on MASM `&` concatenation in macro bodies
(`$ll&n`, `j&c`, etc.). WASM errors E074/E065/E032 on these expressions
during macro expansion. `$BuildJump` already pre-expanded by the
preprocessor. Remaining `&` issues are pervasive in `$Label`,
`$CondJump`, `$CondJump2`, `$Poke`, `$Peek`, `$Push`, `$Pop`, `$Test`,
`$TopTest`. **This is now the largest remaining blocker** -- ~296 E032
hits and a chunk of the E236s land here.

Next step is to package a minimal repro and file against the fork
([[feedback_openwatcom_fork]]). Source-side workaround (pre-expand `&`
the way `$BuildJump` is) is feasible but pervasive; prefer upstream fix.

**Jun 4 BREAKTHROUGH (corrects the central assumption).** The CMD/MODE
E032s were NOT STRUC.INC `&` substitution -- they were `.FOR` macro args
reaching WASM **space-separated**. The preprocessor's `_comma_sep_struc_args`
pass (STRUC_MACRO_PAT) covers IF/ELSEIF/WHILE/UNTIL/WHEN/LEAVE but **omits
FOR**, so `.FOR idx = start TO stop` arrives as one giant comma-arg, mis-
expands, corrupts `.for`'s macro-stack ($st), and CASCADES E032/E074 into
EVERY subsequent `.IF`/`.NEXT` in the file. Fix = explicit commas at the
~6 `.FOR` call sites (`.FOR idx,=,start,TO,stop[,STEP,n]`; MASM-compatible).
**Result: the entire CMD/MODE subsystem (16 files) now assembles 0 errors**
(commit "comma-separate .FOR macro args"). `.IF`/`.WHILE`/`.REPEAT` were
never broken (verified in isolation). NEXT: re-check the other "&-blocked"
subsystems (SELECT/GRAPHICS/KEYB/ANSI/DISPLAY/PRINTER) -- their E032s may
ALSO be `.FOR`/uncovered-comma cascades, not the engine bug, meaning much
of the ~296 E032 may be comma-fixable in source without the upstream `&`
fix. (Edit DOS sources byte-preserving/latin-1 -- see [[cp437-byte-preserving-edits]].)

**GRAPHICS classified (Jun 4).** CMD/GRAPHICS is mostly clean already
(stale May-13 counts); only GRCOLPRT.ASM (2) + GRLOAD2.ASM (5) fail, both
on STRUC.INC `j&c $l&l` ($CondJump2 ~L254) and `loop&c $l&l` ($CondLoop
~L328) -- these use `.LOOP`. Distinct from .FOR: this is the GENUINE `&`
bug. Isolation test (`cj macro c / j&c l`) FAILS E235 'Procedure must have
a name' + E065 + internal error, whereas variable-name concat `$st&n`
WORKS. So WASM's `&` bug is specifically MNEMONIC concatenation (`j`+cc ->
`je`/`jne`, `loop`+cc), exactly why `$BuildJump` is pre-expanded. The fix:
rewrite `$CondJump`/`$CondJump2`/`$CondLoop` to DISPATCH on the condition
(ifidn/irp -> emit explicit `je`/`jne`/`loope`/... ) instead of `j&c`/
`jn&c`/`loop&c` concatenation. Bounded to ~3 macros; should clear GRAPHICS
and any subsystem using `.LOOP`/conditional jumps via these macros. That
is the next source task.

**Jun 4 update -- crucial nuance + partial fix.** `&` concatenation in
WASM masm-mode WORKS when it forms a MACRO CALL (`j&c`->`jeq`, a
`$BuildJump` alias -> assembles) but FAILS when it forms an INSTRUCTION
mnemonic (`loop&c`->`loop`/`loope`, `j&c`->`je`) -> E235/E065/internal
error. So `$CondJump2`'s `j&c`/`jn&c` are FINE (they call `$BuildJump`
macro aliases -- which is why `.IF`/`.WHILE`/`.UNTIL` all assemble clean).
Only `$CondLoop`'s `loop&c` (real LOOP instruction) was broken. FIXED:
`$CondLoop` now emits `loop $l&l` directly (commit "emit explicit LOOP").
`$l&l` operand is variable-name concat (fine). No conditional `.LOOP`
exists in the tree, so plain `loop` covers all usage. No regression.
**Remaining .LOOP blocker:** a SEPARATE pre-existing E206 'block nesting'
in the `.loop` macro body (STRUC.INC ~648/650 at `.loop`'s `endm`);
persists even with `$CondLoop`=nop, so it's NOT the loop emission. `.until`
uses the same `$Pop`/`exitm`/`$Label` patterns and works, so the diff is
subtle. Only GRCOLPRT.ASM + GRLOAD2.ASM use `.REPEAT/.LOOP` and stay
blocked on this E206. Next: bisect `.loop` body (the `if $Temp ne
$RepeatType/exitm` vs `if $LeaveFound/$Label` blocks) to find the E206.

**Jun 4 -- subsystem landscape re-probed + remaining STRUC.INC issues
mapped.** After the .FOR + $CondLoop fixes, the assumed-"&-blocked"
subsystems are MOSTLY CLEAN now (May-13 counts were stale). Per-real-
target residue: DEV/ANSI {ANSI.ASM,IOCTL.ASM ~2 each}, CMD/KEYB
{PARSER.ASM 1}, DEV/DISPLAY {DISPMES.ASM 1 -- ORPHAN, missing DISPMES.INC,
skip}, DEV/PRINTER {PTRMSG.ASM 1 -- orphan}, plus CMD/GRAPHICS
{GRCOLPRT,GRLOAD2 -- the .loop E206}. The remaining REAL blockers are
three DEEP STRUC.INC behaviors, each needing focused (not loop-sized)
work:
  1. **.loop E206** (GRCOLPRT/GRLOAD2): block-nesting in `.loop` body;
     not loop&c (persists with $CondLoop=nop); `.until` uses same patterns
     yet works. Bisect: removing 1st if-block keeps E206; removing 2nd
     (`if $LeaveFound/$Label`) flips it to a stack E032. Subtle.
  2. **AND/OR conjunctions** (DEV/ANSI root): `.IF cond AND` / `.IF cond2`
     two-line conjunction (ANSI 617-618 `.IF NZ AND` then `.IF <..EQ..>`)
     hits $StrucError(33) and CASCADES into later `.IF`s (931 etc. fail
     downstream, exactly like MODE's post-.FOR cascade). The conjunction
     machinery ($GetConj/$TopTest/$AndOr) misbehaves under WASM. Isolated
     `.IF`/`.IF<a EQ b>`/`.IF NZ` all work; only the AND/OR conjunction
     breaks. ROOT (Jun 4): `$GetConj` fails to detect the `AND` -> leaves
     `$AndOr=$NoConj` -> `$TopTest` takes the wrong branch -> `$Test` gets
     mis-parsed args -> `cmp a1,a3` E040. `$GetConj` uses nested `irp` +
     `ifnb <&parm>` + `ifidni`-style `ifidn <parm>,<x>` + `$&x` (`$`+x
     `&`-concat). Some part of that nested-irp/`&parm`-substitution chain
     misbehaves under WASM. This is macro-ENGINE behavior, likely the same
     family as the filed upstream whitespace/substitution bug (#24) -- a
     source workaround would mean rewriting `$GetConj` to avoid `&parm`/
     nested-irp, which is delicate.
  3. **E043 jump-out-of-range** (CMD/KEYB/PARSER): STRUC.INC emits a
     short jump that overflows; $Dist short/near logic. Documented widen-
     pattern, but inside STRUC.INC's generated jumps.
KEY `&` rule (confirmed): `&` works to form a MACRO CALL (j&c->jeq alias)
but NOT an instruction mnemonic. So `.IF`/`.WHILE` with STRUC condition
NAMES (EQ/NEQ/LT/GT/ZERO/NONZERO -> have jeq/jneq/... aliases) assemble
fine; the failures are the conjunction path (#2), `.loop` (#1), and
jump-range (#3) -- NOT plain j&c. These are focused-project work, poorly
suited to the per-iteration loop.

**CONCLUSION (Jun 4, after 3 deep iterations).** All three remaining
STRUC.INC blockers are UPSTREAM WASM MACRO-ENGINE bugs, not cleanly
source-fixable constructs:
 - conjunction `$GetConj`: nested `irp` + `ifnb <&parm>` + `exitm` breaks
   WASM's parser (isolated test: the inner irp/ifnb block fails to close,
   E249/E065). Confirmed engine-level.
 - `.loop` E206: block-nesting miscount in nested macro expansion.
 - `j&c`/`loop&c`: `&` can't form instruction mnemonics (loop&c FIXED via
   explicit `loop`; j&c is fine as it forms macro-alias calls).
Source workarounds would require REIMPLEMENTING STRUC.INC's macro-stack/
conjunction/loop machinery (nested-irp + `&`-substitution + exitm are
fundamental to its design) -- very high effort + regression risk across
~the few remaining files (ANSI x2, GRAPHICS x2, KEYB x1). This VINDICATES
the original [[feedback_prefer_wasm_fix]] recommendation: the STRUC.INC
family needs the upstream WASM fix (file repros against
[[feedback_openwatcom_fork]], same family as #24), not source rewrites.
The big source wins were the NON-engine issues: `.FOR` comma cascade
(cleared all of CMD/MODE) and the per-file fixes. Those are exhausted;
what's left is genuinely upstream.

**Earlier Jun 4 deep-dive (superseded by the above).** Minimal repro: a file that `INCLUDE`s
the real STRUC.INC and uses `.FOR BX = a TO b ... .NEXT` -> 3 errors
(STRUC.INC E032 at `$st = $st+1` in $Push, E032 at `$Dist = $DefDist`
in $for, E040 at `inc index` in $next). KEY: the errors are reported on
**trivial non-`&` lines** -- WASM misattributes them. Every individual
construct works in isolation under `-zcm=masm`: `$st&n` concat,
`%$st`+`&`, `if1`+`$ll&n`/`$l&n:` label-concat all assemble 0 errors on
their own. The failure only appears at the FULL nested-macro-stack
expansion depth (`.FOR`->$Push/$Poke/$Peek/$Label/$CondJump pushing/
popping $st0..$stN via `&`+`%`+`if1`). => This is a WASM macro-ENGINE
state bug, NOT a fixable source construct. A source-only workaround
would require fundamentally reimplementing STRUC.INC's macro-stack
machinery (771 lines, ~16 dependent files: SELECT/MODE/GRAPHICS/KEYB/
ANSI/DISPLAY/PRINTER) -- a major rewrite, not an incremental fix, with
high regression risk. Confirms "prefer upstream fix". Repro recipe saved
for whoever files it against the fork.

### 2. Preprocessor BREAK-strip leaves dangling PURGE (latent)

`bin/preprocess-wasm` strips `BREAK MACRO ... ENDM` blocks. Any
`PURGE BREAK` we emit in an include-guard block then references a
never-defined macro -> E251. Not currently exercised.

## kvikdos bugs

### Open: CL.EXE intermediate-file collisions under parallel make

INC subsystem failures in `make -j4`: four `INC/*.C` files (CDS, ERRTST,
SYSVAR, DPB) report "fatal error C1042: cannot open compiler
intermediate file". Almost certainly CL.EXE temp filenames on the `INIT`
path colliding across concurrent kvikdos invocations. Serial build is
clean. Likely a kvikdos temp-path isolation issue; not yet repro'd in
isolation. File against fork ([[feedback_openwatcom_fork]]) once
isolated.

### Fixed May 7 2026: inplace_realloc Z-tail corruption

DOS INT 21h/AH=4Ah growing a block whose successor is the trailing
Z-type free block wrote a fake M-type next-MCB and a psize past the end
of the arena, fatal-tripping later validation as `bad next/free MCB
after inplace_realloc(): 10`. Hit by CL.EXE compiling INC/*.C
(ERRTST/SYSVAR/CDS/DPB). Fixed in fork submodule `kvikdos@8f5d457` on
`improvements`.

## Triaged but not filed

### E050 in MODEMES.ASM and similar -- inconclusive

22 E050s ("Offset cannot be smaller than WORD size") in the May 13 build,
concentrated in `MODEDEFS.INC(72)` (preprocessed line where `dw Parm5`
sits inside the Create_Msg macro body). Triage May 13 2026: reproducible
at minimal scale (V12, V16) **only when an upstream undefined symbol
exists** (e.g. `Function = No_Function` with `No_Function` undefined).
MASM 5 reports the same code as `A2009 Symbol not defined: NO_FUNCTION`
at the actual reference line. WASM reports E050 at the wrong line
(inside the macro body) with a misleading error code.

That makes this a **diagnostic-quality bug**, not a
wasm-rejects-valid-code bug -- the underlying source is genuinely
broken in MASM too. Not filed upstream per maintainer-overload policy;
priority remains STRUC.INC `&` substitution. Re-evaluate if the build's
22 E050s persist after STRUC.INC and PR #24 land.

## Resolved (don't re-investigate)

- **IRP `<'/'>` via macro arg -> E020** -- upstream PR #1622 (was fork
  PR #21), in May 13 binary. CONST2.ASM workaround `<"/">` retired;
  original Microsoft `<'/'>` restored on `watcom-migration`.
- **Trailing-comma line joining outside WATCOM mode** -- upstream PR
  #1621 (was fork PR #22), in May 13 binary. Not currently exercised
  in MS-DOS sources but available.
- **IFDEF name + later `name macro` SIGSEGV** -- upstream #1617.
- **EXTRN:ABS / `invoke` reserved word / `$M_` parsing / BYTE PTR
  forward-ref** -- earlier upstream PRs, verified Apr 13 binary.

## Summary

| Blocker | Targets | Status |
|---------|---------|--------|
| STRUC.INC `&` substitution | SELECT/MODE/GRAPHICS/KEYB/ANSI etc (~296 E032) | **Top priority -- not filed yet** |
| Preprocessor BREAK dangling PURGE | latent | Not exercised |
| kvikdos CL.EXE parallel temp clash | INC/*.C in `-j4` | Workaround: serial INC build |
| IRP single-quoted-char via macro arg | CONST2 | **Fixed (PR #1622)** |
| Trailing-comma outside WATCOM | latent | **Fixed (PR #1621)** |
| kvikdos inplace_realloc Z-tail | INC/*.C | **Fixed** in fork |
