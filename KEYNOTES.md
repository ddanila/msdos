# MS-DOS 4.0 Build — Key Notes

## Workflow Rules
- Commit after every step that succeeds, push to remote (origin/master).

## CI Workflow

`make` (build), then `make test` (tests only — no rebuild). Do not rely on
`make test` to build — `test` target no longer depends on `all`.

## Line Ending Rules

**CRLF required** (DOS tools parse as text, BUILDIDX computes byte offsets):
- MSG, SKL, LBR, LNK, INF, BAT, INI, IDX files

**LF only** (source code — CRLF corrupts MASM THEADR records in .OBJ output):
- ASM, C, H, INC files

These rules are enforced by `.gitattributes` in the MS-DOS submodule (`MS-DOS/.gitattributes`).
Without it, git may normalize CRLF→LF on checkout, causing `buildidx` to produce a different
`USA-MS.IDX`.

### CRLF-in-blob pitfall (perpetually "modified" MSG files)

Commit `18eeeab` in the upstream MS-DOS repo converted data files to CRLF **and stored CRLF
bytes directly in the git object store** (blobs). This conflicts with `text eol=crlf` in
`.gitattributes`, which tells git to store LF in blobs and convert LF→CRLF on checkout.
Result: git normalizes the working-tree CRLF to LF for comparison, finds it doesn't match the
CRLF blob, and permanently reports `v4.0/src/MESSAGES/USA-MS.MSG` (and similar files) as
"modified" even when the content is byte-for-byte identical to HEAD.

**Impact:** cosmetic only — `git diff --ignore-cr-at-eol` shows zero real differences, the
build is unaffected (working-tree files are still CRLF as DOS tools require).

**Correct long-term fix:** change `*.MSG text eol=crlf` → `*.MSG binary` in `.gitattributes`.
`binary` stores files as-is (CRLF blobs stay CRLF blobs) and disables normalization entirely,
which is semantically correct since BUILDIDX treats these files as byte-addressed binary data.
Avoided for now to not diverge from upstream with a large no-content-change commit.

## TYPE ^Z Requirement

`TYPE <file>` in batch mode hangs if the file doesn't end with ^Z (0x1A). DOS text-mode
reads use ^Z as EOF sentinel. Always terminate text files with `\x1a` when used with TYPE
in batch scripts: `printf 'content\r\n\x1a'`.

## WASM Migration (Open Watcom → replaces MASM 5.x via kvikdos)

**Status:** DOS kernel (50 files) + INC subsystem (5 targets) + BIOS subsystem (14 targets: MSLOAD, MSBIO1, MSBIO2, MSAUX, MSCON, MSCLOCK, MSDISK, MSHARD, MSINIT, SYSINIT1, SYSINIT2, SYSCONF, + MSBIO.EXE link) fully pass. `bin/wasm-masm` is wired into the Makefile. Next: C compiler (wcc replacing CL.EXE), linker (wlink), librarian (wlib).

### Wrapper
`bin/wasm-masm` — translates MASM two-arg calling convention to WASM:
- Input: `masm "FLAGS -I..." "SOURCE.ASM,OUTPUT.OBJ;"`
- Output: `wasm -0 -ms -zq [flags] source.asm -fo=output.obj`
- Flag translations: `-Mx`/`-t` dropped (WASM defaults); `-I` → `-i=`; `-D` → `-d`; `D:\\TOOLS\\INC` path skipped

### WASM vs MASM 5.x compatibility issues (all fixed)

**1. Duplicate EQU/label (E230)**
MASM silently allows re-defining `TRUE`/`FALSE`/`IBM` when multiple include files define the same constant. WASM rejects with E230. Fix: add `ifndef X / ... / endif` guards in `DOSSYM.INC`, `VERSION.INC`, `MSSW.ASM`.

**2. SUBTTL and TITLE parsed as code (E251/E032)**
WASM parses SUBTTL/TITLE argument text as assembly code. If the title contains a word that matches a macro name (e.g. `SUBTTL ... Return ...` → calls `return` macro; `TITLE ... error ...` → calls `error` macro), assembly fails. Fix: comment out all SUBTTL and problematic TITLE directives with `;; `.

**3. STRUC name case sensitivity (E306)**
`DOSINFO STRUC` must close with `DOSINFO ENDS`, not `DosInfo ENDS`. MASM 5.x was case-insensitive. Fix: match case exactly.

**4. Duplicate EXTRN (E299)**
WASM rejects duplicate EXTRN declarations for the same symbol. Fix: remove duplicates. Special case: `STRIN.ASM` and `KSTRIN.ASM` declared `EXTRN COPYNEW/BACKMES/FINDOLD:NEAR` and also *defined* those labels in the same file. MASM 5.x silently overrode the EXTRN. Fix: remove the three EXTRN declarations from both files.

