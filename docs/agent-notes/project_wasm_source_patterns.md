---
name: wasm-source-fix-patterns
description: "Catalog of source-side patterns we have found that trigger WASM/MASM 5.10 divergences, with the rewrite that makes WASM happy. Update cadence — when a new pattern is found and committed."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8bd8f8ac-1776-4345-b429-e310157d3963
---

Each entry is a MASM 5.10 construct that compiles silently and a WASM-in-MASM-mode rewrite that does. Order roughly by how often we hit it.

## Reserved-word collisions (E094)

WASM's MASM-mode reserved-word set is wider than MASM 5.10's. Renaming the identifier in source is the fix.

| MASM use | Rename to | Notes |
|---|---|---|
| `invoke`           | `do_invoke`   | 80286 INVOKE pseudo |
| `enter`            | `do_enter`    | 80186 ENTER instruction (used as macro name) |
| `ECHO`             | `do_echo` / `cmd_echo` | .ECHO listing directive |
| `Out` / `OUT` (as a label/proc name) | `PrintOut` | OUT is the x86 I/O instruction mnemonic; a `CALL Out` / `Out:` console-output routine is rejected (WASM E094 / jwasm A2209). DOS `print.asm`. Word-boundary rename only -- `FmtOut` and similar are safe. |
| `addr`             | `set_addr`    | MASM ADDR operator. Includes the case where `addr` is a **macro name** (e.g. `addr macro sym,name` in EXE2BIN/LOCMES.ASM) -- every call site errors E094 'instruction not supported'. The preprocessor's ADDR passes only rewrite `addr db`/`.addr` (struct field/member), NOT macro names, so a macro-named `addr` needs a source rename. |
| `LowWord` / `HighWord` | `LoWord` / `HiWord` | WASM bitfield ops |
| local label `wait` | `wait_loop`   | WAIT instruction; only matters when used as branch target (`LOOPNZ wait`) |
| `ENTER` constant   | `ENTER_KEY`   | when `ENTER = 28` is used as a scan-code constant |
| label `DF`         | `DF_LBL`      | `DF` is the define-fword (48-bit far pointer) data directive; a code label `DF:` is parsed as a `df` directive -> E021 'Expecting number'. Rename the bare label + all jumps (case-insensitive: `JE DF` and `je df` both target it). Sibling labels `DF1`/`DF_X` and `0DFH` constants are fine. DEV/PRINTER/PARSE4E.ASM. |

## Directive / operator unsupported in WASM MASM mode

