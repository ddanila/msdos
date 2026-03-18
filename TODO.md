# MS-DOS 4.0 Build — TODO

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
| test_label.sh | FCB delete (INT 21h/13h not in kvikdos), interactive prompts |
| test_backup_restore.sh | Multi-disk flow, interactive prompts, archive bit across drives |
| test_append.sh | TSR persistence (INT 2Fh hooks, KEEP_PROCESS) |
| ~~test_builtins.sh~~ | **Deleted** — fully migrated to run_tests.sh Section 7 (kvikdos) |

## E2E Tests — Coverage Summary

**Harness:** kvikdos for fast tests (`run_tests.sh`), QEMU+COM1 for disk-heavy ops. CI runs parallel E2E jobs for each test target; see `.github/workflows/ci.yml` for the full list.

Legend: ✅ tested · ⚠️ partial · ❌ not tested · 🚫 untestable (interactive/hardware)

| Tool | Build | /? help | Functional | Notes |
|------|-------|---------|------------|-------|
| COMMAND.COM (built-ins) | ✅ | ✅ Section 5 binary | ✅ Section 7 (33 tests) | DATE/TIME/PAUSE/CHCP 🚫 interactive |
| MEM | ✅ | ✅ Section 4 | ✅ Section 6 (basic report) | |
| FIND | ✅ | ✅ Section 4 | ✅ Section 6 (8 tests: /V /N /C multi no-match) | |
| FC | ✅ | ✅ Section 4 | ✅ Section 6 (10 tests: /B /C /N /W /L /T /5) | |
| ATTRIB | ✅ | ✅ Section 4 | ✅ Section 6 (5 tests: +R -R +A -A /S) | |
| COMP | ✅ | ✅ Section 4 | ✅ Section 6 (7 tests: identical/diff/hex/limit) | |
| TREE | ✅ | ✅ Section 4 | ✅ Section 6 (3 tests: basic /F path) | |
| SORT | ✅ | ✅ Section 4 | ✅ Section 6 (4 tests: /R /+N file) | |
| MORE | ✅ | ✅ Section 4 | ✅ Section 6 (2 tests: stdin file) | |
| DEBUG | ✅ | ✅ Section 4 | ✅ Section 6 (8 tests: regs/mem/hex/asm/file) + test_debug_qemu.sh (G execute) | |
| EDLIN | ✅ | ✅ Section 4 | ✅ Section 6 (9 tests: insert/del/edit/search/copy) + test_edlin_b_qemu.sh (/B binary mode) | |
| XCOPY | ✅ | ✅ Section 4 | ✅ Section 6 (3 tests: basic /S /S/E) | `/P` `/W` 🚫 interactive |
| REPLACE | ✅ | ✅ Section 4 | ✅ Section 6 (3 tests: /A /U error) | `/P` `/W` 🚫 interactive |
| GRAFTABL | ✅ | ✅ Section 4 | ✅ Section 6 (3 tests: 437 850 /STATUS) | |
| LABEL | ✅ | ✅ Section 4 | ⚠️ Section 6 (read-only); write/delete in test_label.sh | |
| ASSIGN | ✅ | ✅ Section 4 | ✅ test_assign_subst_join.sh (B=A redirect verified; clear) | |
| SUBST | ✅ | ✅ Section 4 | ✅ test_assign_subst_join.sh (D: create/list/delete) | |
| JOIN | ✅ | ✅ Section 4 | ✅ test_assign_subst_join.sh (B: join/list/verify/unjoin) | |
| EXE2BIN | ✅ | ✅ Section 4 | ✅ Section 6 + test_share_nlsfunc_exe2bin.sh | |
| CHKDSK | ✅ | ✅ Section 4 | ✅ test_misc_qemu.sh (disk stats, /V file listing) | |
| FORMAT | ✅ | ✅ Section 4 | ✅ test_format.sh (8 variants: geometry/BPB/label) | |
| SYS | ✅ | ✅ Section 4 | ✅ test_sys.sh (boot verification) | |
| DISKCOPY | ✅ | ✅ Section 4 | ✅ test_diskcomp_diskcopy.sh | |
| DISKCOMP | ✅ | ✅ Section 4 | ✅ test_diskcomp_diskcopy.sh | |
| BACKUP | ✅ | ✅ Section 4 | ✅ test_backup_restore.sh | `/F` ❌ not tested |
| RESTORE | ✅ | ✅ Section 4 | ✅ test_backup_restore.sh | `/P` 🚫 interactive |
| SHARE | ✅ | ✅ Section 4 | ✅ test_share_nlsfunc_exe2bin.sh | |
| NLSFUNC | ✅ | ✅ Section 4 | ✅ test_share_nlsfunc_exe2bin.sh | |
| APPEND | ✅ | ✅ Section 4 | ✅ test_append.sh (/E /X path set/clear) | |
| KEYB | ✅ | ✅ Section 4 | ✅ test_misc_qemu.sh (KEYB US install; KEYB shows current layout) | |
| FDISK | ✅ | ✅ Section 4 | ✅ test_fdisk.sh (/PRI:5 /Q creates partition; verified via fdisk -l) | |
| PRINT | ✅ | ✅ Section 4 | ✅ test_misc_qemu.sh (/D:PRN install; queue status) | |
| FASTOPEN | ✅ | ✅ Section 4 | ✅ test_misc_qemu.sh (C:=50 install smoke test) | |
| GRAPHICS | ✅ | ✅ Section 4 | ✅ test_misc_qemu.sh (load GRAPHICS.PRO; reload) | |
| MODE | ✅ | ✅ Section 4 | ⚠️ test_misc_qemu.sh (CON /STATUS only) | serial/parallel/console config 🚫 hardware |
| RECOVER | ✅ | ✅ Section 4 | ✅ test_recover.sh (file mode: keypress prompt + bytes recovered) | drive mode (destructive) skipped |
| IFSFUNC | ✅ | ✅ Section 4 | ✅ test_misc_qemu.sh (install + already-installed check) | |
| FILESYS | ✅ | ✅ Section 4 | ✅ test_misc_qemu.sh (install smoke test, after IFSFUNC) | |

