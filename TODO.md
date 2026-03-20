# MS-DOS 4.0 Build — TODO

## UMB Support (Upper Memory Blocks)

Goal: add UMB support to our MS-DOS 4.0 fork so device drivers and TSRs can be loaded into upper memory (640K–1MB), freeing conventional memory. Backporting the MS-DOS 5.0 concept.

Reference implementations (for study, not copying):
- **FreeDOS kernel** — UMB link/unlink, `DOS=UMB`, `DEVICEHIGH`, arena chain management.
- **JEMM** (Japheth's EMM386) — UMB provider via INT 2Fh/AX=4310h (XMS), V86 page mapping.

### Phase 1: EMM386 — UMB provider

- [ ] Study how UMBs are exposed: INT 2Fh/AX=4310h → XMS driver entry, functions 10h (Request UMB) / 11h (Release UMB)
- [ ] Study our EMM386 source (`MEMM/`) — V86 mode setup, page table management, existing EMS page frame mapping
- [ ] Add XMS UMB allocation (function 10h): map available upper memory regions (C000–EFFF gaps) as allocatable UMBs
- [ ] Add XMS UMB release (function 11h)
- [ ] UMB region detection: scan adapter ROM signatures (55AA) and video RAM for free gaps; configurable (e.g., `DEVICE=EMM386.SYS I=C800-EFFF`)
- [ ] Test: verify XMS UMB functions work from a test program under QEMU

### Phase 2: MSDOS kernel — UMB-aware memory management

- [ ] Study MS-DOS 5.0+ MCB arena chain structure: how UMBs are linked as a second arena above conventional memory
- [ ] Study FreeDOS kernel source for the UMB link/unlink mechanism
- [ ] `DOS=UMB` CONFIG.SYS directive: kernel calls XMS to request UMBs at init and links them into the MCB chain
- [ ] `DOS=HIGH,UMB` combination
- [ ] MCB chain linking: create MCB headers for UMB regions and chain them to end of conventional memory arena
- [ ] INT 21h/AH=58h subfunction 03h (Set UMB Link State) and 02h (Get UMB Link State)
- [ ] Test: verify `MEM` shows upper memory region, allocation from UMBs works

### Phase 3: COMMAND.COM / CONFIG.SYS — DEVICEHIGH, LOADHIGH

- [ ] `DEVICEHIGH=` CONFIG.SYS directive: load device drivers into UMBs (try UMB first, fall back to conventional)
- [ ] `LOADHIGH` / `LH` COMMAND.COM built-in: load TSRs into UMBs
- [ ] `MEM /C` or similar: show which programs/drivers are in upper memory
- [ ] Test: boot with `DOS=UMB`, `DEVICEHIGH=ANSI.SYS`, verify ANSI.SYS loads into UMA

### Phase 4: HMA — Load DOS High

Load MSDOS.SYS kernel into the HMA (first 64K-16 bytes above 1MB), freeing ~40-50K of conventional memory. Requires A20 gate control and XMS driver.

- [ ] Study HMA mechanics: A20 gate, FFFF:xxxx wrapping, the 64K-16 byte limit
- [ ] XMS prerequisite: EMM386 or minimal HIMEM.SYS must provide functions 01h/02h (Request/Release HMA) and A20 control (03h–07h)
- [ ] Decide: add HMA/A20/XMS support to EMM386, or implement separate HIMEM.SYS
- [ ] `DOS=HIGH` CONFIG.SYS directive: request HMA, enable A20, relocate kernel to FFFF:0010+
- [ ] INT 21h dispatch fix-ups: entry points must remain in low memory or use A20-aware thunks
- [ ] Test: boot with `DOS=HIGH,UMB`, verify MEM shows DOS in HMA and conventional memory increases by ~45K

### Notes

- From-scratch implementation for fun/learning. FreeDOS and JEMM as architectural references only.
- Existing EMM386.SYS already does V86 mode and EMS page mapping — UMB/HMA extend this.
- Testing strategy: QEMU with ≥1MB RAM, verify via MEM output.

---

## Help Text vs Parameter Parsing Audit

Audit of all CMD tools for inconsistencies between `/? ` help text and actual parameter parsing.
All help strings were added by us in `dos4-enhancements` branch.

### Confirmed Inconsistencies (need fixing)

#### 1. DISKCOPY — `/V` advertised but not parsed (critical)
- **File**: `CMD/DISKCOPY/DISKCOPY.ASM` (help) + `CMD/DISKCOPY/DCOPYPAR.ASM` (parser)
- **Help says**: `DISKCOPY [d1:] [d2:] [/1] [/V]` with `/V  Verify that the information is copied correctly`
- **Parser has**: Only `/1` switch defined. SYSPARSE rejects `/V` → "Invalid switch - /V"
- **Note**: Already documented in KEYNOTES.md under "DISKCOPY / DISKCOMP Two-Drive QEMU E2E Patterns"
- **Fix options**: (a) remove `/V` from help text (simplest), or (b) implement `/V` verify pass in `DISKCOPY.ASM`
- [ ] Decide and fix

#### 2. SHARE — `/NC` parsed but not in help
- **File**: `CMD/SHARE/GSHARE2.ASM`
- **Parser has**: `/NC` switch (`N_SW DB "/NC",0 ; /NC: INDICATES no checking required`) — used to skip network-path checking at line 1835, 1852, 2933
- **Help shows**: Only `/F:filespace` and `/L:locks`; `/NC` is completely absent
- **Fix**: Add `/NC  Skip network path checking` line to `SHARE_HELP_STR`
- [ ] Add `/NC` to SHARE help text

#### 3. IFSFUNC — `/NAMES:n` in help but `NAMES=n` in parser
- **File**: `CMD/IFSFUNC/IFSINIT.ASM` (help) + `CMD/IFSFUNC/IFSPARSE.INC` (parser)
- **Help says**: `IFSFUNC [/NAMES:n]` (switch syntax with colon)
- **Parser has**: `DB "NAMES=",0` — a keyword (not a switch), parsed as `NAMES=n` positional keyword
- **Fix**: Change help to `IFSFUNC [NAMES=n]` to match actual syntax; OR verify that the `NAMES=` keyword path is even used/needed (this parameter was likely never widely used)
- [ ] Fix IFSFUNC help text

#### 4. FILESYS — `/d` lowercase in help
- **File**: `CMD/FILESYS/FILESYS.C`
- **Help says**: `FILESYS drive: /d` (lowercase)
- **Parser has**: `strcpy(p_swt1.p_keyorsw,"/D"+NULL)` (uppercase)
- **Impact**: DOS switches are case-insensitive so both work, but convention is uppercase in help text
- **Fix**: Change `printf("FILESYS drive: /d\r\n")` → `printf("FILESYS drive: /D\r\n")`
- [ ] Fix FILESYS help text

#### 5. CHKDSK — dead /? help code in CHKINIT.ASM
- **File**: `CMD/CHKDSK/CHKINIT.ASM` lines 241–271 (dead code)
- **Issue**: An older, briefer `/? ` help block was added in `Main_Init` in `CHKINIT.ASM` (`6a147b1`). Later `CHKDSK1.ASM` was added with a more complete help block at the actual entry point `CHKDSK:` (`a450ec6`). Since `CHKDSK1.ASM:CHKDSK` is the EXE entry, it checks `/? ` first and exits — the `CHKINIT.ASM` block is never reached.
- **Fix**: Remove the dead `/? ` check from `CHKINIT.ASM:Main_Init` (lines ~241–272)
- [ ] Remove dead CHKDSK /? code from CHKINIT.ASM

### Minor / Documentation Issues

#### 6. FDISK — source comment says "in K" but code/help use megabytes
- **File**: `CMD/FDISK/MAIN.C` line 138: `/* /PRI:m  Size of Primary DOS partition to create in K */`
- **Reality**: Help text says "megabytes", parser range is 1–4000, code calls `mbytes_to_cylinders()`. The "K" in the comment is wrong.
- **Fix**: Update the source comment (no behavior change needed)
- [ ] Fix stale source comment in FDISK/MAIN.C

#### 7. FORMAT — undocumented internal switches (intentional omission)
- **File**: `CMD/FORMAT/FORSWTCH.INC`
- **Undocumented**: `SWITCH_BACKUP`, `SWITCH_C`, `SWITCH_SELECT`, `SWITCH_AUTOTEST`, `SWITCH_Z` (ShipDisk)
- **Status**: These are internal/OEM switches not intended for end users. Omission from help is correct.
- No action needed.

---

## E2E Test Coverage Summary

All commands have functional E2E tests. kvikdos handles fast tests (`run_tests.sh`), QEMU+serial for disk/TSR/interactive tests. CI runs parallel jobs per test target (`.github/workflows/ci.yml`).

| Tool | Functional | Test location |
|------|-----------|---------------|
| COMMAND.COM | 48 kvikdos tests + COMMAND /? (QEMU) + CHCP show/set 850 | run_tests.sh §7, test_misc_qemu.sh, test_drivers_qemu.sh |
| MEM | basic + /PROGRAM + /DEBUG | run_tests.sh §6 |
| FIND | /V /N /C + errorlevel-2 + stdin pipe | run_tests.sh §6, test_misc_qemu.sh |
| FC | /A /B /C /N /W /L /LB /T /5 + error | run_tests.sh §6 (15 tests) |
| ATTRIB | +R -R +A -A /S | run_tests.sh §6 (8 tests) |
| COMP | identical/diff/hex/limit/not-found | run_tests.sh §6 (7 tests) |
| TREE | basic /F /A | run_tests.sh §6 (5 tests) |
| SORT | stdin /R /+N | run_tests.sh §6 (5 tests) |
| MORE | stdin, file | run_tests.sh §6 (3 tests) |
| DEBUG | R/E/D/F/H/C/M/S/A/U/N/W/L + G execute | run_tests.sh §6, test_debug_qemu.sh |
| EDLIN | 18 tests + /B binary mode | run_tests.sh §6 |
| XCOPY | /A /D /E /M /P /S /V /W — all v4.0 flags | run_tests.sh §6, test_prompt_yesno.sh |
| REPLACE | /A /P /R /S /U /W — all v4.0 flags | run_tests.sh §6, test_prompt_yesno.sh |
| GRAFTABL | 437 850 /STATUS | run_tests.sh §6 |
| LABEL | read-only + interactive set/delete | run_tests.sh §6, test_label.sh |
| ASSIGN | B=A redirect + clear | test_assign_subst_join.sh |
| SUBST | D: create/list/delete + file I/O (COPY, DIR, TYPE, pass-through) | test_assign_subst_join.sh |
| JOIN | B: join/list/verify/unjoin + file I/O (TYPE, COPY through joined path) | test_assign_subst_join.sh |
| EXE2BIN | 3 tests | run_tests.sh §6, test_share_nlsfunc_exe2bin.sh |
| CHKDSK | disk stats, /V, file alloc, /F orphan fix | test_misc_qemu.sh, test_chkdsk_fix.sh |
| FORMAT | 12 variants: /V /S /B /F:720 /T /4 /1 /8 /C /Z /SELECT /AUTOTEST | test_format.sh |
| SYS | boot verification | test_sys.sh |
| DISKCOPY | /1, /V parse error | test_diskcomp_diskcopy.sh |
| DISKCOMP | /1, /8 | test_diskcomp_diskcopy.sh |
| BACKUP | /S /M /A /F /D /T /L | test_backup_restore.sh |
| RESTORE | /S /N /M /B /A /E /L /P | test_backup_restore.sh, test_prompt_yesno.sh |
| SHARE | /F /L /NC | test_share_nlsfunc_exe2bin.sh |
| NLSFUNC | install + CHCP interaction + CP switch | test_share_nlsfunc_exe2bin.sh, test_drivers_qemu.sh |
| APPEND | /E /X path /PATH:ON /PATH:OFF | test_append.sh |
| KEYB | US, GR, UK,850, FR /ID:189 | test_misc_qemu.sh |
| FDISK | /PRI /EXT /LOG /Q + primary-only (PTM P941) | test_fdisk.sh |
| PRINT | /D /B /Q /S /U /M /P /C /T | test_misc_qemu.sh |
| FASTOPEN | C:=50, /X | test_misc_qemu.sh |
| GRAPHICS | load, reload, /R /B /LCD /PB:STD | test_misc_qemu.sh |
| MODE | CON /STATUS, COLS/LINES, RATE/DELAY, COM1, LPT1, LPT1:=COM1: | test_misc_qemu.sh |
| RECOVER | file-mode recovery | test_recover.sh |
| IFSFUNC | install + already-installed | test_misc_qemu.sh |
| FILESYS | install (requires IFSFUNC) | test_misc_qemu.sh |
| SELECT | stub INT 16H + SELECT.EXE exec + error path | test_select.sh |
| Device drivers | ANSI.SYS, RAMDRIVE.SYS, VDISK.SYS, DISPLAY.SYS, SMARTDRV.SYS | test_drivers_qemu.sh |
| CONFIG.SYS | BUFFERS FILES LASTDRIVE BREAK STACKS FCBS INSTALL SHELL COUNTRY | test_drivers_qemu.sh |

## Bug Fix Regression Coverage

All bug fixes from dos4-enhancements branch have regression tests:

| Fix | Commit | Test |
|-----|--------|------|
| EDLIN /B (2 fixes) | 52f514b + 61b2920 | §6 ^Z test |
| FOR hang (ES corruption) | c70042b | §7 FOR loop timeout |
| SET/PROMPT hang (ES corruption) | ae75edf | §7 stress test (10 alternating calls) |
| FDISK R6001 + semicolon | a5a02a9 | test_fdisk.sh boot 2 (primary-only, PTM P941) |
| COMMAND parser crash (signed cmp) | 4ed73cb | §7 VER with argbuf at 0x80BD |
| COMMAND boot crash (help code path) | 58a0bb4 | test_misc_qemu.sh COMMAND /? |

## QEMU-only tests (won't migrate to kvikdos)

| Test | Reason |
|------|--------|
| test_format.sh | INT 13h formatting, BPB geometry, QMP disk swapping |
| test_sys.sh | Boot verification |
| test_diskcomp_diskcopy.sh | Track-by-track INT 13h |
| test_label.sh | FAT volume writes, interactive prompts |
| test_backup_restore.sh | Multi-disk, interactive prompts |
| test_append.sh | TSR persistence (INT 2Fh + KEEP_PROCESS) |
| test_assign_subst_join.sh | TSR drive table manipulation, multi-disk |
| test_share_nlsfunc_exe2bin.sh | TSR persistence |
| test_misc_qemu.sh | CHKDSK INT 13h; all TSR tools |
| test_debug_qemu.sh | DEBUG G needs INT 21h/AH=5Dh |
| test_recover.sh | FAT chain walking + INT 13h |
| test_chkdsk_fix.sh | FAT12 corruption + interactive Y/N |
| test_prompt_yesno.sh | Interactive Y/N prompts (XCOPY/REPLACE/RESTORE /P) |
| test_fdisk.sh | INT 13h disk partitioning |
| test_drivers_qemu.sh | CONFIG.SYS device drivers, boot verification |
| test_select.sh | INT 16H keyboard (BIOS), INT 10H video, screen_expect |