| MASM construct | WASM equivalent | Caveat |
|---|---|---|
| `name RECORD f1:n1, f2:n2, …`  | comment out RECORD; emit each `MASK <field>` as a named EQU (`MASK_<FIELD> EQU <precomputed>`) | If the record is purely declarative (no MASK/WIDTH/SHIFT use), comment-out alone is enough |
| `NAME EQU THIS WORD` / `EQU THIS BYTE` | `NAME LABEL WORD` / `LABEL BYTE`   | EQU-THIS form errors on every later segment-overridden reference (`MOV AX,ES:NAME`) |
| `NAME EQU THIS BYTE - other_label` | `NAME EQU $ - other_label` | Same root cause; explicit $ works |
| `EQU $` used as a code label (END entry) | `LABEL BYTE` (or `LABEL NEAR` for entry points) | E229 'Invalid start address' at END directive; also triggers W275 'PUBLIC constants should be numeric; 0 written' if exported |
| `LIDT/LGDT qword ptr <mem>` | `LIDT/LGDT fword ptr <mem>` | IDT/GDT descriptor is 6 bytes (FWORD) in 16-bit mode |
| `<reg> * DWORD` as numeric (MASM treats DWORD as 4) | `<reg> * 4`               | E066; MASM 5.10 treats type keywords as size constants in arithmetic, WASM doesn't |
| `REP CMPSB/CMPSW/CMPSD/SCASB/SCASW/SCASD` | `REPE` variant | MASM 5.10 accepted bare REP on conditional string ops; WASM E004 'REP prefix not allowed' |
| `%OUT message` (listing/console progress directive) | comment it out (`;%OUT ...`) | WASM `-zcm=masm` doesn't support `%OUT`, silently fails OBJ generation. Almost all `%OUT` in the tree were already `;`-prefixed; only 6 files had uncommented ones, all inside IF1/IF2 pass-gated cosmetic blocks. Done tree-wide; preprocess-wasm `PCTOUT_PAT` pass retired in same submodule-bump commit. |
| `.XLIST`/`.LIST`/`.XCREF`/`.CREF`/`.LALL`/`.SALL` etc (MASM listing-control) | comment out (`;; .XLIST`) | WASM rejects MASM listing-control directives. May 28 sweep did .ASM/.INC; later passes did .EQU (12 sites, 6 files) and the unpreprocessed INDEINS.MAC. All v4.0 preprocessed-extension files are now clean -> preprocess-wasm `LISTING_PAT` pass **retired** (Jun 4). Only v2.0/source (not built) still has uncommented ones. |
| `SUBTTL <text>` (listing subtitle; WASM segfaults on long-string SUBTTL when STRUC.INC macros are loaded) | comment out | Swept alongside listing directives (May 28); v4.0/src has 0 uncommented SUBTTL. `SUBTTL_PAT` pass **retired** (Jun 4) -- 3rd preprocessor pass retired (after PCTOUT, LISTING). Remaining uncommented SUBTTL only in v2.0/source (not built) + v4.0-ozzie prebuilt disk image. |

## Forward references (E032, E050)

| MASM use | Fix |
|---|---|
| `DB <const_name>` where const_name is an EQU later in same file | Move the EQU above the DB, OR hardcode the value with the original EQU left as documentation |
| `DB <name_L>` where `name_L EQU $-NAME` is later in same file | Hardcode the structure-length byte; keep the EQU below as comment |
| `DW $P_File_Spc+$P_Drv_Only` where PSDATA.INC included later in same file | Hardcode the sum (`Dw 0300h ; $P_File_Spc+$P_Drv_Only — see PSDATA.INC`) |

## Operand-size disambiguation (E040 / E050)

WASM rejects operations on memory operands with segment overrides when it can't infer size. MASM 5.10 inferred from the symbol's DB/DW declaration; WASM needs explicit `BYTE PTR` / `WORD PTR`.

| MASM use | Fix |
|---|---|
| `INC CS:byte_var`            | `INC BYTE PTR CS:byte_var` |
| `INC byte_var` (sometimes)    | `INC BYTE PTR byte_var` (when symbol decl is in another file) |
| `mov DX, seg:arr[BX].word_member` where `arr` is a `DB ... DUP(?)` byte array used as an array of structs -> A2048 (2 vs 1) | `WORD PTR` on the access: `mov DX, WORD PTR seg:arr[BX].word_member` | jwasm types the member access from the `DB` array (BYTE), not the struct member (WORD). COMMAND PATH2.ASM `arg.argv[BX].argpointer` (argv is `DB`, argpointer is `DW`). Real fix would be to declare the array as `argv_ele N DUP(<>)`, but WORD PTR is the localized one. |

## Stale references to renamed/removed symbols (E040 / E251 / E065)