## E2E Tests — Remaining Per-Command Coverage

### COMMAND.COM built-ins — remaining (interactive / needs special setup)

| Command | Remaining options |
|---------|-------------------|
| DIR | `/P` (pause/page — interactive) |
| DATE | no-arg (show date), set date — interactive |
| TIME | no-arg (show time), set time — interactive |
| PAUSE | no-arg (waits for keypress) — interactive |
| CHCP | `CHCP nnn` (set — needs DISPLAY.SYS) |

### External CMD tools

#### XCOPY — remaining (interactive)
- [ ] `XCOPY src dest /P` — prompt per file (interactive)
- [ ] `XCOPY src dest /W` — wait before start (interactive)

#### REPLACE — remaining
- [ ] `REPLACE src dest /P` — prompt (interactive)
- [ ] `REPLACE src dest /W` — wait before start (interactive)

#### BACKUP — remaining
- [ ] `BACKUP C: A: /F` — format target if needed

#### RESTORE — remaining
- [ ] `RESTORE A: C: /P` — prompt on conflicts (interactive)

#### EDLIN — /B bug investigation in progress
- [x] `EDLIN file /B` — binary (ignore ^Z) — QEMU E2E (test_edlin_b_qemu.sh)
- [ ] Fix remaining /B bug — kvikdos test in run_tests.sh fails (LINE3 absent when /B passed)
- [ ] kvikdos test already added to run_tests.sh (Section 6), passing requires the fix below

**Bug 1 — val_sw comparison always failed (FIXED):**
`val_sw` in `EDLPARSE.ASM` had a broken `cmp es:parse_sw_syn, offset es:sw_b_switch` —
MASM resolved the `offset` at assembly time to a local DG-group offset that doesn't match
the actual runtime address after linking with EDLIN+EDLCMD1+EDLCMD2+EDLMES (no fixup emitted).
Fixed by simplifying to unconditional `mov dg:parse_switch_b, true` (only one switch exists).
Committed: submodule `52f514b`, top-level `03206cc`.

**Bug 2 — DS/ES segment mismatch (ROOT CAUSE, not yet fixed):**
`parser_command` in EDLPARSE.ASM sets `DS = org_ds` (PSP segment = 0x0100) at line 170
before calling sysparse in the parse loop. So val_sw executes with DS=0x0100. However
EDLIN_COMMAND runs later with DS=0x0110 (changed by SYSLOADMSG during EDLIN init).

- `val_sw` writes `parse_switch_b = true` at DS:[0x34E7] with DS=0x0100 → linear 0x44E7
- `EDLIN_COMMAND` reads `parse_switch_b` at DS:[0x34E7] with DS=0x0110 → linear 0x45E7
- **Gap is exactly 0x100 bytes = 1 paragraph** — the write and read go to different memory!
- The write IS happening (confirmed by kvikdos debug: `PSP:0x34E7 = 0xFF`), but
  the read misses it (`DS:0x34E7 = 0x00`).

**Root cause details:**
- SIMPED in EDLIN.ASM: `push cs; pop ds` → DS=CS=0x0100 (PSP segment)
- SYSLOADMSG (called from PRE_LOAD_MESSAGE before parser_command): changes DS to 0x0110
  (SYSLOADMSG saves ES but NOT DS, so DS change persists)