**5. Bare `Invoke` treated as directive (E094)**
WASM has a built-in `INVOKE` directive. Uses of `Invoke` (renamed from MASM's custom macro via DOSMAC.INC) clash. Fix: rename to `DOSInvoke`.

**6. `ORG expr` with character literals (E066)**
`ORG CharType-Zero+"."` fails — WASM doesn't convert single-char string literals to their ASCII value in arithmetic ORG expressions. Fix: replace `"."` etc. with explicit ASCII values (`46`, `34`, etc.) at the call sites.

**7. `db LOW (NOT (expr))` (E021)**
WASM doesn't support `LOW` as a unary operator in `db` directives. Fix: pre-compute the values (`LOW(NOT(fChk))` = `0FEH`, etc.) and use hex literals directly.

**8. `<= ` inside angle-bracket argument (E032)**
`<"text <= more">` — WASM sees `<` in `<=` as a nested angle-bracket start. Fix: replace `<=` with `LE` inside string literals used in angle-bracket macro args.

**9. ^Z (0x1A) EOF byte**
DOS source files end with `^Z` (0x1A). WASM stops processing at `^Z`. If a file has `^Z` before an `endif`, the `endif` is invisible. Fix: strip `^Z` in Python binary mode before writing: `data.replace(b'\x1a', b'')`. Never use shell `echo >>` or `tr` on these files — use Python for binary correctness.

**10. Wrong error grep pattern**
WASM errors look like `filename(line): Error! Exx`, not `^Error`. Always grep with `': Error!'` pattern to count real errors.

**11. OOM from batch WASM invocations — NEVER `make -k -f Makefile`**
Even sequential WASM processes are memory-heavy. Never loop over 20+ files. Keep test batches ≤20 files. See memory note: `feedback_wasm_oom.md`.

**CRITICAL:** Never run `make -k -f Makefile` (full build with continue-on-error). This launches hundreds of WASM invocations across all subsystems (CMD alone has 610+ OBJ targets) and causes OOM / system crash.

**Safe workflow — always build ONE subsystem at a time:**
```
make -f Makefile boot      # ~1 file
make -f Makefile mapper    # ~55 files
make -f Makefile bios      # ~14 files
make -f Makefile inc       # ~5 files
make -f Makefile dos       # ~50 files (link has pre-existing errors)
make -f Makefile cmd       # ~many files — build and fix errors one at a time
make -f Makefile memm      # ...
make -f Makefile select    # ...
```
Each subsystem build stops at first WASM error, keeping total invocations bounded. Fix the error, re-run the same subsystem target, repeat.

**12. Include guard needed for DOSMAC.INC (E236)**
`DOSSYM.INC` includes `DOSMAC.INC` and some source files also include it directly. WASM (single-pass) rejects macro redefinitions on second inclusion. Fix: wrap `DOSMAC.INC` in `IFNDEF DOSMAC_INC_ / DOSMAC_INC_ EQU 1 / ... / ENDIF`.

**13. CALL OUT — x86 keyword conflict (E040)**
`CALL OUT` fails — WASM parses `OUT` as x86 I/O instruction even when used as a label. Worse, WASM evaluates this even inside a FALSE `IF` block (MASM skips false blocks entirely). Fix: rename `OUT` procedure to `OUTRTN` in `PRINT.ASM` and `MSINIT.ASM`.

**14. Forward-ref computed symbols (E050)**
`MAXCALL DB VAL1` where `VAL1 = ($-DISPATCH)/2 - 1` is computed later in the file. WASM single-pass can't resolve this forward reference. Fix: move the `DB` declarations after the `VAL1`/`VAL2` assignments (`MS_TABLE.ASM`).

**15. `short_addr name` in data segments needs EXTRN (E251)**
`short_addr X` expands to `DW OFFSET DOSGROUP:X`. If `X` is defined in another OBJ, WASM requires an explicit `EXTRN X:NEAR` declaration. Affected: `CONST2.ASM` (DEVIOBUF), `MSCONST.ASM` (SNULDEV/INULDEV), `DOSMES.ASM` (13 ESCFUNC entries), `MS_TABLE.ASM` (125 dispatch table entries).

**16. `^Z` before newline in include filename (E220)**
`YESNO.ASM` ended with `include MSDOS.CL3\x1a` (no newline). WASM tried to open `MSDOS.CL3\x1a` as filename. Fix: add newline before `\x1a` using Python binary mode.

**17. WASM IFNDEF on macro names doesn't work**
`IFNDEF macroname` does NOT recognize macro names — only EQU/label symbols. Must use a separate EQU sentinel to guard macro definitions. Fix: `IFNDEF PATHMACROS_DEFINED_ / PATHMACROS_DEFINED_ EQU 1 / ...macros... / ENDIF`.

**18. WASM `=` vs `EQU` for include guards**
Guards using `X = 1` (reassignable variable) are not recognized by IFNDEF. Must use `X EQU 1`. Affected: `VERSION.INC` (VERSION_INC_INCLUDED = 1 → EQU 1) and any other guard-style variables.

**19. WASM IFNDEF guards: EQU must be placed INSIDE the guard**
If the sentinel `X EQU 1` is placed OUTSIDE the `IFNDEF X / ... / ENDIF` block, re-inclusion still allows the body to execute the second time. Sentinel must be the first statement inside the guard.

**20. REP/REPE on non-string instructions (E101)**
`REPZ INSW` / `REPZ INSB` (port I/O string instructions) not supported. `REPE MOVSB` is also rejected (use `REP MOVSB` instead). Fix: either replace with explicit loop (for INS*) or use REP (for MOV*).

**21. Struct name as arithmetic constant fails (E077)**
`WORD PTR CHROUT*4` — WASM parses `WORD PTR CHROUT` as a memory reference, not a numeric constant. CHROUT is an EQU. Fix: use the literal value: `(29H*4)`.

**22. `+byte` / `+word` as arithmetic offsets (E065/E066)**
`[si+byte]` and `[di+word]` fail — WASM does not support `byte`/`word` as arithmetic constants (1 and 2 respectively). Fix: replace with `[si+1]` and `[di+2]`.

**23. `NOT immediate` out-of-range (E048)**
`mov cs:EOF, not END_OF_FILE` where END_OF_FILE=0FFh and EOF is a DB (byte). WASM rejects `NOT immediate` for byte-range values. Fix: load into AL and `not al` before storing.

**24. Uninitialized `?stackdepth` in BIOS context (E250: nesting too deep)**
`DOSMAC.INC` initializes `?stackdepth = 0` but BIOS files use `PUSHPOP.INC` without including DOSMAC.INC first. WASM crashes on uninitialized variable. Fix: add `?stackdepth = 0` initialization in `PUSHPOP.INC` with IFNDEF guard.

**25. Angle bracket in macro string argument (E032)**
`MESSAGE FTESTINIT,<"<">` — the `>` inside `"..."` closes the outer `<...>` bracket prematurely. Fix: use unquoted string without outer angle brackets: `MESSAGE FTESTINIT,"<"`.

**32. WASM `%out` suppresses OBJ creation (no error, 0-byte OBJ)**
`%out` directive causes WASM to discard the OBJ output (produces 0-byte file with 0 errors). Fix: replace `%out` with `;; WASM: %out removed` in all COMMAND.CL* files (fix_cl_forward_refs.py).

**33. WASM EXTRN/IFNDEF interaction — L2025 duplicate PUBLIC**
In WASM, `EXTRN name:type` makes `IFNDEF name` return FALSE (symbol is "defined"). In MASM, EXTRN symbols remain invisible to IFNDEF. If a symbol is declared EXTRN before MSGDCL.INC runs, MSGDCL's `IFNDEF $M_CLS_N` returns FALSE → emits `PUBLIC` → L2025 duplicate when the symbol is also PUBLIC in the defining OBJ.
Fix pattern: use a companion `$M_HAS_xxx = 1` flag in the file that DEFINES the symbol. MSGDCL checks `IFNDEF $M_HAS_xxx` instead of `IFNDEF $M_CLS_N`. Applied to:
- `$M_RT2`: added `$M_HAS_RT2 = 1` in MSGSERV.ASM MSGDATA section; MSGDCL.INC COMR branch now uses `IFDEF $M_HAS_RT2` (PUBLIC only); EXTRN handled by MSGSERV.ASM.
- `$M_CLS_N` (N=1..8): fix_cl_forward_refs.py injects `$M_HAS_CLS_N = 1` and `$M_HAS_$M_CLS_N = 1` after each `PUBLIC $M_CLS_N` in CL* files. MSGDCL `$M_DECLARE2` checks `$M_HAS_CLS_&innum` (all 3 branches). `$M_CHECK` checks `$M_HAS_&parm`.
- `$M_MSGSERV_1/2`: `$M_HAS_MSGSERV_N = 1` and `$M_HAS_$M_MSGSERV_N = 1` injected by fix_cl_forward_refs.py in CL1/CL2 files. EXTRN guards added in MSGSERV.ASM LOADmsg section.
- `$M_GET_MSG_ADDRESS`: `$M_HAS_$M_GET_MSG_ADDRESS = 1` set in MSGSERV.ASM `IF $M_SUBS` block; `$M_CHECK` uses `$M_HAS_$M_GET_MSG_ADDRESS`.

**34. WASM `=` equate makes IFNDEF return FALSE; EXTRN of equate generates external named by VALUE**
`$M_RT2 = 0` (reassignable equate) causes WASM to treat `$M_RT2` as defined (unlike MASM). Worse: `EXTRN $M_RT2:BYTE` when `$M_RT2 = 0` → WASM substitutes the value (0) → generates external symbol named "0" → L2029 unresolved external "0". Fix: in MSGSERV.ASM DISK_PROC/LOADmsg/GETmsg/DISPLAYmsg COMR sections, replace the placeholder `$M_RT2 = 0` pattern with a proper `EXTRN $M_RT2:BYTE` (guarded by `$M_HAS_RT2_EXTERN` to avoid double-declaration) + `$M_RT EQU $M_RT2` alias. MSGDCL no longer needs to EXTRN $M_RT2 for COMR case.

**40. MSG_UTILNAME CTL double-include → E230 $M_NUM_CLS already defined**
`MSG_UTILNAME <UTIL>` includes `UTIL.CTL` (defines `$M_NUM_CLS EQU N`). Later, `Msg_Services <...,UTIL.CTL>` includes it again → E230 re-definition. MASM two-pass was silent; WASM single-pass rejects.
Fix: wrap `$M_NUM_CLS EQU N` in `IFNDEF $M_NUM_CLS / ... / ENDIF` in the CTL file. Updated `fix_cl_forward_refs.py` to add this guard when processing a directory (also handles `*.CTL` files). Add `python3 fix_cl_forward_refs.py <DIR>/` step after each BUILDMSG call in Makefile.

**41. MSG_SERVICES CL-before-service ordering — EXTRN vs PROC conflict (E299)**
In the original DISPLAY.ASM for FORMAT, service calls (`NEARmsg`, `LOADmsg`, `DISPLAYmsg`) come BEFORE the class-file call (`FORMAT.CLA,...,FORMAT.CTL`). MSGSERV.ASM (included for each service call) emits `EXTRN $M_MSGSERV_1:NEAR` since the CL file hasn't been included yet. Then when `FORMAT.CL1` is finally included, `$M_MSGSERV_1 PROC NEAR` conflicts with the already-declared EXTRN → E299.
Fix: reorder `Msg_Services` in DISPLAY.ASM so the CL-files call comes FIRST (mirrors SYSSR.ASM pattern). This ensures `$M_HAS_MSGSERV_1 = 1` is set before MSGSERV.ASM's EXTRN-guard block runs.
**Rule:** in any assembly that uses both `Msg_Services <CL files>` and `Msg_Services <LOADmsg/...>`, the CL files call must come first.

**42. FORMSG.INC uses SYSMSG.INC constants before SYSMSG.INC is included (E050)**
FORMAT's include order is: FOREQU.INC → FORMSG.INC → SYSMSG.INC. FORMSG.INC's `Create_Msg` macro uses `STDOUT`, `No_Handle`, `No_Input` as Handle/Function values in DB/DW directives. These are defined in SYSMSG.INC, not yet available when FORMSG.INC is assembled. WASM single-pass: undefined symbol in `var = STDOUT` may produce a fixup/label reference; `db Class` then receives an unexpected offset expression → E050 "Offset cannot be smaller than WORD size".
Fix: pre-define `STDOUT`, `STDERR`, `NO_HANDLE`, `NO_INPUT` in FOREQU.INC (with IFNDEF guards) before FORMSG.INC is included. Also add IFNDEF guard for `NO_INPUT` in SYSMSG.INC.

**43. $M_BUILD_PTRS nummsg expansion — OPEN issue (FORMAT DISPLAY.OBJ still failing)**
After fixing issues #40-42, `DISPLAY.OBJ` still fails with E251 "$M_CLS_4 is not defined" through "$M_CLS_23 is not defined". The call chain: `Msg_Services <LOADmsg>` (DISPLAY.ASM:81) → INCLUDE MSGSERV.ASM (SYSMSG.INC:404) → `$M_BUILD_PTRS %$M_NUM_CLS` (MSGSERV.ASM:594) → REPT iterates past 3. FORMAT has only 3 classes (CLA/CLB/CLC → $M_CLS_1/2/3). The REPT loop runs more than 3 times (errors from CLS_4 onward imply nummsg ≥ 23 at REPT execution time). $M_NUM_CLS is defined as 3 via FORMAT.CTL. Root cause unclear: possibilities include WASM `%` operator not expanding `%$M_NUM_CLS` correctly in nested macro argument, or $M_NUM_CLS being evaluated to a different value than expected at REPT time. **Status: under investigation.**

**37. $M_BUILD_PTRS timing — EXTRN guards needed before $M_MAKE_COMR/$M_MAKE_COMT**
`$M_MAKE_COMR` calls `CALL $M_CLS_3`..`CALL $M_CLS_7` before MSGDCL.INC runs (MSGDCL is included after MSG_SERVICES). WASM E251 "symbol not defined" for each class. Fix: add `IFNDEF $M_HAS_CLS_N; IF FARmsg; EXTRN $M_CLS_N:FAR; ELSE; EXTRN $M_CLS_N:NEAR; ENDIF; ENDIF` guards inside `$M_MAKE_COMR` and `$M_MAKE_COMT` macros in SYSMSG.INC.

**38. AD054 amendment removed CL3/CL4 from RDATA.ASM — $M_CLS_1/$M_CLS_2 unresolved**
The AD054 amendment changed `MSG_SERVICES <COMR,MSGDATA,COMMAND.CLA,COMMAND.CL3,COMMAND.CL4>` to omit CL3/CL4. These define $M_CLS_1 and $M_CLS_2, which are referenced via EXTRN in all 6 COMMAND OBJs but never defined anywhere → L2029. The Makefile still lists CL3/CL4 as RDATA.OBJ dependencies (revealing the bug). Fix: restore CL3/CL4 in RDATA.ASM's MSG_SERVICES call.

**39. triageError cross-group NEAR call — L2002 fixup overflow**
INIT.ASM (RESGROUP:INIT) calls `triageError` declared as `EXTRN:NEAR`. `triageError` is defined in TMISC2.ASM in TRANCODE (TRANGROUP). Different groups → NEAR call cannot span groups → L2002. Pre-existing in MASM build too. Fix: change `EXTRN triageError:NEAR` to `EXTRN triageError:FAR` in INIT.ASM. Also removed duplicate EXTRN set (copy-paste artifact).

**35. WASM BREAK macro / SUBTTL Trap interaction**
`BREAK <Trap: Get the attention of MSDOS>` expands to `SUBTTL Trap: ...`. WASM (case-insensitive) parses `Trap:` as an invocation of the `trap` macro → E225 "Data emitted with no segment". Fix: redefine BREAK as empty macro in TDATA.ASM before COMEQU.ASM include.

**36. `int_command` undefined in TDATA (E251)**
COMEQU.ASM's `trap` macro references `int_command` (from VECTOR.INC) at definition time. VECTOR.INC is not in TDATA's include chain. Fix: add `IFNDEF int_command; int_command EQU 21H; ENDIF` before the COMEQU.ASM include in TDATA.ASM.

**26. WASM -Mx flag makes macro parameter substitution case-sensitive**
`MACRO AA` with body using `&aa` (lowercase) fails under `-Mx`. MASM was case-insensitive for macro parameter substitution. Fix: normalize all parameter references to same case as the MACRO parameter declaration.

**27. Struct initialization with DUP fields (E020)**
WASM cannot handle `<val1, val2, N dup (x)>` struct initializer syntax. Fix: replace with explicit `label byte` + individual `db`/`dw` directives with hardcoded sizes.

**28. IF1/IF2 two-pass directives (E300: unclosed conditional)**
`IF1 ... INCLUDE BPB.INC ... ELSE ... ENDIF` not supported in WASM (single-pass). Fix: replace with `IFNDEF A_BPB / INCLUDE BPB.INC / ENDIF`. Note: misplaced `endif` in comments can also cause E300.

**29. Trailing comma in EXTRN (E214)**
`EXTRN foo:word,bar:word,` with trailing comma causes E214 "Colon expected" on the next EXTRN line. WASM does not allow line continuation via trailing comma. Fix: remove trailing commas.

**30. Forward-referenced EQU constants used as immediates (E040)**
WASM single-pass: EQU constants defined near the end of a file cannot be used as immediates in instructions earlier in the file. MASM two-pass handled this transparently. Fix: hoist the EQU definitions to before their first use (top of file or before segment). Affected: `SYSINIT2.ASM` switchnum/flagec35/flagdrive/flagcyln/flagseclim/flagheads/flagff.

**31. Bare `invoke` treated as built-in directive (E094)**
WASM has a built-in `INVOKE` directive (case-insensitive). Legacy BIOS code using `invoke GETCHR` (without `DOS` prefix) hits E094. Fix: replace `invoke` with `DOSInvoke`.

## Build Architecture
- kvikdos cannot spawn subprocesses (exec replaces process), so NMAKE is unusable.
- Linux GNU Makefile calls kvikdos for each individual DOS tool invocation.
- `bin/dos-run` mounts C: at `MS-DOS/v4.0/src/` (uppercase mode) and uses `--cwd=C:\SUBDIR\`
  to set the initial DOS current directory, allowing `..` relative paths to work.

## Filename Case
- kvikdos mounts C: in uppercase mode — all DOS filenames must be uppercase in Makefile rules.
- ASM/OBJ/EXE/BIN/LIB targets: use uppercase (MSBOOT.OBJ, MAPPER.LIB, etc.).
- The `MESSAGES_OUT` target is `USA-MS.IDX` (uppercase), not `usa-ms.idx`.

## Build Status

### Core (libraries, kernel, boot)
| Module   | Status  | Output                    |
|----------|---------|---------------------------|
| MESSAGES | ✅ done | USA-MS.IDX                |
| MAPPER   | ✅ done | MAPPER.LIB                |
| BOOT     | ✅ done | INC/boot.inc              |
| INC      | ✅ done | *.OBJ in INC/             |
| BIOS     | ✅ done | BIOS/IO.SYS               |
| DOS      | ✅ done | DOS/MSDOS.SYS             |
| MEMM     | ✅ done | MEMM/EMM386.SYS           |

### CMD utilities
| Utility       | Status  | Output                         |
|---------------|---------|--------------------------------|
| COMMAND       | ✅ done | CMD/COMMAND/COMMAND.EXE        |
| FORMAT        | 🔄 in progress | DISPLAY.OBJ failing: $M_BUILD_PTRS nummsg expansion issue (issue #43) |
| SYS           | ✅ done | W249 warnings only (END directive) — all 3 OBJs assemble cleanly |
| CHKDSK        | ✅ done | CMD/CHKDSK/CHKDSK.COM          |
| DEBUG         | ✅ done | CMD/DEBUG/DEBUG.COM            |
| MEM           | ✅ done | CMD/MEM/MEM.EXE                |
| FDISK         | ✅ done | CMD/FDISK/FDISK.EXE            |
| MORE          | ✅ done | CMD/MORE/MORE.COM              |
| SORT          | ✅ done | CMD/SORT/SORT.EXE              |
| LABEL         | ✅ done | CMD/LABEL/LABEL.COM            |
| FIND          | ✅ done | CMD/FIND/FIND.EXE              |
| TREE          | ✅ done | CMD/TREE/TREE.COM              |
| COMP          | ✅ done | CMD/COMP/COMP.COM              |
| ATTRIB        | ✅ done | CMD/ATTRIB/ATTRIB.EXE          |
| EDLIN         | ✅ done | CMD/EDLIN/EDLIN.COM            |
| FC            | ✅ done | CMD/FC/FC.EXE                  |
| NLSFUNC       | ✅ done | CMD/NLSFUNC/NLSFUNC.EXE        |
| ASSIGN        | ✅ done | CMD/ASSIGN/ASSIGN.COM          |
| XCOPY         | ✅ done | CMD/XCOPY/XCOPY.EXE            |
| DISKCOMP      | ✅ done | CMD/DISKCOMP/DISKCOMP.COM      |
| DISKCOPY      | ✅ done | CMD/DISKCOPY/DISKCOPY.COM      |
| APPEND        | ✅ done | CMD/APPEND/APPEND.EXE          |
| RECOVER       | ✅ done | CMD/RECOVER/RECOVER.COM        |
| FASTOPEN      | ✅ done | CMD/FASTOPEN/FASTOPEN.EXE      |
| PRINT         | ✅ done | CMD/PRINT/PRINT.COM            |
| FILESYS       | ✅ done | CMD/FILESYS/FILESYS.EXE        |
| REPLACE       | ✅ done | CMD/REPLACE/REPLACE.EXE        |
| JOIN          | ✅ done | CMD/JOIN/JOIN.EXE              |
| SUBST         | ✅ done | CMD/SUBST/SUBST.EXE            |
| BACKUP        | ✅ done | CMD/BACKUP/BACKUP.COM          |
| RESTORE       | ✅ done | CMD/RESTORE/RESTORE.COM        |
| GRAFTABL      | ✅ done | CMD/GRAFTABL/GRAFTABL.COM      |
| KEYB          | ✅ done | CMD/KEYB/KEYB.COM              |
| SHARE         | ✅ done | CMD/SHARE/SHARE.EXE            |
| EXE2BIN       | ✅ done | CMD/EXE2BIN/EXE2BIN.EXE        |
| GRAPHICS      | ✅ done | CMD/GRAPHICS/GRAPHICS.COM      |
| IFSFUNC       | ✅ done | CMD/IFSFUNC/IFSFUNC.EXE        |
| MODE          | ✅ done | CMD/MODE/MODE.COM              |

### DEV (device drivers)
| Module        | Status  | Output                         |
|---------------|---------|--------------------------------|
| ANSI          | ✅ done | DEV/ANSI/ANSI.SYS              |
| COUNTRY       | ✅ done | DEV/COUNTRY/COUNTRY.SYS        |
| DISPLAY       | ✅ done | DEV/DISPLAY/DISPLAY.SYS        |
| DRIVER        | ✅ done | DEV/DRIVER/DRIVER.SYS          |
| KEYBOARD      | ✅ done | DEV/KEYBOARD/KEYBOARD.SYS      |
| PRINTER       | ✅ done | DEV/PRINTER/PRINTER.SYS        |
| RAMDRIVE      | ✅ done | DEV/RAMDRIVE/RAMDRIVE.SYS      |
| SMARTDRV      | ✅ done | DEV/SMARTDRV/SMARTDRV.SYS      |
| FLUSH13       | ✅ done | DEV/SMARTDRV/FLUSH13.EXE       |
| VDISK         | ✅ done | DEV/VDISK/VDISK.SYS            |
| XMA2EMS       | ✅ done | DEV/XMA2EMS/XMA2EMS.SYS        |
| XMAEM         | ✅ done | DEV/XMAEM/XMAEM.SYS            |

### Other
| Module        | Status  | Output                         |
|---------------|---------|--------------------------------|
| SELECT        | ✅ done | SELECT.{EXE,DAT,COM,HLP}       |
| DEPLOY        | ✅ done | out/floppy.img                 |
| VERIFY        | ✅ done | headless QEMU boot confirmed   |
| SYS e2e test  | ✅ done | `make test-sys`                |

## Manual Testing (Interactive QEMU)

Run the floppy image in a graphical QEMU window for manual testing:

```bash
# Build the image first (if not already built):
make deploy

# Launch QEMU with SDL display:
./run-qemu.sh

# Or pass a custom image path:
./run-qemu.sh out/floppy-test.img
```

- Uses `-display sdl` (graphical window); requires `qemu-system-i386` and SDL libraries.
- Memory: 4 MB (matches the headless verify target).
- Equivalent `make` target: `make run-boot` (same image, same flags, but no SDL forcing).
- To quit QEMU: `Ctrl+Alt+Q` or close the window, or use the QEMU monitor (`Ctrl+Alt+2`, then `quit`).

### SYS.COM e2e test (`make test-sys`)

Tests that `SYS B:` correctly transfers system files to a blank floppy and that the result boots.

```bash
make test-sys
```

Steps performed by `tests/test_sys.sh`:
1. Copies `out/floppy.img` → `out/floppy-sys-boot.img`, adds `AUTOEXEC.BAT`: `CTTY AUX` + `SYS B:`.
2. Creates blank FAT12 `out/floppy-sys-target.img` with `dd` + `mformat -f 1440`.
3. Boots QEMU with A: = boot img, B: = target img; checks COM1 for `"System transferred"`.
4. Adds `AUTOEXEC.BAT` (`CTTY AUX` + `VER`) to target via `mcopy -o` on the host.
5. Boots QEMU from target img alone; checks COM1 for `"MS-DOS"`.

Key notes:
- `cache=writethrough` on QEMU floppy drives ensures B: writes are flushed to the file before QEMU is killed by `timeout`.
- SYS.COM is built from `CMD/SYS/` source (BUILDMSG → CL* → MASM → LINK → EXE2BIN) and included on the floppy image.
- FORMAT.COM is built from `CMD/FORMAT/` source (BUILDMSG → CL* → MASM × 7 → LINK → CONVERT). Uses `CONVERT.EXE` (not EXE2BIN) to produce COM. MSFOR.ASM needs `BOOT.CL1` copied from `BOOT/` dir (`include BOOT.CL1`) and `BOOT11.INC` from `INC/`.
- FC.EXE has no SKL/BUILDMSG — uses its own `MESSAGES.ASM` (not the system message framework). Requires `INC/KSTRING.OBJ` compiled from `INC/KSTRING.C` (referenced as `..\..\inc\kstring.obj` in the LNK file). 5 C files + 7 ASM files, stays EXE.
- FDISK.EXE is the most complex CMD utility: NOSRVBLD (FDISK5.SKL→CL1, already done for SELECT), BUILDMSG (FDISK.SKL→CTL+CL files), MENUBLD (FDISK.MSG + USA-MS.MSG → FDISKM.C), 20 C files compiled with `-AS -Os -Zp -I. -I..\\..\\H -c`, 4 ASM files (_MSGRET, _PARSE, BOOTREC, REBOOT), linked against MAPPER.LIB + INC/COMSUBS.LIB. FDBOOT.OBJ and FDBOOT.INC reused from the SELECT build.
- MEM.EXE is built from `CMD/MEM/` source (BUILDMSG → CL + 2 MASM → LINK against `LIB/MEM.LIB`). Output stays as EXE — no CONVERT needed. MEM.EXE calls `sysloadmsg` which checks for DOS 4.0; it exits with "Incorrect DOS version" under kvikdos (which reports an older version) — this is expected, it works fine on the real floppy.
- DEBUG.COM is built from `CMD/DEBUG/` source (BUILDMSG → 11 MASM files → LINK → CONVERT). Unlike CHKDSK, BUILDMSG generates all CL files including CL1/CL2 — no empty stubs needed. DEBMES.ASM includes `SYSVER.INC` (local to DEBUG dir) and `sysmsg.inc`/`msgdcl.inc` from INC/.
- MODE.COM: 16 ASM modules, 4 SKL classes (1/2/A/B). EXE2BIN. Handles serial/parallel/display/codepage. Standard AINC, no external libraries.
- IFSFUNC.EXE: 10 ASM modules, 3 SKL classes (1/2/A). Links 5 INC kernel objs (NIBDOS/CONST2/MSDATA/MSTABLE/MSDOSME) plus 2 DOS objects (MSDISP.OBJ/MSCODE.OBJ from DOS/ dir — already built by `dos` target). Stays EXE (resident IFS driver). MSDOS.CL1 step in original MAKEFILE not needed since DOS/INC targets already built it.
- GRAPHICS.COM: 13 ASM modules, `:util GRAPHICS` with CLA/CLB/CLC + CL1/CL2. .EXT files are regular ASM include headers. Key quirk: GRCPSD.OBJ is assembled from GRPARSE.ASM and GRPARSE.OBJ from GRCPSD.ASM (filenames swapped in repo — GRPARSE.ASM's TITLE says "GRLOAD.ASM"). GRCOLPRT.ASM includes GRCOMMON.ASM directly via `INCLUDE`. GRAPHICS.PRO (printer profile) shipped alongside GRAPHICS.COM on the floppy.
- EXE2BIN.EXE: 2 ASM (E2BINIT.ASM + DISPLAY.ASM), `:util EXE2BIN` with CLA/CLB/CL1/CL2. Link via @EXE2BIN.LNK with /DOSSEG /MAP /E flags. Stays EXE. Build produces the source version for the floppy; the build system itself still uses the pre-built exe2bin from TOOLS/ (chicken-and-egg).
- BACKUP.COM: 1 large C file + 2 ASM, `-AS -Od -Zp` (debug opts). Link: `/NOE BACKUP+_PARSE+_MSGRET,,,MAPPER+COMSUBS;` → CONVERT. BUILDMSG generates CL1/CL2/CLA.
- RESTORE.COM: 12 C files + 2 ASM, same flags/pattern as BACKUP. LNK uses `/STACK:50000`. Link via @RESTORE.LNK → CONVERT.
- GRAFTABL.COM: 10 ASM, no external libs, EXE2BIN. BUILDMSG generates CL1/CL2/CLA (no stubs needed).
- KEYB.COM: 10 ASM, no external libs, EXE2BIN. BUILDMSG generates CL1/CL2/CLA. Handles keyboard layout via INT 9/9C/2F/48 handlers; data tables in KEYBTBBL.ASM/KEYBI9.ASM/KEYBI9C.ASM.
- SHARE.EXE: 4 ASM + INC kernel objs (NIBDOS, CONST2, MSDATA, MSDOSME — same as JOIN/SUBST). BUILDMSG generates CL1/CL2/CLA. Link via @SHARE.LNK. Stays EXE (TSR file-sharing/locking).
- APPEND.EXE: 1 ASM file (no SKL/BUILDMSG), `link APPEND;`. Stays EXE.
- RECOVER.COM: 4 ASM files, no SKL. Linked then CONVERT to COM.
- FASTOPEN.EXE: 5 ASM files (no SKL), `link FASTOPEN+FASTOPC+FASTOPM+FASTOPS+FASTOPN;`. Stays EXE.
- PRINT.COM: 4 ASM files, no SKL. Linked then CONVERT to COM.

## CONVERT.EXE COM Runtime Environment

**All** of CHKDSK, RECOVER, EDLIN, PRINT, FORMAT, DEBUG, RESTORE, and BACKUP are built
with `CONVERT.EXE` (not `EXE2BIN`). Any modification to these tools must account for the
runtime environment CONVERT creates:

**How CONVERT works:** Wraps the linked EXE in a COM file with a 3-byte JMP at offset 0 that jumps to
CONVERT's own init code (appended at the END of the COM file). The init code:
1. Gets current IP via `CALL $+3; POP BX` (position-independent)
2. Reads relocation offsets from the COM header (around bytes 0x116–0x128)
3. Computes runtime segment addresses and patches far-jump targets in the init code itself
4. Copies code/data to final memory location
5. Does a **FAR JMP** to the actual EXE entry point

**CONVERT COM file layout** (verified on RECOVER.COM, CHKDSK.COM, etc.):
- COM byte 0–2: `E9 xx xx` — NEAR JMP to CONVERT init code at end of file
- COM byte 3–0xF: `"Converted\0"` marker + padding
- COM byte 0x10: embedded MZ EXE header starts here (512 bytes = 0x200 for these tools)
- COM byte 0x210 (= 0x10 + header_size): actual EXE data starts here
- True COM entry = `EXE_data_offset + EXE_IP` (e.g. RECOVER: 0x210 + 0x136F = 0x157F)

**MAP vs COM offset:** The `.MAP` file shows `Program entry point at 0000:NNNN` — this is the
EXE IP, NOT the COM file byte offset. To find the actual byte where execution begins in the COM
file: `COM_entry = 0x210 + EXE_IP` (for tools with the standard 512-byte header). Confirmed by
parsing the embedded MZ header: `header_paras * 16 = 0x200`, data offset `= 0x10 + 0x200 = 0x210`.

**Analyzing COM binaries:** `objdump` can disassemble raw COM/EXE bytes (`-b binary -m i8086`),
but for CONVERT COM files it doesn't understand the embedded MZ structure. Python is more flexible
for: (1) parsing OMF OBJ segment/symbol tables to verify code placement, (2) locating the embedded
MZ header and computing true entry offsets, (3) searching for byte patterns across segments.

After the FAR JMP: **CS = the EXE's code segment (DG or similar), not PSP**.

**Implications for any code modification:**
- `OFFSET label` gives the assembler's DG-relative value. At runtime CS=DG, so `CS:[DG_offset]`
  is valid. But DS is NOT PSP — do not use DS:[81h] to access the command line.
- PSP is still accessible via `INT 21h / AH=62h` (returns BX=PSP segment).
- For position-independent string addresses: use the `CALL/POP` trick — CALL pushes the
  runtime IP of the next byte (the string start), bypassing DG-relative OFFSET entirely.
- `PUSH CS; POP DS` sets DS=DG (CS at runtime), so `DS:DX` from CALL/POP is correct for
  INT 21h/09h string output.

**SHORT-jump range:** MASM 5.x conditional jumps (`JNE`, `JE`) are always SHORT (±127 bytes).
Use a relay: `JNE short_relay_label; [long code block]; short_relay_label: JMP NEAR far_target`.
Unconditional `JMP far_target` auto-promotes to NEAR (3 bytes) across MASM's two passes.

**Proven pattern for /? (implemented in PRINT, applicable to CHKDSK/RECOVER/EDLIN):**
```asm
   MOV   AH, 062H
   INT   21H          ; BX = PSP segment
   MOV   ES, BX       ; ES = PSP
   MOV   SI, 081H
SKIP_SP: CMP BYTE PTR ES:[SI],' ' | JNE CHK_SL | INC SI | JMP SHORT SKIP_SP
CHK_SL:
   CMP   BYTE PTR ES:[SI], '/'
   JNE   NO_HELP          ; SHORT (target right below)
   CMP   BYTE PTR ES:[SI+1], '?'
   JE    DO_HELP           ; SHORT (target right below — 3 bytes past JMP)
NO_HELP:
   JMP   CONTINUE          ; NEAR unconditional — skips the whole help block
DO_HELP:
   CALL  HELP_END          ; pushes runtime addr of string, jumps to HELP_END
HELP_STR DB "...$"
HELP_END:
   POP   DX               ; DX = runtime CS-relative address of HELP_STR
   PUSH  CS | POP DS      ; DS = CS = DG
   MOV   AH, 09H | INT 21H
   MOV   AX, 4C00H | INT 21H
CONTINUE:
   ; original entry code
```

- FILESYS.EXE: 1 C file + 2 ASM, no SKL. Link: `link FILESYS+_PARSE+_MSGRET; /NOI` (note space before `/NOI`). Stays EXE.
- REPLACE.EXE: 1 C + 3 ASM, BUILDMSG for SKL. Links MAPPER.LIB + INC/COMSUBS.LIB. Stays EXE.
- JOIN.EXE / SUBST.EXE: 1C + 2ASM + INC kernel objects (ERRTST.OBJ, SYSVAR.OBJ, CDS.OBJ, DPB.OBJ already built by `inc` target). Links MAPPER.LIB + INC/COMSUBS.LIB. LNK files reference INC objs by relative path `..\..\inc\*.OBJ`. Stays EXE.
- CHKDSK.COM is built from `CMD/CHKDSK/` source (BUILDMSG → 9 MASM files → LINK → CONVERT). Key quirk: `CHKDISP.ASM` uses the `Msg_Services` macro which includes `CHKDSK.CL1` and `CHKDSK.CL2` — but CHKDSK.SKL has no class 1 or 2, so BUILDMSG doesn't generate them. Fix: `touch CHKDSK.CL1 CHKDSK.CL2` after BUILDMSG to create empty stubs. CHKDSK also uses `CONVERT.EXE` (not EXE2BIN).
- FORMAT.COM is tested via `test_format.sh` — see "## FORMAT E2E Tests (QMP disk swapping)" section below.
- FORMAT internal/OEM switches (`/BACKUP /SELECT /AUTOTEST /Z`) — see "## FORMAT Internal/OEM Switches" section.

## Floppy Image (deploy / verify)

### MSBOOT.BIN layout
- EXE2BIN produces a flat binary with code ORG'd at `0x7c00`; file is 32256 bytes (= 0x7c00 padding + 512 bytes boot sector).
- Extract boot sector: `dd if=MSBOOT.BIN bs=1 skip=31744 count=512`.

### BPB patching (`bin/patch-bpb`)
- MSBOOT.BIN's built-in BPB targets a fixed disk (media `0xF8`); patch it to 1.44MB floppy geometry before calling `mformat -k`.
- 1.44MB parameters: 512 B/sec, 1 sec/cluster, 2 FATs, 224 root entries, 2880 total sectors, media `0xF0`, 9 sec/FAT, 18 sec/track, 2 heads.
- Extended BPB (DOS 4.0): drive `0x00` (floppy), ext_boot_sig `0x29`, volume label 11 bytes, FS type `"FAT12   "`.
- BPB occupies bytes 11–61 of the boot sector; bootstrap code starts at byte 62 (`0x3E`).

### mformat -k
- `mformat -i floppy.img -k ::` — formats FAT12 *keeping* the existing boot sector (reads BPB from it to build consistent FAT tables).

### File copy order
- `IO.SYS` **must** be the first directory entry; `MSDOS.SYS` must be second.
- Use `mcopy` (not loop-mount) to guarantee insertion order; then `mattrib +h +s +r` both files.

### verify target
- `floppy-test.img` = `floppy.img` + `AUTOEXEC.BAT` with `CTTY AUX\r\nVER\r\n`.
- `CTTY AUX` redirects DOS console to COM1; `VER` prints `MS-DOS Version 4.00` to COM1.
- QEMU flags: `-display none -serial file:out/serial.log`; `timeout 15` kills QEMU after output is captured.
- Pass condition: `grep -q "MS-DOS" out/serial.log`.

## CI (GitHub Actions)

- **Submodule pointer pitfall:** When committing changes to both the submodule and
  `tests/` (golden.sha256, run_tests.sh), always `git add MS-DOS` in the parent repo too.
  If only `tests/` is staged, CI will check out the OLD submodule commit and fail the
  smoke tests because the new binaries are missing. Verify with `git ls-tree HEAD MS-DOS`
  and confirm the hash matches the submodule's latest commit before pushing.
- Workflow: `.github/workflows/ci.yml`, runs on every push/PR to `master`.
- Runner: `ubuntu-latest` with pre-built Docker container image (`ghcr.io/<repo>/ci:latest`).
- KVM fix: `chmod 666 /dev/kvm` in the container.
- Steps: grant KVM → build kvikdos → `make` → `make test` → `make deploy` → upload floppy artifact → parallel e2e jobs: `test_sys.sh`, `test_help_qemu.sh` (includes EXEPACK verification).
- Free tier: unlimited minutes for public repos on GitHub Actions.
- kvikdos now builds and runs on macOS via software 8086 CPU backend (XTulator).
  Linux CI uses KVM (unchanged); macOS builds use the same codebase with `#ifdef __linux__` guards.

## MS-DOS Fork Branch Strategy

The MS-DOS submodule (`MS-DOS/`) has three branches:
- `main` — minimal patches to make the source build (CRLF fixes, UTF-8, `.gitattributes`).
  Stays close to the original Microsoft source.
- `dos4-enhancements` — our additions (help strings, bug fixes, etc.). Branches off `main`.
  This is the active development branch.
- `watcom-migration` — migration to Open Watcom V2 (native Linux toolchain). Branches off
  `dos4-enhancements`.

Workflow: develop on `dos4-enhancements`; merge upstream changes into `main` first,
then rebase `dos4-enhancements` on top. Watcom work happens on `watcom-migration`.

## Adding /? Help Strings to CMD Tools

### General pattern (external tools)
- **C tools** (`argv`-based): check `argv[1]` for `"/?"`; `printf` the help string; `exit(0)`. Add `#include <stdio.h>` and `#include <stdlib.h>` if not already present.
- **ASM EXE tools** (DS=PSP at entry): scan `DS:[81H]`, skip spaces/tabs, check `'/'` then `'?'`; `PUSH CS / POP DS` to reach help string in code segment; `INT 21H/09H` to print; `INT 21H/4CH` to exit.
- **COM tools** (CS=DS=PSP): same as ASM EXE but no `PUSH CS / POP DS` needed — CS already equals DS.
- **CONVERT COM tools** (CS=DG, not PSP): use `INT 21H/62H` → ES=PSP, check `ES:[81H]`; `CALL HELP_END / DB "...$" / HELP_END: POP DX; PUSH CS / POP DS; INT 21H/09H` (CALL/POP trick for position-independent string address). See detailed example under "## CONVERT.EXE COM Runtime Environment".

### COMMAND.COM built-in /? pattern
- **`fSwitchAllowed` flag** (TDATA.ASM COMTAB): bit 1 must be set or the dispatcher rejects `/` as "Invalid switch" before the handler is called. Commands with flag `0` need it changed to `fSwitchAllowed`.
- **Handler entry**: DS=CS=TRANGROUP. Scan `DS:[81H]` (command tail set up by `cmd_copy`), skip spaces/tabs, check `'/'` then `'?'`.
- **Print**: `MOV DX, OFFSET TRANGROUP:HELP_STR; MOV AH, 09H; INT int_command`. No `PUSH CS / POP DS` needed — DS already equals CS at handler entry.
- **Exit**: `return` (maps to `ret`; dispatcher uses `call BX` so `ret` returns correctly).
- **REM special case**: REM was mapped directly to `TCOMMAND` (not a callable handler). Fix: new `REM_HANDLER` proc in TCODE.ASM that checks `/?` and `return`s, or `jmp TCOMMAND` for normal REM. Add `PUBLIC REM_HANDLER` + `EXTRN REM_HANDLER:NEAR` in TDATA.ASM.
- **Help string placement**: place `DB "...$"` data only where execution cannot fall through — after a `ret`/`return`, or after an unconditional `jmp`. Never between two executable labels unless preceded by `jmp`.
- **Short-jump range**: MASM 5.x conditional jumps (`JZ`, `JNZ`, etc.) are always ±127 bytes. A large help string (e.g., FOR_HELP_STR = 284 bytes) placed before a handler's body pushes all backward jumps to labels before the string out of range. Fix: move the string to *after* a `jmp` that exits the flow; or add relay labels (`JNZ short_relay; JMP far_target; short_relay:`).

### pipefail / SIGPIPE fix in run_tests.sh
Capture `strings` output into a variable first, then grep — avoids SIGPIPE false negative under `set -o pipefail`:
```bash
bin_str=$(strings "$SRC/CMD/COMMAND/COMMAND.COM")
if echo "$bin_str" | grep -q "$expected"; then ...
```
Direct pipeline `strings ... | grep -q ...` can cause SIGPIPE when grep exits early, which `pipefail` treats as a failure.

## kvikdos Emulation Notes (for running MS-DOS 4.0 tools)

### DOS version
- kvikdos upstream default is version 5. MS-DOS 4.0 tools call `sysloadmsg` which checks
  for DOS 4.x via INT 21h/AH=30h; getting 5 causes "Incorrect DOS version" exit.
- **Fix:** use `--dos-version=4` flag (added to kvikdos fork). `bin/dos-run` passes it
  automatically so all tools work correctly.

### INT stubs added to kvikdos fork (needed for functional MS-DOS 4.0 tool testing)
| INT / Function | Purpose | kvikdos behavior |
|---|---|---|
| INT 21h/AH=65h | GetExtendedCountryInfo (NLS) | Returns identity collating table (0x0420) and country_info (0x0522); handles AL=01h–07h,20h–23h. Needed by `sysloadmsg`, XCOPY (capitalize). |
| INT 21h/AH=43h | Get/set file attributes | GET returns attrs in CX (archive+readonly from chmod). SET maps DOS readonly to chmod. Needed by ATTRIB. |
| INT 21h/AH=6Ch | Extended open/create (DOS 4.0+) | DS:SI filename, BX=mode, DX=action flags. Needed by EDLIN, REPLACE, XCOPY. |
| INT 21h/AH=26h | Create new PSP (legacy) | Copies current PSP to DX segment. Needed by DEBUG.COM. |
| INT 21h/AH=50h/51h | Set/Get PSP address | Tracks `current_psp_para` variable. Needed by DEBUG.COM. |
| INT 21h/AH=44h/AL=09h | IOCTL: block device remote check | Returns DX=0 (local). Needed by LABEL.COM. |
| INT 21h/AH=44h/AL=0Ch | IOCTL: generic char I/O | No-op stub. Needed by MORE.COM. |
| INT 21h/AH=35h whitelist | Get interrupt vector | Extended: INT 01/02/03 (DEBUG), INT 21/25/26 (ASSIGN), INT 2F (GRAFTABL). |
| INT 2Fh/AH=06h | ASSIGN installation check | Returns AL=0 (not installed). Needed by ASSIGN /STATUS. |
| INT 2Fh/AH=B7h | APPEND (any sub-function) | Returns AX=BX=0 (not installed). Needed by TREE.COM. |
| INT 12h | BIOS Get Conventional Memory Size | Returns AX=640 (KB). Needed by MEM.EXE. |
| INT 15h/AH=C1h | Get EBDA Segment | Returns CF=1 (no EBDA). Needed by MEM.EXE. |
| INT 67h/AH=40h..62h | EMS functions | Returns AH=0x86 (EMM not present). Needed by MEM.EXE EMS check. |
| INT 21h/AH=87h | GETPID (MS-DOS 4.0 multitasking) | Returns PID=1, parent PID=0. MS C 5.10 `getpid()` calls this during compilation. |
| INT 21h/AH=33h/AL=03h | Get boot drive | Returns DL=3 (C:). Needed by FIND.EXE. |
| INT 21h/AH=69h | Get disk serial number (DOS 4.0+) | Returns dummy serial 0x67452301, volume "NO NAME", FS "FAT12". Needed by TREE.COM. |
| MMIO INVARS region | List of Lists (INT 21h/52h) | MCB chain pointer + NUL device header with FFFF:FFFF terminator. Needed by MEM.EXE. |
| MMIO 0xA0000–0x110000 reads | High memory / ROM area | Returns zeros. Needed for MEM.EXE reading INVARS ExtendedMemory via segment 0xFFF0. |

### Static data placed in low-memory readonly region (re-initialized on each run)
- **0x0420..0x0521** — identity collating table (word 0x0100 = 256 length + 256 identity bytes). Used by INT 21h/AH=65h.
- **0x0522..0x0539** — country_info copy (0x18 bytes). Used by INT 21h/AH=65h/AL=01h.
- These addresses are in the KVM readonly-guest slot (0x0000..0x0FFF), safely between the BIOS data area and the hlt table (0x0540).

### E2E functional test status (Section 6, kvikdos)
- **MEM.EXE**: runs, prints correct memory report, exits non-zero (C runtime artifact — ignored).
- **FIND.EXE**: works with file arguments. Stdin mode unreliable under kvikdos. Full option coverage (basic, /V, /C, /N) tested via QEMU in `test_builtins.sh`.
- **FC.EXE**: works — all major modes tested (identical, different, /N, /B, /C, /W, /L).
- **TREE.COM**: works — shows "Directory PATH listing". kvikdos doesn't expose subdirectories via FindFirst/FindNext, so tree is flat. /F mode also tested.
- **SORT.EXE**: works — sorts stdin lines correctly, /R (reverse) and /+N (column sort) tested. Was blocked by "Insufficient memory" until build was fixed to include `exefix sort.exe 1 1` (sets MAXALLOC=1 so INT 21h/48h malloc has free memory).
- **COMP.COM**: works — identical files ("Files compare OK") and different files ("different sizes") tested. Uses `timeout 5` with piped `/dev/null` to avoid interactive Y/N loop at EOF.
- **ATTRIB.EXE**: works — show attributes, +R (set read-only), -R (clear read-only) tested. +A/-A (archive) cannot be tested under kvikdos — only read-only is mapped to Unix chmod; archive/hidden/system are silently ignored (kvikdos.c INT 21h/43h handler).
- **MORE.COM**: works — piped stdin pagination tested.
- **DEBUG.COM**: works — launch+quit (`-` prompt) and register dump (`R` command) tested. Required INT 21h/26h (Create PSP), /50h (Set PSP), INT 01/02/03 whitelist additions.
- **LABEL.COM**: works — show volume info tested. Write operations need FCB delete (QEMU only).
- **EDLIN.COM**: works — open existing file + list, open new file tested. Insert mode can't be tested via pipe (Ctrl+C handling). Needs INT 21h/6Ch (Extended Open/Create).
- **REPLACE.EXE**: /A (add mode) works. Basic replace fails (needs wildcard FindFirst on absolute paths).
- **XCOPY.EXE**: launches but copies 0 files under kvikdos. No-args error message tested.
- **GRAFTABL.COM**: /STATUS, 437, 850 all work. /STATUS prints "Active Code Page: None"; 437/850 load the code page and print "Active Code Page: NNN" (crashes after on INT 1F set-vector, but output is correct on stdout).
- **SUBST.EXE**: no-args (list substitutions) works — silent exit 0.
- **JOIN.EXE**: no-args (list joins) works — silent exit 0.
- **ASSIGN.COM**: /STATUS works — silent exit 0. No-args (clear assignments) is TSR operation, fails.

### QEMU /? help test status (`make test-help-qemu`)
27 external CMD tools tested with /? on real DOS (single QEMU boot). All 27 print
correct help text — both C-based tools (argv pattern) and ASM-based tools (PSP check)
work identically under real DOS and kvikdos. Skipped: TSRs (NLSFUNC, SHARE, APPEND,
PRINT, GRAPHICS, FASTOPEN), interactive (DEBUG, EDLIN), filters (MORE, SORT).

## DISKCOPY / DISKCOMP Two-Drive QEMU E2E Patterns

### Prompt sequencing
Two-drive (A:≠B:) DISKCOPY flow per invocation:
1. "Insert SOURCE diskette in drive A:" — display only, no wait
2. "Insert TARGET diskette in drive B:" — display only, no wait
3. `PRESS_ANY_KEY`: `CLEAR_BUF` (INT 21h/AH=0Ch) + `KEY_IN` — any single char accepted
4. Copy tracks, print "Copying %1 tracks / %2 Sectors/Track, %3 Side(s)"
5. "Copy another diskette (Y/N)?" — `CLEAR_BUF` + `KEY_IN_ECHO` — **must feed 'N', not bare CR** (bare CR is not a valid Y/N response)

DISKCOMP flow is similar: INSERT FIRST/SECOND messages (no wait) → `PRESS_ANY_KEY` → compare → result → "Compare another diskette (Y/N)?".

**Test feed:** `(while true; do sleep 0.2; printf 'N\r\n'; done)` satisfies both PRESS_ANY_KEY (any char) and Y/N prompts, because `CLEAR_BUF` flushes the type-ahead buffer before each read.

### Key quirks
- **"Copy process ended" (msg 21) = MSGNUM_FATAL_ERROR** — printed ONLY on fatal errors (e.g., unformatted disk that DISKCOPY cannot format). NOT printed on success. Success goes directly to "Copy another diskette (Y/N)?". Do NOT use "Copy process ended" as a success oracle.
- **DISKCOPY /V is unimplemented**: `VERIFY_FUNC EQU 62H` is defined in `DISKCOPY.EQU` and appears in help text, but never called in `DISKCOPY.ASM`. `DCOPYPAR.ASM` defines only one switch descriptor: `/1`. SYSPARSE rejects `/V` as unknown → "Invalid switch - /V". Test oracle: grep for "Invalid switch".
- **DISKCOPY /1**: Sets `NO_OF_SIDES=0` at `CS_OPTION_1` in `CHECK_SOURCE` → `MSG_SIDES=1` → output says "1 Side(s)". Test oracle: grep for "1 Side(s)".
- **FORMAT_FLAG**: Only set on IOCTL hard write failure. A mformatted B: disk passes IOCTL writes directly → FORMAT_FLAG never set → "Formatting while copying" (msg 7) never printed for mformatted targets.
- **DISKCOMP compare errors**: `EXITFL` is never set when compare errors occur → errorlevel always 0 even on mismatches. Test oracle is "Compare error on" text in serial log, not errorlevel.
- **Mismatch test**: After DISKCOPY A:→B:, write a file to A: with `ECHO DISKTEST > DISKTEST.TXT`. This changes FAT + directory + data sectors on A:. DISKCOMP A: B: then finds "Compare error on" on those sectors.

## SHARE / NLSFUNC / EXE2BIN TSR and Tool Behaviors

### SHARE
- **First call**: installs silently as TSR (INT 2Fh hook + INT 21h/31h Keep_Process). No output.
- **Second call**: INT 2Fh check returns AL=0FFh (already loaded) → `ShDispMsg` prints "SHARE already installed" → `ShDispMsg` calls `INT 21h/AH=4Ch/AL=0FFh` → exits with **errorlevel 255**.
- `ShDispMsg` always calls INT 21h/4Ch after printing — the batch continues after errorlevel 255 exits.

### NLSFUNC
- **First call (no args)**: NO_PARMS=1 → installs silently via INT 2Fh + Keep_Process. COUNTRY.SYS is NOT opened at install time.
- **Second call**: INT 2Fh/AH=MULT_NLSFUNC check returns AL≠0 → "NLSFUNC already installed" printed to **STDERR** (handle 2, via `bx=STDERR` in SYSDISPMSG call). ERROR_CODE=80h → exits with **errorlevel 128**.
- **STDERR routing**: `CTTY AUX` only redirects handles 0 (stdin) and 1 (stdout). STDERR (handle 2) is unaffected. "NLSFUNC already installed" message does NOT appear on COM1 serial output — verify via errorlevel check only.

### EXE2BIN
- **Always exits errorlevel 0** (`xor al,al; Dos_call Exit` at end of `E2BINIT.ASM` regardless of path).
- **IP=0 → BINFIX path**: binary conversion, no "Fix-ups needed" prompt. Test oracle: `IF EXIST outputfile`.
- **IP=0x100 → COM path**: same (no prompts).
- **IP≠0 + relocations → interactive**: prompts "Fix-ups needed - base segment (hex):" — can't automate.
- **File not found**: DosError → INT 21h/AH=59h extended error → `extend_message` → SYSDISPMSG → `$M_GET_MSG_ADDRESS` → "File not found" printed. Still exits errorlevel 0.
- **SYSDISPMSG quirk**: SYSLOADMSG calls `$M_GET_DBCS_VEC` (INT 21h/AH=63h) during init. Without a valid DBCS table, the message retriever corrupts memory and infinite-loops in `$M_GET_MSG_ADDRESS`. kvikdos DBCS fix (returning empty table at 0x053A) resolved this.
- **Source-built vs pre-built**: CMD/EXE2BIN/EXE2BIN.EXE (8KB, source-built) still hangs in SYSDISPMSG error path — different MSGSERV linkage from TOOLS/EXE2BIN.EXE (3KB, pre-built) which works. The kvikdos E2E error test uses TOOLS/ version.
- **Minimal test EXE** (33 bytes, IP=0, BINFIX path):
  ```bash
  printf '\115\132\041\000\001\000\000\000\002\000\000\000\377\377\000\000\000\000\000\000\000\000\000\000\034\000\000\000\000\000\000\000\303' \
      | mcopy -o -i "$BOOT_IMG" - ::TEST.EXE
  ```
  Layout: MZ header (28 bytes) + 4-byte pad = 32-byte header (e_cparhdr=2 paragraphs); e_ip=0, e_crlc=0, e_cp=1, e_cblp=33; 1 byte code (0xC3 RET).

## FORMAT Internal/OEM Switches

FORMAT has several switches beyond the public ones (`/V /S /B /1 /4 /8 /T /N /F`).
These are registered in SYSPARSE (`FORPARSE.INC`) so they **can be passed on the command line** —
they are intentionally omitted from the `/? ` help text.

| Switch | SYSPARSE | What it does |
|--------|----------|--------------|
| `/BACKUP` | yes | Suppresses the "Insert new diskette" prompt. Called by `BACKUP.COM` when it spawns FORMAT to pre-format the target disk. |
| `/SELECT` | yes | Called by `SELECT.EXE`. Suppresses all interactive prompts; on write-protect or not-ready errors sets `ExitStatus` errorlevel instead of displaying a message. |
| `/AUTOTEST` | yes | Same prompt-suppression as `/SELECT` (both checked together throughout FORMAT). Used for automated/test invocations. |
| `/Z` | yes (ShipDisk only) | Sets 1 sector/cluster in the BPB — a special geometry for the "ShipDisk" build variant. Only compiled when `ShipDisk` is defined; absent in standard builds. |
| `/C` | removed | Was dead code — had a bit in `FORSWTCH.INC` and checks in `MSFOR.ASM`/`FORMAT.ASM` but no parser control block in `FORPARSE.INC`. SYSPARSE always rejected it. Removed in `555b065`. |

## FORMAT E2E Tests (QMP disk swapping)

### Prompt sequence (FORMAT.SKL verified)
1. msg 7: "Insert new diskette for drive B:" — display only, no wait
2. msg 28 (ContinueMsg): "and press ENTER when ready..." — waits via USER_STRING (reads one CR-terminated line)
3. Format runs, prints `%1 percent of disk formatted` (CR overwrites same line)
4. msg 4: "Format complete" (CR,LF — stays visible)
5. msg 30: "System transferred" (only for /S, via COMMON30)
6. COMMON35: "Volume label (11 characters, ENTER for none)?" — waits for input; skipped if /V:label given on command line
7. msg 46: "Format another (Y/N)?" — reads one char; anything except Y/y exits

**Feed:** continuous `\r\n` satisfies all waits. CR is not Y/y so FORMAT exits at "Format another?".

### QMP disk swapping — single QEMU boot for all 8 FORMAT variants
Instead of 8 separate QEMU boots (which would take ~12 min), all FORMAT variants run in one QEMU session. After each FORMAT completes:
1. Background bash process detects DONE marker via a named FIFO + `stdbuf -oL tee`
2. Copies the current B: image to a saved path (image is already flushed due to `cache=writethrough`)
3. Sends QMP command: `{"execute":"human-monitor-command","arguments":{"command-line":"change floppy1 <path>"}}` via Python3 + Unix socket
4. QEMU's floppy emulation sets the disk-change line; DOS detects the new medium on the next B: access

**stdbuf -oL:** forces line-buffering on `tee`'s stdout so the FIFO reader sees each line immediately (without it, tee buffers 4 KB and the swapper would miss DONE markers until QEMU exits).

**QEMU startup flag:** `-qmp unix:$QMP_SOCK,server,nowait` — creates QMP socket without blocking.

**Timing:** After DONE marker appears, host has ~1 second before next FORMAT accesses B: (DOS reads the next batch lines + loads FORMAT.COM from A: floppy). QMP swap takes ~150 ms. Plenty of margin.

### BPB geometry verification (Python3)
Post-QEMU: read BPB from each saved image at fixed offsets (boot sector bytes):
- `0x18-0x19`: sectors per track
- `0x1A-0x1B`: number of heads
- `0x13-0x14`: total sectors 16-bit (use `0x20-0x23` 32-bit if this is 0)

Expected values per variant:
| Switch | spt | heads | total |
|--------|-----|-------|-------|
| default (1.44MB) | 18 | 2 | 2880 |
| /F:720 | 9 | 2 | 1440 |
| /T:80 /N:9 | 9 | 2 | 1440 |
| /4 (360K on 1.2MB) | 9 | 2 | 720 |
| /1 (single-sided) | 18 | 1 | — |
| /8 | 8 | 2 | — |

The /4 test uses a 2400-sector target image (1.2MB) — QEMU auto-detects drive type from image size.

### Volume label
`mlabel -i img -s ::` reads the label from the FAT12 root directory / BPB. For /V:TEST, grep output for "TEST".

## Interactive QEMU Tests — serial_expect.py Pattern

### Problem
Programs like LABEL, XCOPY /P, REPLACE /P, FDISK prompt the user mid-execution.
`-serial stdio` with a uniform `\r\n` or `N\r\n` feed cannot send DIFFERENT characters
at different prompts (e.g., ENTER to clear the label field, then Y to confirm deletion).

### Solution: serial pipe + Python expect coordinator
Use `-serial pipe:<prefix>` instead of `-serial stdio`.  QEMU creates:
- `<prefix>.in`  — QEMU reads serial input from this FIFO (host → DOS)
- `<prefix>.out` — QEMU writes serial output to this FIFO (DOS → host)

`tests/serial_expect.py` acts as an expect-like coordinator:
1. Opens `.in` for writing, `.out` for reading
2. Scans raw byte buffer for each pattern in order
3. When pattern is found, writes the corresponding response to `.in`
4. Exits on EOF (QEMU exits / pipe closes)

### FIFO open deadlock prevention
`mkfifo serial.in serial.out` creates blocked FIFOs (open blocks until both ends open).
Fix: `exec 3<>"$SERIAL_IN"` in bash opens `.in` with O_RDWR (both ends in one fd).
This ensures QEMU's O_RDONLY open of `.in` doesn't block (write-end already exists).
Python's O_WRONLY open of `.in` also doesn't block for the same reason.
Python's O_RDONLY open of `.out` blocks until QEMU opens `.out` for O_WRONLY — they
unblock each other since QEMU is running in background at that point.
Close the bash fd after the coordinator exits: `exec 3>&-`.

### Template (bash)
```bash
mkfifo "$SERIAL_IN" "$SERIAL_OUT"
exec 3<>"$SERIAL_IN"    # O_RDWR trick

timeout 120 qemu-system-i386 \
    ... \
    -serial pipe:"$OUT/foo-serial" \
    2>/dev/null &
QEMU_PID=$!

python3 "$REPO_ROOT/tests/serial_expect.py" \
    "$SERIAL_IN" "$SERIAL_OUT" "$SERIAL_LOG" \
    "prompt text 1" $'response1\\r\\n' \
    "prompt text 2" $'Y\\r\\n'

wait $QEMU_PID || true
exec 3>&-
```

### Prompt text notes
- Prompts often end with `? ` (no `\n`). serial_expect.py scans raw bytes, not lines — works fine.
- `CTTY AUX` redirects DOS handle 0 (stdin) and 1 (stdout) to COM1 = the serial pipe. Interactive programs using INT 21h for I/O go through COM1.
- SYSDISPMSG Y/N reads (INT 21h passthrough) also go through COM1 when CTTY AUX is active.

### LABEL remove (implemented in test_label.sh)
Prompts:
- COMMON35: `"Volume label (11 characters, ENTER for none)? "` — response: `\r\n`
- msg 9: `CR,LF,"Delete current volume label (Y/N)? "` — response: `Y\r\n`
Y/N logic: Y → delete (does NOT set NO_DELETE flag), N → keep (sets NO_DELETE).

## BACKUP / RESTORE Interactive Prompts

BACKUP.COM has `display_it(..., WAIT)` calls (not `wait_for_keystroke()`) embedded
in the `display_msg()` switch for these message codes:

| Message | Condition | Waits? |
|---------|-----------|--------|
| INSERTSOURCE (msg 25) | source is a floppy | always — 1 wait |
| INSERTTARGET (msg 26) | target used, not /A | 1 wait |
| ERASEMSG (msg 20) | target used, not /A | 1 wait |
| LASTDISKMSG (msg 28) | /A first target | 1 wait |
| FERASEMSG (msg 21) | hardfile target has existing backup | 1 wait |

Total keypresses per BACKUP call to a floppy target:
- Normal (not /A): 3 (INSERTSOURCE + INSERTTARGET + ERASEMSG)
- /A first disk: 2 (INSERTSOURCE + LASTDISKMSG)
- No files found: 1 (INSERTSOURCE only — `get_diskette()` never called)

`format_target()` in `get_diskette()` calls FORMAT.COM only if `disk_free_space()`
fails (unformatted disk). A mformatted B: passes the check → no FORMAT spawned.

**Test approach:** feed continuous `\r\n` through `-serial stdio` via a subshell
(`while true; do sleep 0.2; printf '\r\n'; done`). COMMAND.COM reads batch
commands from the .BAT file (not stdin), so extra buffered newlines are harmless.

RESTORE single-disk is prompt-free (`NO_RESPTYPE` on all messages except the
multi-disk case at RTDO.C:358 which requires `ANY_KEY_RESPTYPE` — only triggered
when multiple backup diskettes must be swapped, not needed for single-disk tests).

## EXEPACK A20 Gate Bug

**Symptom:** "Packed file is corrupt" on real DOS hardware / QEMU when running tools
linked with Microsoft LINK 3.65 `/EXEPACK` (or `/EX`, `/E+`).

**Root cause:** The EXEPACK decompressor stub embedded by LINK 3.65 has an A20 gate bug:
when the relocation fixup loop accesses memory near the 1 MB boundary (segment ~0x10000),
A20 wrap-around causes the wrong memory to be read/written, triggering the error message
that is embedded in the stub itself.

**Affected binaries (built by our Makefile):**
| Tool | Link flag | Makefile |
|------|-----------|----------|
| FIND.EXE | `/EX` | `mk/cmd.mk` |
| FDISK.EXE | `/E+` | `mk/cmd.mk` |
| IFSFUNC.EXE | `/EX` | `mk/cmd.mk` |
| EXE2BIN.EXE | `/E+` | `mk/cmd.mk` |
| SELECT.EXE | `/EXEPACK` | `mk/select.mk` |

**Why smoke tests don't catch it:** kvikdos automatically detects EXEPACK at load time
(detection: `EXE_IP ∈ {16,18,20}` AND `'RB'` signature at `EXE_IP-2`) and replaces the
buggy stub with a fixed 283-byte version from exepack-1.3.0 (see `kvikdos/kvikdos.c`
lines ~1351–1391). This means `make test` passes, but the output EXE is still broken
for real DOS.

**Fix:** `bin/fix-exepack` patches the stub in-place at build time (same logic kvikdos
does at runtime). Called automatically after each affected LINK step in the Makefile.
- Detection: `EXE_IP ∈ {16,18,20}` AND `'RB'` sig at `EXE_IP-2`
- Old stub boundary found via `\xcd\x21\xb8\xff\x4c\xcd\x21` + 22-byte error string
- New header grows 16→18 bytes: adds `skip_len=1` at offset 14, moves `'RB'` to offset 16
- References: https://www.bamsoftware.com/software/exepack/

**Lesson:** Always test on real DOS or QEMU after linking with EXEPACK. kvikdos masks
this class of bug entirely.

## COMMAND.COM /? Help — Transient Corruption Bug (FIXED)

### Root cause (found and fixed)
The `newarg` function in `PARSE2.ASM` used `jge` (signed comparison) for the argbuf
overflow check. When TRANGROUP offsets grew large enough for `arg.argbuf+ARGBLEN-1`
to reach `0x8000`, this crossed the signed boundary making the check always trigger.
All internal commands failed with "Bad command or file name".

**Fix:** `jge` → `jae` (unsigned comparison) in commit `4ed73cb`. All /? help strings
for all built-in commands are now present and working.

### History
Adding /? help strings to COMMAND.COM built-ins (commits 5d10cef + 58a0bb4) caused
all built-in commands to silently fail at runtime. Initial investigation suggested
a size boundary theory (TRANTAIL PARA alignment), but this was disproven — adding
2,300 bytes of padding to a working binary produced a larger-but-working COMMAND.COM.
The actual bug was a latent signed comparison that only manifested when the transient
segment grew past the 0x8000 offset boundary.

### How to test locally (macOS)
```bash
# Requires: brew install qemu mtools coreutils
# Build floppy image:
dd if=/dev/zero of=out/floppy-test.img bs=512 count=2880 status=none
dd if=MS-DOS/v4.0/src/BOOT/MSBOOT.BIN of=out/floppy-test.img \
   bs=1 skip=31744 count=512 conv=notrunc status=none
bin/patch-bpb out/floppy-test.img
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
echo 'drive a: file="out/floppy-test.img"' > /tmp/mtoolsrc
export MTOOLSRC=/tmp/mtoolsrc
mformat -k a:
mcopy MS-DOS/v4.0/src/BIOS/IO.SYS a:IO.SYS
mattrib +h +s +r a:IO.SYS
mcopy MS-DOS/v4.0/src/DOS/MSDOS.SYS a:MSDOS.SYS
mattrib +h +s +r a:MSDOS.SYS
mcopy MS-DOS/v4.0/src/CMD/COMMAND/COMMAND.COM a:COMMAND.COM
printf "CTTY AUX\r\nVER\r\n" > /tmp/autoexec.bat
mcopy -o /tmp/autoexec.bat a:AUTOEXEC.BAT
# Boot and check:
rm -f out/serial.log
gtimeout 15 qemu-system-i386 -display none -fda out/floppy-test.img \
   -boot a -m 4 -serial file:out/serial.log 2>/dev/null; true
cat out/serial.log  # should show "MS-DOS Version 4.00"
```

**macOS mtools note**: `mattrib -i image.img` does not work on mtools 4.0.49.
Use MTOOLSRC drive mapping instead (as shown above). Also needs `MTOOLS_NO_VFAT=1`.
`timeout` is not available on macOS — use `gtimeout` from `brew install coreutils`.

## COMMAND.COM FOR Command Hang (FIXED)

### Root cause

The `$for` handler in `TFOR.ASM` sets `ES` to `RESGROUP` via `mov ES, [RESSEG]` at
`FOR_NORM` (needed to access resident data like `ForFlag`, `SINGLECOM`). Two bugs:

1. **Error paths**: `forerrorj`, `forerrorjj`, `fornesterrj`, and `for_alloc_err`
   all jumped to `CERROR`/`TCOMMAND` without restoring `ES` to `TRANGROUP`. Since
   `TCOMMAND` uses `CALL ES:[HEADCALL]` (MASM generates ES: override because
   `HEADCALL` is in `TRANSPACE`/`TRANGROUP` and `DS` is assumed `RESGROUP`), having
   `ES=RESGROUP` caused the far call to read a garbage address from the resident
   segment instead of the real `HEADCALL` pointer. Result: bare `FOR` printed
   "Syntax error" then hung.

2. **Success path**: `for_ret` returned with `ES=RESGROUP` (popped at line 514 after
   the for-info structure was initialized). The caller (`Cmd_done`) doesn't touch ES
   before jumping to `TCOMMAND`, so the same `HEADCALL` corruption occurred on the
   first `forproc` iteration. Result: valid `FOR %%X IN (set) DO cmd` hung without
   executing any iterations.

**Fix**: Added `push cs; pop es` (restore `ES=TRANGROUP`) to all four error
trampolines and to `for_ret` before the `ret` instruction.

**Diagnostic**: `IF` (handler `$IF` in `TBATCH2.ASM`) never changes `ES`, so it
works fine through the same `CERROR` path. This proved the hang was FOR-specific,
not a general `CERROR`/`TCOMMAND` problem.

**Testing**: FOR cannot be tested under kvikdos (COMMAND.COM fails `TSYSLOADMSG`
due to version mismatch). Tested via QEMU E2E in `test_builtins.sh`: bare FOR
error recovery + valid FOR loop iteration (3 items).

## COMMAND.COM SET/PROMPT Hang (FIXED)

Same class of bug as the FOR hang. Both `ADD_NAME_TO_ENVIRONMENT` (SET) and
`ADD_PROMPT` (PROMPT) in `TENV.ASM` corrupt ES without restoring it:

- `SCAN_DOUBLE_NULL` (called by both) sets `ES = [ENVIRSEG]` (environment segment)
- The COMSPEC path (only for `SET COMSPEC=...`) further sets `ES = [RESSEG]` (RESGROUP)
- Neither path restores ES to TRANGROUP before returning

**Fix (TENV.ASM):** Added `push cs; pop es` at 5 return points:
1. `add_name_ret` `retz` — normal SET/PROMPT return (ES=ENVIRSEG)
2. `ONEQ` `retz` — `SET FOO=` clearing a variable (ES=ENVIRSEG via FIND)
3. COMSPEC `ret` — `SET COMSPEC=...` path (ES=RESGROUP)
4. `ADD_PROMPT2` `retz` — bare PROMPT with no args (ES=ENVIRSEG)
5. `STORE_CHAR` `JMP CERROR` — out of environment space (ES=ENVIRSEG)

**Fix (TCODE.ASM):** Defensive: added `PUSH CS; POP ES` before `CALL [HEADCALL]`
at TCOMMAND. This catches any command handler that forgets to restore ES —
TCOMMAND's own comment says "Nothing is known here. No registers, no flags, nothing."

## kvikdos Modifications (in kvikdos/kvikdos.c)
- `current_dir[DRIVE_COUNT]` expanded from 1 to 64 bytes per drive.
- `ah=0x3b` (CHDIR) implemented.
- `ah=0x29` (Parse Filename for FCB) fully implemented.
- `ah=0x46` (Force Duplicate File Handle / dup2) implemented.
- `ah=0x4d` (Get Child Process Exit Code) implemented.
- `ah=0x5b` (Create New File / O_CREAT|O_EXCL) implemented — needed by ASC2HLP.EXE.
- Spawn support (ah=0x4b al=0): saves full 640KB memory + CPU state, restores parent after child exits.
- `cd <path>` support added to batch interpreter.
- Filenames starting with `.` allowed (needed for `.CL1` files).
- `--cwd=<drive>:\<path>\` flag added to set initial DOS current directory.
- is_args_normal check now accepts both `\0` and `\r` as args terminator.
- `INT 3` (software breakpoint) handled as no-op — needed by COMPRESS.COM.
- INT 21h/AH=87h GETPID stub — returns PID=1 (MS-DOS 4.0 multitasking API, called by MS C 5.10 getpid()).
- macOS: `MADV_DONTNEED` does not zero pages (unlike Linux); spawn/re-exec path uses memset instead.

## Paths
- C standard headers (dos.h, stdio.h, etc.) are in `TOOLS/BLD/INC/`, not `TOOLS/INC/`.
- INCLUDE env var in bin/dos-run: `c:\\TOOLS\\BLD\\INC`.
- LIB env var in bin/dos-run: `c:\\TOOLS\\BLD\\LIB` (for SLIBCE.LIB needed by SELECT C objects).
- DOS/MSDOS.CL1 must be generated by NOSRVBLD before assembling INC/MSDOSME.OBJ (via DIVMES.ASM include chain).
- CMD utilities use BUILDMSG (not NOSRVBLD) to generate `.ctl` + `.cl*` files from `.skl`.
  - Rule: `buildmsg ..\..\MESSAGES\USA-MS COMMAND.SKL` (basename without .msg, then SKL file)
  - Key: check first line of .skl — `:class 1` → NOSRVBLD; `:util` → BUILDMSG.
- CMD AINC: `-I. -ID:\\TOOLS\\INC -I..\\..\\INC -I..\\..\\DOS` (two levels up from CMD/COMMAND/).
- DEV AINC: same as CMD AINC for most modules; RAMDRIVE/KEYBOARD use `-I. -I..\\..\\INC` (no DOS dir); SMARTDRV/XMAEM use `-I.` only; XMA2EMS uses `-I. -I..\\..\\INC`.
- XMAEM.MAKEFILE bug: target named `xmaem.ctl` but SKL is class 1, so NOSRVBLD generates `xmaem.cl1`. Use NOSRVBLD and target CL1.
- XMAEM.SYS: produced directly by LINK (output named `.sys` in LNK file) — no EXE2BIN needed.
- SELECT AINC: `-I. -I..\\INC` (one level deep from SRC/SELECT/). BRIDGE/CASERVIC use CASVAR.INC and CASRN.INC from INC/.
- SELECT C objects: compile with `-AS -Od -Zp -I. -c`.
- CASSFAR.LIB: pre-built, already in SELECT/ dir (no need to build from SHELL/CASSFAR).
- ASC2HLP.EXE and COMPRESS.COM: pre-built in TOOLS/.
- BOOTREC.OBJ: built in CMD/FDISK/ (needs FDBOOT.INC from FDBOOT.BIN via DBOF), then copied to SELECT/.
- FDBOOT.INC chain: NOSRVBLD(FDISK5.SKL)→CL1 → MASM FDBOOT.OBJ → LINK → EXE2BIN → DBOF(600 200).
- SELECT.LNK uses /EXEPACK (supported by LINK 3.65) and /noe flag (pass as `link /noe @SELECT.LNK`).
- COMPRESS.COM hardcoded: reads SEL-PAN.DAT, writes SELECT.DAT (must run in SELECT/ dir).
- MEMM: two sub-dirs: EMM/ (EMMLIB.LIB) and MEMM/ (EMM386.SYS).
- EMM AFLAGS: `-Mx -t -DI386 -DNOHIMEM -I..\\MEMM`; CFLAGS: `/ASw /G2 /Oat /Gs /Ze /Zl /c`.
- MEMM AFLAGS: `-Mx -t -DI386 -DNoBugMode -DNOHIMEM -I..\\EMM`; MAPDMA.C needs `-I..\\EMM`.
- EMM386.SYS: link `/NOI @EMM386.LNK` → emm386.exe, then rename to emm386.sys (no exe2bin).