Not a wasm-vs-MASM quirk -- genuinely broken source where an `.INC` renamed
or removed a symbol but a consumer `.ASM` was never updated. MASM reports
"symbol not defined"; wasm often reports a misleading code at the use site
(E040 'invalid instruction operands' when the undefined name is an immediate
operand, E251 'symbol not defined' for a segment/macro name, E065). Fix by
updating the consumer to the new name **only when the mapping is unambiguous**
(matching value + matching comment in the `.INC`). Example: MEMM/INITDEB.ASM
used `DEBC_GSEL/DEBD_GSEL/DEBW1_GSEL/DEBW2_GSEL` but VDMSEL.INC had renamed
them to `DEB1_GSEL..DEB4_GSEL` (same values 088h/090h/098h/0A0h, old names
left commented). Do NOT guess when the original symbol is simply absent (e.g.
INITDEB's `mov bx,ddata` -- there is no `ddata` segment declared, only `dcode`;
resolving needs the external lib's segment layout) -- surface it instead.

A second, very common E251 cause: a cross-module symbol used without an
`extrn`. MASM 5's two-pass linker tolerated some of these; single-pass WASM
does not. Confirm the symbol is `public` + defined in a sibling `.ASM`, then
add the missing `extrn name:<type>` next to the existing ones. Example:
MEMM/INIT.ASM used `[hi_size]` (public/`dw` in OEMPROC.ASM) but only declared
`extrn ext_size`/`extrn sys_size` -- adding `extrn hi_size:word` cleared it.

## Immediate-mask sizing (E048)

| MASM use | Fix |
|---|---|
| `AND byte_var, NOT 8BIT_CONST` | `AND byte_var, (NOT 8BIT_CONST) AND 0FFh` |

WASM widens `NOT X` to 32 bits and rejects the resulting `0xFFFFFFxx` as an 8-bit immediate. Mask the NOT result back to 8 bits.

## CPU directive needed (E002)

| MASM use | Fix |
|---|---|
| `PUSH mem` / `POP mem` (80186+) without `.286` directive | Add `.286` near top of file (after PAGE/TITLE/NAME header) |
| 32-bit operands inferred by default-DWORD (e.g. `AND ES:[DI]+SCB_OPT1`) | Use `.386` instead of `.286` |

## Macro-collision overrides (E236)

| MASM use | Fix |
|---|---|
| Local file redefines a macro from a shared INC (e.g. `procedure` from DOSMAC.INC) | `purge <name>` immediately before the new definition |

## Line-joining hazards (E206 / E032)

| MASM use | Fix |
|---|---|
| `public foo, bar, baz,` with stray trailing comma (PC-DOS-4 source has lots) | Strip the trailing comma. PR #1621's trailing-comma line joining causes the next non-comment line to merge into the public statement |

## Header-guard EQU duplicates (E230)

When an .INC file is pulled both directly and via another INC and there's no header guard, every EQU inside is "already defined" on the second inclusion. Standard fix:

```
IFNDEF <FILE>_INC_
<FILE>_INC_ EQU 1
; ... file content ...
ENDIF
```

We have this on SYSMSG.INC and MAC_EQU.INC. Also use `IFNDEF FALSE / FALSE EQU 0 / ENDIF` for cross-file constants.

## Typeless STRUC field (E032)

Old PC-DOS source occasionally declares a STRUC field with no type keyword,
e.g. `ra  5 dup(?)` or `DResv  5 dup(?)` (reserved-area fields) while every
sibling uses an explicit type. WASM rejects the typeless form with E032
'syntax error'. Fix: add the type that matches the siblings (`db` for the
`N dup(?)` byte-array reserved fields). Example: MAPPER/OLDGETCN.ASM cntry /
Doscntry structs.

## Same-file duplicate EQU (E230)

Old PC-DOS-4 source sometimes redefines the same EQU twice within one file (different comments suggest editing artifact). Delete the second copy.

## Preprocess-wasm bugs (source-side workaround)

| Bug | Workaround |
|---|---|
| `wrap_struc_ifndef` STRUC_DEF_PAT regex `^(\w+)\s+STRUC\b` false-matches `INCLUDE STRUC.INC` at column 0 (treats INCLUDE as struct name; injects unmatched IFNDEF; E300 at EOF) | Indent the `INCLUDE STRUC.INC` line with a tab — `^` anchor no longer matches |
| `.STR` / `.EXT` extensions not in INC_EXTS — files not shadowed to PPDIR; E220 'Cannot open include file' for consumers | Rename `.STR` → `.INC`, `.EXT` → `_EXT.INC` and update INCLUDE callers |
| `.MAC` extension not in INC_EXTS — included `.MAC` files are NOT preprocessed, so any WASM-hostile construct inside them (listing directives, etc.) reaches wasm raw even though the same construct is stripped from `.ASM`/`.INC`. Example: `DEV/XMAEM/INDEINS.MAC` `.XLIST`/`.LIST` survived the listing-directive sweep. | Fix the construct directly in the `.MAC` source (e.g. comment out the listing directives `;; .XLIST`), since the preprocessor won't. Don't add `.MAC` to INC_EXTS — that's the wrong direction per the no-preprocessor end state. |

## TYPE STRUCNAME operator (E065)

WASM in `-zcm=masm` mode does not accept `TYPE STRUCNAME` as a numeric byte-size in expressions (`MOV BX, TYPE FBUFS`, `DB (TYPE RHC) DUP (?)`, recursive `DW TYPE FBUFS` inside the STRUC body).  Replace with `SIZE STRUCNAME` -- including the recursive self-referential case inside the struc definition, which WASM still accepts.  Note: `bin/preprocess-wasm` already does this textually (line 693, `TYPE_OP_PAT.sub('SIZE ', text)`), so dropping the preprocessor would require these source edits to land first.

## Include order matters (E040, forward STRUC refs)

WASM is single-pass; MASM 5 was two-pass.  When file A uses a STRUC defined in file B, B must be `INCLUDE`d before A in the parent .ASM.  Example: `DEV/DISPLAY/DISPLAY.ASM` had `F-PARSER.INC` (defining FBUFS/FTBLK) included LAST; moving it first fixed E040 in CPS-FUNC.INC and WRITE.INC.  Generic rule: when adding new dependencies, reorder INCLUDEs.

## Macro args without explicit commas (call-site fix)

WASM tokenizes macro args by commas only; MASM 5 also split on whitespace plus angle brackets.  `DOSAssume SS <DS>,"msg"` -- WASM reads as 2 args (reg=`SS <DS>`, reglist=`"msg"`), MASM 5 read as 3 args (reg=`SS`, reglist=`DS`, message=`"msg"`).  Fix at the call site: add the explicit comma -- `DOSAssume SS,<DS>,"msg"`.

## Block nesting inside skipped IF (E206)

WASM tracks block nesting (SEGMENT/ENDS, PROC/ENDP) even inside `IF cond` branches whose condition is false.  Old PC-DOS-4 code sometimes put `CODE ENDS` inside `IF not Installed` (with `Installed = TRUE` hardcoded) to work around MASM-5 quirks (`%out Ignore this END error (blasted assembler)` comment).  Fix: drop the dead branch entirely -- it never assembled in MASM 5 either; it just confused WASM's tracker.

## Short-jump overflow (E043)

When a hot-path `JMP SHORT label` ends up >127 bytes from target — usually because we've added explicit BYTE PTRs or expanded other instructions earlier — widen to `JMP label` (3-byte near). Look at FASTOPEN.ASM precedent.

## JWasm-specific patterns (`-Zm` MASM 5.1 mode)

The jwasm-migration branch uses a far smaller preprocessor (comma-sep only); these are source fixes for jwasm `-Zm` divergences from MASM 5.10. Codes are A-prefixed (A2139, A2143, ...), not E-prefixed.

| MASM use | jwasm fix | Notes |
|---|---|---|
| `invoke`/`GOTO`/`.IF`/`C` as macro/label names | `OPTION NOKEYWORD:<name>` before first use, in the shared INC that defines it | jwasm's reserved set (HLL directives, INVOKE, C convention) is wider. One `OPTION NOKEYWORD` in DOSMAC.INC/MACROS5.INC clears the clash across every consumer. |
| Two includes define the same struct name with different layouts -> A2139 non-benign redefinition | Rename the struct **whose name is not referenced by `SIZE`/`TYPE`/`PTR`/instance** (members are global and unaffected by a struct-name rename) | e.g. SYSVAR.INC `Buffinfo` (pool manager) vs BUFFER.INC `BUFFINFO` (single buffer); only `SIZE BUFFINFO` referenced the latter, so renamed SYSVAR's to `BuffPoolInfo`. Same shape as ANSI `INIT_REQ_HDR`->`IOCTL_REQ_HDR`. Grep all-case tokens first; comment-only refs (e.g. `;BuffInfo`) don't count. |
| Proc called (`invoke FOO`) **before** its definition, where the call macro emits `IF2 / IFNDEF name / EXTRN name:NEAR` -> A2143 redefinition at the later `PROC` | Change `EXTRN name:NEAR` -> `EXTERNDEF name:NEAR` in the call macros (invoke, transfer, short_addr, long_addr in DOSMAC.INC) | **jwasm evaluates `IFNDEF` textually per pass** -- a symbol defined LATER reads as undefined at an earlier site even on pass 2 (no cross-pass symbol memory at earlier positions), unlike MASM 5.10 whose pass-1 fills the whole table. So jwasm emits a spurious EXTRN for same-module forward calls. `EXTERNDEF` = PUBLIC-if-defined-else-EXTERN, idempotent, pass-independent -- exactly MASM's intent. **Do NOT just drop the auto-EXTRN**: genuine cross-module externs are not all explicitly declared (proven: A2102 storm in 54 DOS files), so it is load-bearing. No jwasm CLI option restores MASM's two-pass-table IFNDEF. |
| Build-config equate (`IBM EQU IBMVER`) in a shared INC clashes with a per-variant switch file (`STDSW`/`MSSW`/... define `IBM EQU FALSE`) -> A2143 | Guard the shared-INC default with `ifndef NAME / NAME EQU ... / endif` so the switch file's value wins | VERSION.INC `IBM`; the sibling `MSVER` was already guarded, `IBM` was just missing it. Same header-guard-EQU idea as WASM, but here the override comes from a per-build switch file included first, and the shared INC must defer. Cleared the STD*/MS* DOS chain (+6 files). |
| `MOV`/`CMP <byte-flag>,TRUE` where the flag is `DB` and `TRUE EQU 0FFFFh` (word) -> A2048 "Operands must be the same size: 1 - 2" | Mask the immediate to a byte: `(TRUE) AND 0FFh` (= 0FFh) | MASM 5.10 silently truncated the word immediate into the byte; jwasm is strict. Safe when the flag is only tested against `False`(0)/for nonzero (so 0FFh is a fine truthy byte) -- the usual case for DB booleans. **Likely systemic** across subsystems (lots of `MOV byteflag,TRUE`). Applies to both assignment (MOV) and comparison (CMP) sites. CHKDSK fTrunc/IsCross/SecondPass/zerotrunc. (Distinct from the NOT-width family -- here the issue is the symbolic `TRUE`=0FFFFh constant being word-sized, not a `NOT`.) |
| `REPE`/`REPZ` (or `REPNE`/`REPNZ`) prefix on a non-CMPS/SCAS string op (`MOVS`/`STOS`/`LODS`/`INS`/`OUTS`) -> A2028 "Instruction prefix not allowed" | Change to plain `REP` | The conditional-repeat prefixes are only valid on CMPS/SCAS (they test ZF); MASM 5.10 tolerated `repe movsb` / `repz insw` as REP aliases, jwasm rejects them. Plain `REP` is semantically identical (MOVS/STOS/LODS/INS/OUTS don't set flags). SYSINIT2.ASM `repe movsb`, MSHARD.ASM `REPZ INSW`. (This is the inverse of the WASM E004 row above, where bare `REP CMPSB` needed widening to `REPE`.) INS/OUTS also need a `.186`+ CPU directive. |
| `IF NOT <flag>` where flag is a 0/0FFFFh boolean (`Installed`, `BUFFERFLAG`, `IBM`, `SHAREF`, `DEBUG`, ...) -> **wrong branch selected silently**, and A2102 when the skipped branch defined a jump target | Rewrite to `IF (NOT <flag>) AND 0FFFFh` | **jwasm `-Zm` does NOT mask `NOT` to the 16-bit word size**: `NOT 0FFFFh` becomes a WIDE nonzero value -> `IF NOT Installed` takes the IF branch, but MASM 5.10's 16-bit `NOT 0FFFFh = 0` takes the ELSE branch. This is a CORRECTNESS bug, not just an error -- files that "assemble" can have the wrong conditional-assembly branch baked in. `(NOT x) AND 0FFFFh` is provably identical to MASM 16-bit NOT for any value (0->true, 0FFFFh->false, 1->0FFFEh). Same family as the WASM immediate-mask pattern (`(NOT C) AND 0FFh`). All sweep sites are simple `IF NOT <single-symbol>` (only trailing comments) -- a per-line regex is safe; watch for compound `IF NOT (a OR b)` which needs hand-checking. |

| `MOV DS:WORD PTR <const>*4,...` / `OFFSET WORD PTR <label>` (absolute interrupt-vector write) -> A2065 "Constant expected" | Use the bracketed memory form `MOV WORD PTR DS:[<const>*4],OFFSET <label>` | jwasm rejects `WORD PTR` applied to a pure constant address expression (`CHROUT*4`) and `OFFSET` on a WORD-PTR-typed operand. Note `DS:WORD PTR <memvar>` (a real memory label) is fine -- only the constant-address form needs brackets. MSINIT.ASM CHROUT vector. Match the file's own working vector writes. |

| Nested macro definition via MASM `&macro` / `&endm` escaping (a macro that defines another macro from inside itself) -> A2209 Syntax error | Drop the `&`: use plain `macro` / `endm` | jwasm counts nested `macro`/`endm` correctly on its own and does NOT accept the `&`-escaped directive form. Replace only the directive escapes (` &macro`->` macro`, `&endm`->`endm`); leave `&`-symbol concatenations (`add_&grp`, `begin&ln`) intact. INC/CMACROS.INC (Microsoft C-callable-assembly package; addSeg/createSeg build `add_IGROUP` etc.). MASM-only, but MASM is not a target on the jwasm branch. |
| MASM double-ampersand `&&` concatenation nested inside an IRP/REPT in a macro (e.g. `?T&&x = s`, `_&&x`) -> A2039 "Expecting comma: &<name>" (a stray `&` is left) | Replace `&&` -> single `&` | MASM needs `&&` so one `&` survives the macro pass and reaches the IRP expansion; jwasm does not strip the first `&` the same way and wants a single `&` at these sites. Replaced all 30 `&&` in INC/CMACROS.INC. With this + the `&macro`/`&endm` fix above, the whole CMACROS C-interface package assembles under jwasm. |
| Under `.386`/`.386p`, a segment opened with a BARE `segment` (no `USE16`) makes `OFFSET <label>` 32-bit -> A2048 "Operands must be the same size: 2 - 4" (e.g. `mov si, offset X`) | Add `USE16` to the (first) segment def | jwasm defaults bare segments to USE32 once a 386 CPU is selected; MASM 5.10 defaulted them to USE16. Add `USE16` to the first def; bare reopens inherit it. KBD.ASM DCODE (`.386p`, `mov si, offset AltChrs - 1`). |
| `OFFSET <forward-label>` (or any forward symbol) used inside a compile-time `IF`/`IF2` expression -> A2102 "Symbol not defined" at the IF | If it's a no-code sanity/alignment guard (`IF (offset-diff) ... %out ERROR ...`), comment it out (`;JWASM`); otherwise move the IF after the labels are defined | jwasm evaluates IF expressions textually per pass; a forward OFFSET is undefined at that point (MASM's two-pass resolved it by pass 2). Same root as the invoke/`IFNDEF` forward-ref family. SMARTDRV.ASM IF2 ABOVE_BLKMOV/ABOVE_END/ABOVE_RESET_END alignment assertions. |
| Reopening a SEGMENT with attributes (align/combine/class) that differ from its first definition -> A2078 "Segment definition changed: <seg>, alignment" | Make the attributes consistent across all `<seg> SEGMENT ...` for that segment | jwasm requires a segment's attributes to match on every reopen; MASM took the first definition's attributes and ignored later differences. Common with a skeleton block that declares empty segments (`CONST SEGMENT PUBLIC` / `ENDS`) to set up a GROUP, then reopens them with content (`CONST SEGMENT PUBLIC BYTE`). Fix the skeleton to match the content def (or vice-versa) using the file/subsystem's convention. DEBUG.ASM CONST/DATA skeletons. **Sub-case (jwasm-specific ordering):** jwasm allows explicit-first-then-`bare segment` reopen (bare inherits attrs) but NOT bare-first-then-explicit (bare establishes default attrs -> explicit reopen conflicts). MEMM is pervasive here: a canonical include (VDMSEG.INC) defines `_TEXT`/`LAST`/`R_CODE` explicitly, but dozens of files (and OEMDEP.INC) reopen them BARE; when the bare open precedes the VDMSEG include the file gets A2078. Fix = make the early bare opens explicit (match the canonical def) or include the canonical def first. |
| A macro CALLED before its `MACRO` definition (forward macro use) -> A2209 at the call site | Move the macro def above its first use, or (if the macro is cosmetic, e.g. a listing SUBTTL/PAGE helper) comment out the premature call | jwasm requires macros be defined before use; MASM was sometimes laxer. GRAFTABL GRTAB/GRTABHAN/GRTABP call the `HEADER` listing macro as the section header for the very section that *defines* HEADER. Only the call(s) before the def fail; later calls are fine. |
| Same name used as a CODE LABEL in one file and a DATA var (`DW`/`DB`) in a shared INC pulled into it -> A2143 redefinition + A2249 "jump destination must specify a label" | Rename the local code label (keep the shared data var) | The existing symbol is a data var, not a near label, so the `name:` def is a redefinition and `jmp name` rejects it. Like the dup-struct fix: rename the local/less-shared one. CPSPI.ASM `HWCP_1:`/`HWCP_2:` (parse-loop labels) vs CPSPEQU.INC `HWCP_1 DW ?` -> renamed labels to HWCP_LP1/HWCP_LP2. |
| `c`/`C` used as an identifier (label, parm name, EQU) -> A2209 | `OPTION NOKEYWORD:<C>` before first use (if the file doesn't use the C calling-convention directive) | `C` is jwasm's reserved C-calling-convention keyword. Same family as the `invoke`/`GOTO`/`OUT` NOKEYWORD frees. ITOUPPER.ASM `parmW c`; MODEVID.ASM `C EQU 0`. |
| `LowWord`/`HighWord` used as identifiers (e.g. struct field names) -> A2209 | `OPTION NOKEYWORD:<LowWord HighWord>` (multi-keyword form works) | jwasm reserves the MASM-6 `LOWWORD`/`HIGHWORD` word-extraction operators (not in MASM 5.10). On the jwasm path NOKEYWORD is cleaner than the WASM-path rename to `LoWord`/`HiWord` (no `.field` reference updates). MEMM `vm386.inc` `DwordS` struct. |
| `Wait EQU 77` (a constant whose NAME is the x86 `WAIT`/FWAIT mnemonic), included OUTSIDE a segment -> A2082 "Must be in segment block" (NOT A2209); inside a segment the same line gives A2209 | `OPTION NOKEYWORD:<Wait>` just before the equate | jwasm parses the mnemonic-named line as the WAIT *instruction* (then chokes on the trailing `EQU`); outside a segment an instruction is A2082, so the error misleads. jwasm's line counter mis-blames the *include site* (e.g. `syscall.inc:91` even though the include directive is at the parent's line 192) -- so trust the symbol name, not the line. NOKEYWORD beats rename here: shared syscall-constant table, name unused locally, keeps the canonical value. RAMDRIVE local `SYSCALL.INC`. Same family as the `Out`/`C`/`invoke` mnemonic frees. |

| Hand-encoded jump that does offset arithmetic on an EXTERNAL symbol, e.g. `DW (OFFSET extern)-(localconst)` (a manual 386 near-Jcc `0F 8x cw` built in a macro) -> A2193 "Invalid use of external symbol" | Emit a REAL jump instruction instead -- only that forms the relative relocation. For a conditional long-jump-to-external, use the inverse-short-Jcc-over-near-`JMP extern` idiom (`Jcc_inverse over / JMP extern / over:`); `.286P`-safe, no `.386` needed | jwasm won't do offset/displacement arithmetic on an external (no DW form works: OFFSET, bare, `$`-relative all A2193). Verified `JMP extern` / `Jcc extern` emit proper fixups. XMAEM INDEDMA `LJNE/LJA DISPLAY` via the LJCOND macro -- added an `LJX` macro for the 2 external sites, left LJCOND's `DW (OFFSET..)` form for the working LOCAL-target jumps. Same class as the deferred ".386 Jcc near ptr extern" idea but avoids the USE32-default risk. |
| A redefinable numeric `=` symbol assigned BOTH an absolute value (e.g. `0`) and a relocatable label/offset across reassignments, then used in `dw <sym>` -> A2164 "No segment information to create fixup" (flushed at segment end) | Make it a TEXT equate: `sym EQU <X>` instead of `sym = X`, so `dw sym` text-substitutes to `dw <label>` (direct ref -> proper fixup) or `dw <0>` | The numeric `=` types the symbol as a Number that loses the relocatable's segment, so the reloc-valued `dw` can't form its fixup. IFE / `OFFSET` / `AND 0FFFFh` coercions all FAIL (A2164/A2065). The text equate routes the label name directly. FORMAT FORMSG.INC `Sublist`. Keep `?`/`@`/`$` in label names inside the `< >`. |

| `LOCK MOV <mem>,<reg>` / `LOCK MOV <reg>,<mem>` -> A2028 "Instruction prefix not allowed" | Drop the `LOCK` prefix | LOCK is architecturally invalid on MOV (#UD on 386+; merely tolerated on 8086/286). MASM 5.10 emitted it blindly. Distinct from the REPE-on-MOVS A2028 row -- here the prefix is LOCK, the fix is removal, not substitution. XMA2EMS XMA1DIAG.INC charge-bus memory test (4 sites). On a single-CPU diagnostic the semantics are unchanged. |
| `var DB (?)` / `DW (?)` bare parenthesized uninitialized -> A2209 "Syntax error: ?)" | `DB ?` (keep `N DUP (?)` -- that form is fine) | COMMAND COMEQU/FORDATA/TSPC, XMA2EMS EMSINIT.INC. |

Sweep-counting note: the `EndProc` macro emits `***** Possible stack size error in X *****` via `%OUT` -- that is a message, not an error. Filter jwasm sweeps on `Error A[0-9]`, never the bare word "error".

Tooling note (Jun 12 2026): **jwasm silently ignores any command-line option placed AFTER the source filename** -- `bin/jwasm-masm` passed `-Fo=<out>` last, so no sweep before Jun 12 ever wrote an OBJ (error counts were still valid). Fixed: attached `-Fo<out>` now precedes the filename. When invoking jwasm directly, always put options first.

## Cross-references

- [[wasm-migration-remaining-blockers]] — top-down view of what is left, with E-code distribution and STRUC.INC bucket
- [[wasm-migration-end-state-no-preprocessor]] — goal is to retire preprocess-wasm; new transformations are NOT to be added. These source-side patterns are the alternative.
- [[feedback-prefer-wasm-fix]] — was the previous default; in this session we agreed source-side is fine since most patterns above are real-but-tolerated MASM 5.10 sloppiness, not WASM rejecting valid code.