- parser_command saves DS on stack (`push ds`), sets `DS = org_ds = 0x0100`
  (org_ds was saved at SIMPED time, = 0x0100)
- After parse loop: `pop ds` restores DS = 0x0110 (the pre-parser_command value)
- EDLIN_COMMAND runs with DS = 0x0110

**Proposed fix (not yet applied):**
In EDLIN.ASM's EDLIN_COMMAND, change the `cmp dg:parse_switch_b, true` to use CS: override:
```asm
cmp  cs:parse_switch_b, true   ; CS=0x0100=PSP segment = where val_sw wrote
```
CS is always 0x0100 (PSP segment) for the COM file. val_sw's write and this read would
both target linear 0x44E7. The LOADMOD write after it can still use DS (correct for SCANEOF).

Alternatively, check the binary directly first against the ORIGINAL MS-DOS 4.0 EDLIN.COM
(no modifications from our fork) to bisect whether this is a pre-existing bug in the
original EDLIN source, a bug introduced by our /? and val_sw modifications, or a kvikdos
emulation issue (e.g. incorrect DS value during init).

**Bisect plan:**
1. Test original MS-DOS 4.0 EDLIN.COM (from git history before any of our modifications)
   with kvikdos — does /B work? If yes → our changes broke it.
2. Test the original EDLIN.COM with QEMU — does /B work? If different from kvikdos →
   kvikdos emulation bug (e.g., wrong DS during SYSLOADMSG init).
3. Test current modified EDLIN.COM with QEMU (test_edlin_b_qemu.sh) — does it pass?
   If yes → only a kvikdos issue.

**Binary addresses (in rebuilt EDLIN.COM with val_sw fix, DS=0x0110 at ExtOpen time):**
- `val_sw` at CS:0x2E13 (binary 0x2D13): `mov byte [0x34E7], 0xFF; ret`
- `EDLIN_COMMAND` at CS:0x0B8D (binary 0x0A8D): `cmp byte [0x34E7], 0xFF`
  → with DS=0x0110 reads linear 0x45E7 (wrong: val_sw wrote to 0x44E7)
- `LOADMOD` at CS:0x2B15 (binary 0x2A15): should be 0x01 when /B used
- `SCANEOF` at CS:0x1278 (binary 0x1178): `cmp byte [LOADMOD], 0x00`

**kvikdos debug probes (temporary, in kvikdos.c):**
- DS change tracker after KVM_GET_SREGS: logs every DS segment change
- ExtOpen (AH=0x6C) handler probe: logs DS/PSP values of parse_switch_b and LOADMOD
  when EDLIN opens a file with "EDLB" in its name
- Remove both probes once the fix is confirmed.

#### DEBUG ✅ done
- [x] `G` (go/execute) — assemble tiny program, run with G, verify output + "Program terminated normally" (test_debug_qemu.sh)

#### FDISK ✅ done
- [x] `FDISK 1 /PRI:5 /Q` — create primary partition (test_fdisk.sh, partition verified via host fdisk -l)

#### PRINT
- [ ] `PRINT /D:PRN file` — print to device
- [ ] `PRINT /T` — cancel queue
- [ ] `PRINT file /P` — add to queue
- [ ] `PRINT file /C` — remove from queue
- [ ] `PRINT /Q:5 file` — set queue size

#### KEYB — needs QEMU
- [ ] `KEYB US` — load US keyboard (kvikdos: SYSLOADMSG fails before KEYB_COMMAND runs)
- [ ] `KEYB GR,,KEYBOARD.SYS` — explicit file, non-US layout
- [ ] `KEYB UK,850,KEYBOARD.SYS /ID:166` — with code page and ID
- [ ] `KEYB` — show current layout

#### ASSIGN ✅ done
- [x] `ASSIGN B=A` + `DIR B:` verify + `ASSIGN` clear (test_assign_subst_join.sh)

#### JOIN ✅ done
- [x] `JOIN B: A:\JOINDIR` + list + verify BJOIN.TXT + `JOIN B: /D` (test_assign_subst_join.sh)

#### SUBST ✅ done
- [x] `SUBST D: A:\SUBSTDIR` + `SUBST` list + `SUBST D: /D` (test_assign_subst_join.sh)

#### FASTOPEN
- [ ] `FASTOPEN C:=50` — cache 50 entries
- [ ] `FASTOPEN C:=50 /X` — use expanded memory

#### GRAPHICS
- [ ] `GRAPHICS` — load default (GRAPHICS.PRO)
- [ ] `GRAPHICS COLOR4 /R` — color4 reversed
- [ ] `GRAPHICS HPDEFAULT /B` — with background

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
