# MS-DOS 4.0 Build — TODO

## PREREQUISITE: Full E2E Test Coverage

**Full kvikdos test coverage must be achieved before starting UMB work.**
All items below must be `[x]` before any UMB phase begins.

Source-code audit identified these untested paths (all doable under kvikdos):

### COMMAND.COM — untested built-ins and batch features

- [x] `IF ERRORLEVEL n` — tests IF ERRORLEVEL parsing with default errorlevel 0 (Section 7). Note: can't test with child EXE exit codes — kvikdos spawn from COMMAND.COM causes "Memory allocation error".
- [x] `CD` / `CHDIR` functional — change directory and verify via CD output (Section 7)
- [x] `PROMPT` functional — set prompt string, verify via SET (Section 7)
- [x] `TRUENAME` functional — resolve canonical path via `/C TRUENAME path` (Section 7; passes on all platforms)
- [x] `COPY a+b c` concatenation — COPY /B with `+` multi-file, verify via TYPE (Section 7)
- [x] `COPY /A` / `COPY /B` — ASCII stops at ^Z (<=8 bytes), binary copies past ^Z (>=11 bytes); host file size verification (Section 7)

### FIND — untested paths

- [ ] `FIND "str"` from stdin (no filename argument) — kvikdos stdin passthrough is unreliable for FIND (works for SORT but not FIND; timing-dependent). Blocked until kvikdos stdin handling is improved.
- [x] Exit code via `IF ERRORLEVEL` — FIND.ASM source audit: exits 0 (always, even no match) or 2 (error). Note: full exit-code test blocked by kvikdos spawn limitation (can't run child EXEs from COMMAND.COM). IF ERRORLEVEL parsing itself is tested with default errorlevel 0.
  - Note: FIND v4.0 does NOT set errorlevel 1 for "no match" — only 0 or 2.

### MEM — untested switches

- [x] `MEM /PROGRAM` — show loaded programs; verified "Address" and "Type" column headers (Section 6). Note: MEM walks MCB chain which loops under kvikdos, test uses timeout+head.
- [x] `MEM /DEBUG` — same verification as /PROGRAM (Section 6). Note: EMS handle table not testable (no EMS under kvikdos).
- Note: `/CLASSIFY`, `/FREE`, `/MODULE` do NOT exist in v4.0 — those are 5.0+ additions.

### XCOPY — untested flags (use kvikdos-soft)

- [x] `XCOPY src dest /A` — copy only files with archive bit set; archive bit unchanged on source (Section 6). Required kvikdos fix: FindFirst/FindNext now reads xattr for real DOS attributes instead of hardcoding archive bit.
- [x] `XCOPY src dest /M` — copy archive-bit files and clear the archive bit on source after copy (Section 6). Same kvikdos fix as /A.
- [x] `XCOPY src dest /V` — verify sectors written; confirmed "1 File(s) copied" + file content (Section 6). Was blocked until kvikdos-soft rebuild included AH=54h stub.

### REPLACE — untested flags

- [x] `REPLACE src dest /R` — replace read-only files; verified "file(s) replaced" output (Section 6). Sets +R via ATTRIB, replaces with /R, confirms success.
- [x] `REPLACE src dest /S` — replace files in subdirectories recursively (Section 6). Verified files replaced in SUB1/ and SUB2/ subdirectories.

### FC — untested error paths

- [x] `FC nonexistent file` — verified "cannot open" error message (Section 6)

### Summary table

| Item | Tool | Effort | Status |
|------|------|--------|--------|
| `IF ERRORLEVEL n` | COMMAND.COM batch | Low | ✅ done (batch; macOS blocked) |
| CD/CHDIR functional | COMMAND.COM | Low | ✅ done (batch; macOS blocked) |
| PROMPT functional | COMMAND.COM | Low | ✅ done (batch; macOS blocked) |
| TRUENAME functional | COMMAND.COM | Low | ✅ done |
| COPY concatenation (`a+b`) | COMMAND.COM | Low | ✅ done (batch; macOS blocked) |
| COPY /A /B | COMMAND.COM | Low | ✅ done (batch; macOS blocked) |
| FIND from stdin | FIND | Low | ❌ blocked (kvikdos stdin unreliable) |
| FIND exit code via ERRORLEVEL | FIND | Low | ✅ done (batch; macOS blocked) |
| MEM /PROGRAM | MEM | Low | ✅ done |
| MEM /DEBUG | MEM | Low | ✅ done |
| XCOPY /A | XCOPY | Medium | ✅ done (kvikdos FindFirst xattr fix) |
| XCOPY /M | XCOPY | Medium | ✅ done (kvikdos FindFirst xattr fix) |
| XCOPY /V | XCOPY | Low | ✅ done |
| REPLACE /R | REPLACE | Low | ✅ done |
| REPLACE /S | REPLACE | Medium | ✅ done |
| FC nonexistent file error | FC | Low | ✅ done |

---

## UMB Support (Upper Memory Blocks)

Goal: add UMB support to our MS-DOS 4.0 fork so that device drivers and TSRs
can be loaded into the upper memory area (640K–1MB), freeing conventional memory.
This is a feature MS-DOS 5.0 introduced; we're backporting the concept to our 4.0 fork.

Reference implementations (for study, not copying):
- **FreeDOS kernel** — MSDOS/kernel side: UMB link/unlink, `DOS=UMB`, `DEVICEHIGH`, arena chain management.
- **JEMM** (Japheth's EMM386) — EMM386 side: UMB provider via INT 2Fh/AX=4310h (XMS), V86 page mapping.

### Phase 1: EMM386 — UMB provider

EMM386 must provide UMBs to the kernel via the XMS interface.

- [ ] Study how UMBs are exposed: INT 2Fh/AX=4310h → XMS driver entry, functions 10h (Request UMB) / 11h (Release UMB)
- [ ] Study our EMM386 source (`MEMM/`) — understand V86 mode setup, page table management, existing EMS page frame mapping
- [ ] Add XMS UMB allocation (function 10h): map available upper memory regions (C000–EFFF gaps not used by ROM/adapters) as allocatable UMBs
- [ ] Add XMS UMB release (function 11h)
- [ ] UMB region detection: scan adapter ROM signatures (55AA) and video RAM to find free gaps in upper memory; make regions configurable (e.g., `DEVICE=EMM386.SYS I=C800-EFFF` include ranges)
- [ ] Test: verify XMS UMB functions work from a test program under QEMU

### Phase 2: MSDOS kernel — UMB-aware memory management

The kernel needs to link UMBs into the MCB (Memory Control Block) arena chain.

- [ ] Study MS-DOS 5.0+ MCB arena chain structure: how UMBs are linked as a second arena above conventional memory
- [ ] Study FreeDOS kernel source for the UMB link/unlink mechanism
- [ ] `DOS=UMB` CONFIG.SYS directive: when set, kernel calls XMS to request UMBs at init and links them into the MCB chain
- [ ] `DOS=HIGH,UMB` combination: support both directives together
- [ ] MCB chain linking: after obtaining UMB regions from XMS, create MCB headers and chain them to the end of the conventional memory arena
- [ ] INT 21h/AH=58h subfunction 03h (Set UMB Link State): allow programs to include/exclude UMBs from allocation
- [ ] INT 21h/AH=58h subfunction 02h (Get UMB Link State)
- [ ] Test: verify `MEM` shows upper memory region, allocation from UMBs works

### Phase 3: COMMAND.COM / CONFIG.SYS — DEVICEHIGH, LOADHIGH

- [ ] `DEVICEHIGH=` CONFIG.SYS directive: load device drivers into UMBs (kernel init code — try UMB first, fall back to conventional)
- [ ] `LOADHIGH` / `LH` COMMAND.COM built-in: load TSRs into UMBs
- [ ] `MEM /C` or similar: show which programs/drivers are in upper memory
- [ ] Test: boot with `DOS=UMB`, `DEVICEHIGH=ANSI.SYS`, verify ANSI.SYS loads into UMA, conventional memory increases

### Phase 4: HMA — Load DOS High

Load MSDOS.SYS kernel into the HMA (High Memory Area, first 64K-16 bytes above 1MB at FFFF:0010–FFFF:FFFF),
freeing ~40-50K of conventional memory. Requires A20 gate control and an XMS driver (HIMEM.SYS or EMM386).

- [ ] Study HMA mechanics: A20 gate enable/disable, FFFF:xxxx wrapping vs linear access, the 64K-16 byte limit
- [ ] Study how MS-DOS 5.0+ relocates kernel code/data to HMA (FreeDOS `kernel/hma.c` as reference)
- [ ] XMS prerequisite: EMM386 or a minimal HIMEM.SYS must provide XMS function 01h (Request HMA) / 02h (Release HMA) and A20 control (functions 03h–07h)
- [ ] Decide: add HMA/A20/XMS support to EMM386 (it already does V86), or implement a separate minimal HIMEM.SYS
- [ ] `DOS=HIGH` CONFIG.SYS directive: at init, request HMA via XMS, enable A20, relocate kernel resident code/data to FFFF:0010+
- [ ] Fix-up INT 21h dispatch: kernel entry points must remain in low memory (or use A20-aware thunks) since callers expect segment ≤ 0xFFFF
- [ ] A20 management: enable A20 while DOS code in HMA executes, handle transitions correctly
- [ ] `MEM` display: show "nnnnK DOS resident in HMA" when DOS=HIGH is active
- [ ] Test: boot with `DOS=HIGH,UMB`, verify MEM shows DOS in HMA and conventional memory increases by ~45K

### Notes

- This is a from-scratch implementation for fun/learning. Use FreeDOS and JEMM as architectural references only.
- The existing EMM386.SYS in our build already does V86 mode and EMS page mapping — UMB and HMA support extend this, don't replace it.
- Testing strategy: QEMU with ≥1MB RAM, verify via MEM output and actual program loading.

## E2E Tests — Migrate QEMU Tests to kvikdos

Goal: reduce expensive QEMU CI jobs by moving tests that only need INT 21h file I/O
to the fast kvikdos harness. Keep QEMU for disk hardware (INT 13h), boot, TSRs,
and interactive prompt flows.

### Priority 1: test_builtins.sh → kvikdos

Best candidate. Tests COMMAND.COM built-ins (VER, DIR, SET, PATH, VOL, TYPE, COPY,
DEL, RENAME, FIND, VERIFY, BREAK, CHCP, TRUENAME, MD/RD) and batch control flow
(IF, FOR, CALL, SHIFT, GOTO, REM). All are pure file I/O and string operations —
no disk hardware dependencies.

- [x] Verify COMMAND.COM batch file execution works reliably in kvikdos
  - **Result: WORKS** — requires COMSPEC env var pointing to COMMAND.COM on C: drive
    (now set automatically by `bin/dos-run`). Added 6 new INT 21h/2Fh stubs to kvikdos:
    AH=13h (FCB delete), AH=17h (FCB rename), AH=2Eh (set verify), AH=54h (get verify),
    AH=5Ah (create unique temp file), INT 2Fh/AX=1902h-1903h (shell multiplex).
    Working built-ins: VER, DIR, SET, PATH, VOL, VERIFY, BREAK, IF, FOR, GOTO, CALL,
    SHIFT, TYPE, COPY, REN, DEL, MD, RD, ECHO, REM and batch control flow.
- [x] Port test_builtins.sh test cases to run_tests.sh kvikdos E2E section
  - **Result: DONE** — 33 tests in Section 7 covering VER, ECHO, SET, PATH, DIR, DIR/W, VOL,
    BREAK, VERIFY, TYPE, GOTO, REM, IF EXIST/NOT EXIST/==, CALL, SHIFT, FOR, ECHO./OFF/ON,
    BREAK/VERIFY ON/OFF toggle, PATH/SET assign+clear, COPY, COPY/V, REN, DEL, ERASE,
    DEL wildcard, MD+RD, MD nested. All 33 pass under kvikdos.
- [x] Remove or slim down the QEMU e2e-builtins CI job
  - **Result: REMOVED** — `e2e-builtins` job deleted from ci.yml; `build` job already runs
    `make test` (run_tests.sh) which covers all 33 built-in tests via kvikdos in Section 7.

### Priority 2: test_help_qemu.sh — slim to EXEPACK-only

run_tests.sh Section 4 already tests `/?` help for all tools under kvikdos.
The only unique QEMU value is verifying EXEPACK decompression with the real DOS loader.

- [x] Reduce test_help_qemu.sh to EXEPACK integrity verification only
- [x] Drop the duplicated `/?` checks that kvikdos already covers
  - **Result: DONE** — test_help_qemu.sh now runs 2 checks: EXEPACK corruption absent,
    and QEMU boot reached ---DONE--- marker. All 27 per-tool `check_tool_help` calls removed.

### Priority 3: Expand kvikdos E2E coverage

Add more test scenarios for tools already supported in kvikdos, avoiding QEMU cost:

- [ ] SUBST/JOIN with actual drive operations (requires kvikdos multi-drive support)

### Won't migrate (must stay QEMU)

| Test | Reason |
|------|--------|
| test_format.sh | INT 13h sector formatting, BPB geometry, QMP disk swapping |
| test_sys.sh | Boot verification — SYS transfers system files, QEMU boots from result |
| test_diskcomp_diskcopy.sh | Track-by-track INT 13h read/write |
| test_label.sh | FAT volume/boot-sector writes (not in kvikdos), interactive prompts |
| test_backup_restore.sh | Multi-disk flow, interactive prompts, archive bit across drives |
| test_append.sh | TSR persistence (INT 2Fh hooks, KEEP_PROCESS) — all 6 cases depend on residency |
| test_assign_subst_join.sh | TSR-based drive table manipulation (INT 2Fh + KEEP_PROCESS), multi-disk |
| test_share_nlsfunc_exe2bin.sh | SHARE/NLSFUNC: TSR persistence; EXE2BIN already covered in Section 6 |
| test_misc_qemu.sh | CHKDSK: INT 13h; IFSFUNC/FILESYS/FASTOPEN/GRAPHICS/PRINT/KEYB: all TSRs |
| test_debug_qemu.sh | DEBUG G needs INT 21h/AH=5Dh/AL=0Ah (save extended error state) — unsupported |
| test_recover.sh | FAT chain walking + INT 13h disk hardware |
| ~~test_builtins.sh~~ | **Deleted** — fully migrated to run_tests.sh Section 7 (kvikdos) |
| ~~test_edlin_b_qemu.sh~~ | **Deleted** — EDLIN /B bug fixed + migrated to run_tests.sh Section 6 (kvikdos) |

## E2E Tests — Coverage Summary

**Harness:** kvikdos for fast tests (`run_tests.sh`), QEMU+COM1 for disk-heavy ops. CI runs parallel E2E jobs for each test target; see `.github/workflows/ci.yml` for the full list.

Legend: ✅ tested · ⚠️ partial · ❌ not tested · 🚫 untestable (interactive/hardware)

| Tool | Build | /? help | Functional | Notes |
|------|-------|---------|------------|-------|
| COMMAND.COM (built-ins) | ✅ | ⚠️ Section 5 binary (Linux CI only) | ⚠️ Section 7 (43 tests) | IF ERRORLEVEL, CD, PROMPT, TRUENAME, COPY+concat, COPY /A/B; DATE/TIME/PAUSE/CHCP 🚫 interactive |
| MEM | ✅ | ⚠️ Section 4 (Linux CI only) | ⚠️ Section 6 (3 tests: basic + /PROGRAM + /DEBUG) | MCB loops under kvikdos, uses timeout+head |
| FIND | ✅ | ⚠️ Section 4 (Linux CI only) | ⚠️ Section 6 (7 tests: /V /N /C multi no-match) | v4.0 flags: /V /C /N only. stdin ❌ blocked (kvikdos stdin unreliable) |
| FC | ✅ | ✅ Section 4 (own parser, works everywhere) | ✅ Section 6 (14 tests: /A /B /C /N /W /L /T /5 + nonexistent) | v4.0 flags: /A /B /C /L /LB /W /T /N /NNNN |
| ATTRIB | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ Section 6 (8 tests: show +R -R +R+A -A +A /S) | v4.0 flags: +R -R +A -A /S. No +H/-H +S/-S in v4.0 |
| COMP | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ Section 6 (7 tests: identical/diff/hex/limit/not-found) | v4.0 has NO switches (confirmed: COMPPAR.ASM defines 0 switch operands) |
| TREE | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ Section 6 (5 tests: basic /F /A path chars) | v4.0 flags: /F /A |
| SORT | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ Section 6 (5 tests: stdin /R /+N file reverse) | v4.0 flags: /R /+n only. No /T /C /L /O in v4.0 |
| MORE | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ Section 6 (3 tests: stdin file from-file) | v4.0: no switches (filter utility) |
| DEBUG | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ Section 6 (15 tests: R/E/D/F/H/C/M/S/A/U/N/W/L) + test_debug_qemu.sh (G execute) | |
| EDLIN | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ Section 6 (18 tests: open/new/insert/del/edit/copy/move/search/replace/transfer/page/write + /B) | |
| XCOPY | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ Section 6 (15 tests: basic /S /S+E /V /A /M /D) | v4.0 flags: /A /D /E /M /P /S /V /W. `/P` `/W` 🚫 interactive |
| REPLACE | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ Section 6 (9 tests: /A /U /U-older /R /S error + content checks) | v4.0 flags: /A /P /R /S /U /W. `/P` `/W` 🚫 interactive |
| GRAFTABL | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ Section 6 (4 tests: 437 850 /STATUS status) | |
| LABEL | ✅ | ⚠️ Section 4 (Linux CI only) | ⚠️ Section 6 (read-only); write/delete in test_label.sh | |
| ASSIGN | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_assign_subst_join.sh (B=A redirect verified; clear) | |
| SUBST | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_assign_subst_join.sh (D: create/list/delete) | |
| JOIN | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_assign_subst_join.sh (B: join/list/verify/unjoin) | |
| EXE2BIN | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ Section 6 (3 tests) + test_share_nlsfunc_exe2bin.sh | |
| CHKDSK | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_misc_qemu.sh (disk stats, /V file listing) | |
| FORMAT | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_format.sh (8 variants: geometry/BPB/label) | |
| SYS | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_sys.sh (boot verification) | |
| DISKCOPY | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_diskcomp_diskcopy.sh | |
| DISKCOMP | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_diskcomp_diskcopy.sh | |
| BACKUP | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_backup_restore.sh (/S /M /A /D /T /L) | `/F` ❌ not tested |
| RESTORE | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_backup_restore.sh (/S /N /M /B /A /E /L) | `/P` 🚫 interactive |
| SHARE | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_share_nlsfunc_exe2bin.sh | |
| NLSFUNC | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_share_nlsfunc_exe2bin.sh | |
| APPEND | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_append.sh (/E /X path set/clear) | |
| KEYB | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_misc_qemu.sh (KEYB US; KEYB GR,,KEYBOARD.SYS; KEYB status) | |
| FDISK | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_fdisk.sh (/PRI:5 /EXT:10 /LOG:10 /Q; errorlevel 2; MBR+EBR verified) | |
| PRINT | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_misc_qemu.sh (/D:PRN install; queue status) | |
| FASTOPEN | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_misc_qemu.sh (C:=50 install smoke test) | |
| GRAPHICS | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_misc_qemu.sh (load GRAPHICS.PRO; reload; /R reverse; /B background) | |
| MODE | ✅ | ⚠️ Section 4 (Linux CI only) | ⚠️ test_misc_qemu.sh (CON /STATUS only) | serial/parallel/console config 🚫 hardware |
| RECOVER | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_recover.sh (file mode: keypress prompt + bytes recovered) | drive mode (destructive) skipped |
| IFSFUNC | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_misc_qemu.sh (install + already-installed check) | |
| FILESYS | ✅ | ⚠️ Section 4 (Linux CI only) | ✅ test_misc_qemu.sh (install smoke test, after IFSFUNC) | |

**Note on /? help tests:** Section 4 uses SYSPARSE which returns "Parse Error 3" under kvikdos-soft (macOS). Tests pass under KVM (Linux CI). FC has its own parser and works everywhere.

## E2E Tests — Remaining Per-Command Coverage

**Kvikdos-testable gaps are tracked in the PREREQUISITE section above.**
Items here are either interactive (require keypress) or need hardware not available in kvikdos.

### COMMAND.COM built-ins — remaining (interactive / needs special setup)

| Command | Remaining options |
|---------|-------------------|
| DIR | `/P` (pause/page — interactive) |
| DATE | no-arg (show date), set date — interactive |
| TIME | no-arg (show time), set time — interactive |
| PAUSE | no-arg (waits for keypress) — interactive |
| CHCP | `CHCP nnn` (set — needs DISPLAY.SYS) |

### External CMD tools

#### XCOPY — remaining
- [x] `XCOPY src dest /D:date` — required INT 21h/AH=2Bh (Set Date) stub in kvikdos; SYSPARSE calls it to validate dates. Section 6, kvikdos.
- [ ] `XCOPY src dest /P` — prompt per file (interactive)
- [ ] `XCOPY src dest /W` — wait before start (interactive)

#### REPLACE — remaining (interactive; non-interactive flags tracked in PREREQUISITE above)
- [ ] `REPLACE src dest /P` — prompt (interactive)
- [ ] `REPLACE src dest /W` — wait before start (interactive)

#### BACKUP — remaining
- [ ] `BACKUP C: A: /F` — format target if needed

#### RESTORE — remaining
- [ ] `RESTORE A: C: /P` — prompt on conflicts (interactive)

#### EDLIN — /B bug (pre-existing in MS-DOS 4.0 source)
- [x] `EDLIN file /B` — binary (ignore ^Z) — kvikdos Section 6 (~~test_edlin_b_qemu.sh~~ **Deleted**)
- [x] Fix /B bug — kvikdos test in run_tests.sh passes (LINE3 visible after embedded ^Z)
- [x] kvikdos test in run_tests.sh (Section 6) now passes with the fix

The /B bug is **pre-existing in the original MS-DOS 4.0 source** — both kvikdos and QEMU
reproduce it on the original binary. `/B` was always intended (the parse structure is in
EDLPARSE.ASM) but broken at the binary level due to two MASM issues.

**Bug 1 — val_sw comparison always failed (FIXED):**
`val_sw` in `EDLPARSE.ASM` had a broken `cmp es:parse_sw_syn, offset es:sw_b_switch` —
MASM resolved the `offset` at assembly time to a local DG-group offset that doesn't match
the actual runtime address after linking (no fixup emitted).
Fixed by simplifying to unconditional `mov dg:parse_switch_b, true` (only one switch exists).
Committed: submodule `52f514b`, top-level `03206cc`.

**Bug 2 — MASM ASSUME vs runtime DS mismatch in val_sw (ROOT CAUSE):**

`val_sw` writes `parse_switch_b` to the **wrong segment** because of a mismatch between
MASM's positional `ASSUME` and the actual runtime DS value.

EDLPARSE.ASM source layout:
```
line 145:  assume cs:dg, ds:dg, es:dg       ← code segment start
line 158:  parser_command proc
line 165:    mov dg:parse_switch_b, false    ← DS is DG here (correct write)
line 170:    mov ds, dg:org_ds              ← DS := org_ds (PSP segment)
line 171:    assume ds:nothing
             ... parse loop, calls val_sw at line 190 ...
line 209:    assume ds:dg                   ← restores ASSUME after pop ds
line 214:  parser_command endp
line 261:  val_sw proc                      ← ASSUME is ds:dg (from line 209!)
line 266:    mov dg:parse_switch_b, true    ← MASM uses DS, NO segment override
line 276:  val_sw endp
```

MASM ASSUME is **positional in source text**, not call-chain-aware. At `val_sw`'s
definition (line 261), the last ASSUME was `ds:dg` (line 209). So MASM generates
`mov DS:[group_offset], 0xFF` — no CS: segment override prefix emitted.

But `val_sw` is **called** from line 190, inside `parser_command`'s parse loop,
where `DS = org_ds` (PSP segment, set at line 170). At runtime:

| Location | ASSUME | Actual DS | Override | Write target |
|---|---|---|---|---|
| Line 165 (init false) | ds:dg | CS (= DG) | none | DG group (correct) |
| Line 266 (set true) | ds:dg | org_ds (PSP) | none | PSP segment (WRONG) |

Result: `true` (0xFF) is written to `PSP:[group_offset_of_parse_switch_b]` —
a random location in the PSP segment. The DG group retains `false` from line 165.

`EDLIN_COMMAND` (EDLIN.ASM:1713) then reads `parse_switch_b` via DS, which is CS = DG
(set at SIMPED line 355, preserved through SYSLOADMSG). It correctly reads from DG
group, gets `false`, and never sets `loadmod = 1`. SCANEOF sees `loadmod = 0` → stops
at ^Z → LINE3 absent.

Note: SYSLOADMSG preserves DS (verified: it pushes AX,BX,DX,ES,DI; does not modify DS
directly; subroutine `$M_GET_DBCS_VEC` saves/restores DS). So `EDLIN_COMMAND`'s
DS-relative read is fine — the problem is purely on the val_sw write side.

Note: the `offset dg:` vs `[name]` address discrepancy (0x2B1F vs 0x2B15 for loadmod)
found in the earlier CS:[BX] fix attempt is a separate MASM quirk — `offset dg:` computes
at assembly time from partial segment info, while `[name]` uses a linker fixup. This is
NOT the root cause. The original `[LOADMOD]` and `[parse_switch_b]` references in
EDLIN_COMMAND use linker fixups and resolve correctly. The bug is purely that val_sw's
write goes to the wrong segment.

**Hardcode loadmod=1 test (DONE):** confirmed SCANEOF logic is correct. With
`loadmod db 1` hardcoded, LINE3 appears. The bug is 100% in the parse plumbing.

**Fix:** add `assume ds:nothing` to `val_sw` so MASM generates a CS: segment override:
```asm
val_sw    proc  near
    assume ds:nothing                          ; DS is org_ds at runtime, not DG
    mov  byte ptr cs:[parse_switch_b], true    ; CS: override → writes to DG group
    assume ds:dg                               ; restore for following code
    ret
val_sw    endp
```
MASM syntax `cs:[varname]` is confirmed valid — already used in EDLIN.ASM ~line 1802:
`mov ds, cs:[org_ds]` (Calc_Memory_Avail).

#### DEBUG ✅ done
- [x] `G` (go/execute) — assemble tiny program, run with G, verify output + "Program terminated normally" (test_debug_qemu.sh)

#### FDISK ✅ done
- [x] `FDISK 1 /PRI:5 /Q` — create primary partition (test_fdisk.sh, MBR type verified)
- [x] `FDISK 1 /EXT:10 /Q` — create extended partition (test_fdisk.sh, MBR type 0x05 verified)
- [x] `FDISK 1 /LOG:10 /Q` — create logical drive in extended partition (test_fdisk.sh, EBR verified)
- [x] `FDISK 1 /Q` (no switches) — exit code 2 verified via IF ERRORLEVEL (test_fdisk.sh)

#### PRINT
- [ ] `PRINT /D:PRN file` — print to device
- [ ] `PRINT /T` — cancel queue
- [ ] `PRINT file /P` — add to queue
- [ ] `PRINT file /C` — remove from queue
- [ ] `PRINT /Q:5 file` — set queue size

#### KEYB — needs QEMU
- [x] `KEYB US` — load US keyboard (test_misc_qemu.sh)
- [x] `KEYB GR,,KEYBOARD.SYS` — explicit file, non-US layout (test_misc_qemu.sh)
- [x] `KEYB` — show current layout, verified for US and GR (test_misc_qemu.sh)
- [ ] `KEYB UK,850,KEYBOARD.SYS /ID:166` — with code page and ID

#### ASSIGN ✅ done
- [x] `ASSIGN B=A` + `DIR B:` verify + `ASSIGN` clear (test_assign_subst_join.sh)

#### JOIN ✅ done
- [x] `JOIN B: A:\JOINDIR` + list + verify BJOIN.TXT + `JOIN B: /D` (test_assign_subst_join.sh)

#### SUBST ✅ done
- [x] `SUBST D: A:\SUBSTDIR` + `SUBST` list + `SUBST D: /D` (test_assign_subst_join.sh)

#### FASTOPEN
- [x] `FASTOPEN C:=50` — cache 50 entries (test_misc_qemu.sh)
- Note: `/X` (expanded memory) does NOT exist in v4.0 source — that's a DOS 5.0+ addition.

#### GRAPHICS
- [x] `GRAPHICS` — load default GRAPHICS.PRO (test_misc_qemu.sh)
- [x] `GRAPHICS /R` — reverse printing (test_misc_qemu.sh)
- [x] `GRAPHICS /B` — background printing (test_misc_qemu.sh)
- Note: v4.0 printer types are COLOR and BLACK_WHITE (not COLOR4/HPDEFAULT — those are DOS 5.0+ names).

#### MODE
- [ ] `MODE COM1: 9600,N,8,1` — configure serial
- [ ] `MODE LPT1: 80,66` — configure parallel
- [ ] `MODE CON COLS=80 LINES=25` — configure console
- [ ] `MODE CON RATE=30 DELAY=1` — typematic rate
- [ ] `MODE CON /STATUS` — show console status

#### CHKDSK — remaining
- [x] `CHKDSK` — disk stats (test_misc_qemu.sh)
- [x] `CHKDSK /V` — verbose file listing (test_misc_qemu.sh)
- [ ] `CHKDSK /F` — fix errors (interactive on real errors; needs corrupt disk image)

#### RECOVER
- [ ] `RECOVER A:file` — recover bad-sector file
- [ ] `RECOVER A:` — recover entire disk

#### IFSFUNC
- [ ] `IFSFUNC` — load IFS driver (smoke test)

#### FILESYS
- [ ] `FILESYS` — load (smoke test, internal tool)
