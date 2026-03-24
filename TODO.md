# MS-DOS 4.0 Build — TODO

## Watcom Migration (ACTIVE)

**End state:** All assembly and C compilation uses Open Watcom (WASM, wcc, wlink, wlib) natively. The full E2E test suite passes on the WASM-built floppy image. kvikdos remains only for the 7 pre-built DOS build utilities (BUILDMSG, NOSRVBLD, EXE2BIN, CONVERT, BUILDIDX, DBOF, MENUBLD) — eliminating those is a separate future effort, not part of this migration.

**Current status:** Assembly migration complete (53/53 modules, 52 WASM compat issues fixed). COMMAND.COM boots and runs (test B passes, issue #52 fixed). Remaining: MSDOS.SYS and IO.SYS runtime validation, then full E2E.

**Key findings:**
- COMMAND.COM issue #52 (L2029 `$M_GET_MSG_ADDRESS` unresolved) fixed: renamed `$M_HAS_$M_GET_MSG_ADDRESS` → `$M_HAS_GETMSGADDR` to avoid WASM `$M_` symbol parsing bug.
- `bin/strip-wasm-segs` OMF post-processor created: strips WASM's auto-generated empty `_TEXT`/`_DATA` SEGDEFs that break MS LINK segment ordering in DOSGROUP.
- `test_wasm_boot.sh` FAT12 patcher fixed: extends cluster chains when WASM binary is larger than MASM original (was silently truncating at 86 clusters).
- Both MS LINK and wlink produce bootable COMMAND.COM from WASM OBJs.
- Full `IF NOT` audit complete (60+ instances across 38 files) — no `IF NOT` patterns remain.
- MSDOS.SYS still hangs silently (test C) — not an `IF NOT` bug, needs QEMU `-d in_asm` trace debugging.
- IO.SYS prints "Non-System disk or disk error" (test F) — executes but fails disk I/O. Also not `IF NOT`.

### Phase 0A: wlink proof-of-concept ✅ DONE

Proved that both MS LINK and wlink produce bootable COMMAND.COM from WASM OBJs. The crash was not a linker issue — it was the MSGSERV.ASM `IF NOT` bug (issue #51). wlink migration remains a future convenience step.

- [x] Hand-convert `COMMAND.LNK` to wlink directive syntax (`COMMAND.wlink`)
- [x] Link WASM-built COMMAND.COM OBJs with wlink (native, no kvikdos)
- [x] Boot test: both MS LINK and wlink COMMAND.COM boot to date prompt
- [ ] ~~If test passes, also test MSDOS.SYS~~ (deferred — MSDOS.SYS has its own runtime bugs)

**wlink response file format** (completely different from MS LINK):
```
FORMAT DOS
FILE obj1.obj, obj2.obj
NAME output.exe
OPTION MAP=output.map
OPTION STACK=50000
OPTION DOSSEG
LIBRARY lib1.lib
```
vs MS LINK positional: `obj1+obj2, output.exe, output.map, lib1 /STACK:50000;`

**If proof-of-concept succeeds:**
- [ ] Write `bin/wlink-mslink` wrapper — translates MS LINK response file format to wlink directives on the fly. Makes the switch transparent to the Makefile (`LINK := $(BIN)/wlink-mslink`). All 51 .LNK files work without modification.
- [ ] Handle /EXEPACK gap: 4 targets use it (SELECT, FIND, FDISK, EXE2BIN). wlink has no equivalent. Options: (a) skip packing — binaries slightly larger but functional, (b) use existing `bin/fix-exepack` as a post-link step.
- [ ] Verify segment ordering for kernel binaries (MSDOS.SYS, IO.SYS) — layout is critical.

**wlink flag mapping:**
| MS LINK | wlink | Notes |
|---------|-------|-------|
| `/MAP` | `OPTION MAP` | |
| `/DOSSEG` | `OPTION DOSSEG` | |
| `/STACK:N` | `OPTION STACK=N` | |
| `/NOI` | `OPTION CASEEXACT` | |
| `/EXEPACK` | none | Skip or post-process |
| `/NOE` | none | May not be needed |

### Cleanup: source hygiene (3 items, one commit each)

No divergence concerns — upstream hasn't accepted PRs in 35 years.

**1. Strip `^Z` (0x1A) from all source files**
827 ASM/INC files have DOS `^Z` EOF marker causing W249 warnings on every file.
- [ ] Python bulk strip: `data.replace(b'\x1a', b'')` across the submodule
- [ ] Verify build still passes (W249 warnings gone)

**2. Fix `.gitattributes` for MSG files**
`*.MSG text eol=crlf` causes perpetually "modified" MSG files (CRLF-in-blob conflict). Change to `*.MSG binary` + renormalize.
- [ ] Update `.gitattributes`: `*.MSG binary`
- [ ] `git add --renormalize .` to fix blobs

**3. Delete commented-out SUBTTL/TITLE directives**
37 lines across 13 files changed from `SUBTTL ...` to `;; SUBTTL ...` for WASM compat. They serve no purpose — just delete them.
- [ ] Remove all `;; SUBTTL` and `;; TITLE` lines

### Phase 0B: MSDOS.SYS and IO.SYS runtime debugging

Full `IF NOT` audit complete — all 60+ instances converted to `EQ 0`. The remaining failures are **not** `IF NOT` bugs.

**MSDOS.SYS (test C):** Hangs silently after "Booting from Floppy..." — kernel starts but crashes before producing any output. Needs QEMU `-d in_asm` trace to find crash point.

**IO.SYS (test F):** Prints "Non-System disk or disk error" — IO.SYS executes far enough to display this message but fails to read MSDOS.SYS from disk. Likely a BPB/disk parameter or segment layout issue.

- [x] Audit kernel source for remaining `IF NOT` patterns — done, all converted
- [ ] Debug MSDOS.SYS crash: QEMU `-d in_asm` trace, same methodology as COMMAND.COM
- [ ] Debug IO.SYS disk read failure (test F) — compare MASM/WASM SYSINIT disk read code
- [ ] Fix and validate MSDOS.SYS boot (test C)
- [ ] Fix and validate IO.SYS (test F)
- [x] Fix `test_wasm_boot.sh` cluster overflow bug (COMMAND.COM truncation) — FAT chain extension + correct cluster range for 1.44MB
- [x] Fix issue #52: `$M_GET_MSG_ADDRESS` L2029 — renamed flag to `$M_HAS_GETMSGADDR`

### Phase 1: Individual binary validation under kvikdos (fast, no QEMU)

kvikdos can run COMMAND.COM (`/C` mode), any standalone .COM/.EXE, and has spawn support (8 levels deep). Much faster than QEMU for individual binary testing.

**COMMAND.COM under kvikdos:**
- [ ] Run WASM-built COMMAND.COM under kvikdos: `kvikdos --dos-version=4 COMMAND.COM /C VER` — if it prints "MS-DOS Version 4.00", transient init works.
- [ ] Run built-in commands: `COMMAND.COM /C DIR`, `/C COPY`, `/C SET FOO=BAR`, `/C FOR %X IN (A B C) DO ECHO %X` — tests TRANCODE dispatch table and the OFFSET bug's blast radius.
- [ ] Run Section 7 of run_tests.sh (COMMAND.COM built-in E2E) against WASM binary — covers 48 built-in command tests.
- [ ] If any built-in crashes, cross-reference the COMTAB dispatch offset with the OBJ analysis.

**Individual CMD utilities under kvikdos:**
- [ ] Run /? smoke tests (Section 4 of run_tests.sh) against WASM-built binaries — all 37 tools.
- [ ] Run Section 6 functional tests (FIND, FC, SORT, COMP, ATTRIB, MORE, DEBUG, EDLIN, etc.) against WASM-built binaries.

**Approach:** Modify `run_tests.sh` or create a wrapper that points `$SRC` to the WASM build output directory. No floppy image needed.

### Phase 2: Minimal QEMU boot (boot sector + IO.SYS + MSDOS.SYS + COMMAND.COM)

QEMU tests the boot chain that kvikdos cannot emulate.

- [ ] Test B: MASM core + WASM COMMAND.COM — validates COMMAND.COM in real DOS
- [ ] Test C: MASM BIOS + WASM MSDOS.SYS — validates kernel init, INT 21h dispatch
- [ ] Test D: WASM MSDOS.SYS + WASM COMMAND.COM — validates kernel ↔ shell interaction
- [ ] Test E: full WASM — validates complete boot chain
- [ ] Use `tests/test_wasm_boot.sh` (already exists) for all of the above

### Phase 3: Full E2E test suite on WASM build

- [ ] `make deploy` with WASM-built floppy image
- [ ] `make test` (kvikdos fast tests — reuses Sections 1–7)
- [ ] Full QEMU E2E test suite: FORMAT, SYS, FDISK, DISKCOMP, DISKCOPY, drivers, BACKUP/RESTORE, etc.
- [ ] Binary size comparison: MASM vs WASM for all outputs (track regressions)

### Phase 4: C compiler + library manager migration

- [ ] Migrate C-based tools (FDISK, BACKUP, RESTORE, REPLACE, FC, FILESYS, SELECT) from CL.EXE to wcc
- [ ] Replace LIB.EXE with wlib (already vendored) for MAPPER.LIB, EMMLIB.LIB, COMSUBS.LIB, SERVICES.LIB
- [ ] Verify E2E tests pass with wcc-compiled and wlib-built binaries

### Phase 5: CI pipeline update

- [ ] Update `.github/workflows/ci.yml` to use native Open Watcom toolchain
- [ ] Verify CI passes on both Linux x64 and macOS ARM64
- [ ] Update build documentation (README.md dependencies section)

### Remaining kvikdos dependencies (post-migration)

Even after Phases 0–4, these pre-built DOS tools from `TOOLS/` still require kvikdos:

| Tool | Purpose | Invocations |
|------|---------|-------------|
| EXE2BIN.EXE | EXE → flat binary | MSBOOT, ~10 CMD utilities |
| CONVERT.EXE | EXE → COM with relocating stub | CHKDSK, RECOVER, EDLIN, PRINT, FORMAT, DEBUG, RESTORE, BACKUP |
| BUILDIDX.EXE | Build message index (USA-MS.IDX) | 1 (messages target) |
| BUILDMSG.EXE | Generate CL/CTL from SKL | ~30 CMD utilities |
| NOSRVBLD.EXE | Generate CL1 from SKL (class 1) | BOOT, DOS, FDISK5, XMAEM |
| DBOF.EXE | Binary → INC offset table | BOOT (MSBOOT.BIN → BOOT.INC), FDISK (FDBOOT) |
| MENUBLD.EXE | FDISK menu data → C source | 1 (FDISK) |

These are Microsoft-proprietary build utilities with no Open Watcom equivalent. Options for full kvikdos elimination (future, not blocking):
- Rewrite as Python/native scripts (BUILDIDX, DBOF, MENUBLD are simple format converters)
- EXE2BIN: Open Watcom's `wstrip` or custom script (MZ header removal)
- CONVERT: custom native reimplementation (small relocating stub generator)
- BUILDMSG/NOSRVBLD: most complex — SKL message compiler, would need reverse-engineering

---

## INT 21h Unit Test (standalone, master branch)

Goal: a standalone `.COM` test harness that exercises every INT 21h function and reports pass/fail. Runs on real DOS (QEMU) and validates the kernel independently of the toolchain. Can be built and used on master branch — not tied to the Watcom migration.

**Source of truth:** `DOS/MS_TABLE.ASM` dispatch table (109 entries, AH=00h–6Ch). Each handler's expected behavior must be verified from the kernel source code, not from generic DOS documentation.

**Design:**
- Single `.ASM` file → `.COM` (no LINK, no message framework, no dependencies)
- Self-contained: creates its own test files, cleans up after itself
- Output: one line per test group to serial/console (`PASS: File I/O` or `FAIL: File I/O - AH=3Ch`)
- Exit code: 0 = all pass, 1 = any failure
- Usable in CI: boot QEMU with CTTY AUX, capture serial, grep for FAIL

**Test groups (by INT 21h AH function):**

### Core file I/O (17 functions)
| AH | Test |
|----|------|
| 3Ch | Create file, verify handle returned |
| 3Dh | Open existing file (read, write, r/w modes) |
| 3Eh | Close handle, verify double-close fails |
| 3Fh | Read bytes, verify count and content |
| 40h | Write bytes, read back and compare |
| 41h | Delete file, verify open fails after |
| 42h | Seek (beginning, current, end), verify position |
| 43h | Get/set file attributes (readonly, archive) |
| 45h | Dup handle, write via dup, read via original |
| 46h | Dup2 (force dup), verify redirect works |
| 56h | Rename file, verify old name gone + new exists |
| 57h | Get/set file date/time, verify roundtrip |
| 5Ah | Create temp file, verify unique name |
| 5Bh | Create new (fail if exists), verify error on second call |
| 5Ch | Lock region, verify concurrent access blocked |
| 68h | Commit (flush), verify no error |
| 6Ch | Extended open/create (DOS 4.0+), verify action codes |

### Directory (4 functions)
| AH | Test |
|----|------|
| 39h | Mkdir, verify exists |
| 3Bh | Chdir into it, verify with 47h |
| 47h | Get current dir, verify path string |
| 3Ah | Rmdir, verify gone |

### Find first/next (2 functions)
| AH | Test |
|----|------|
| 4Eh | Find first with wildcard, verify DTA filled |
| 4Fh | Find next, verify iteration + termination |

### Memory management (4 functions)
| AH | Test |
|----|------|
| 48h | Allocate block, verify segment returned |
| 4Ah | Resize block (grow and shrink) |
| 49h | Free block, verify double-free fails |
| 58h | Get/set allocation strategy, verify roundtrip |

### Process control (testable subset)
| AH | Test |
|----|------|
| 4Ch | Exit with code (implicitly tested — the test itself exits) |
| 4Dh | Get child exit code (after spawning a tiny helper) |
| 62h | Get PSP, verify segment matches CS-10h for .COM |
| 30h | Get DOS version, verify major=4 |
| 2Eh | Set verify flag, 54h get verify — roundtrip |

### Console I/O (testable via serial/CTTY AUX)
| AH | Test |
|----|------|
| 02h | Output char, verify echo |
| 09h | Print $-terminated string |
| 06h | Direct console I/O (output mode) |
| 0Bh | Check input status (should be "no input ready") |

### Date/time
| AH | Test |
|----|------|
| 2Ah | Get date, verify year ≥ 1980 |
| 2Ch | Get time, verify hours 0-23 |

### System info
| AH | Test |
|----|------|
| 19h | Get default drive, verify 0-25 range |
| 0Eh | Set default drive, 19h get — roundtrip |
| 1Ah | Set DTA, 2Fh get DTA — roundtrip |
| 25h | Set interrupt vector, 35h get — roundtrip |
| 33h | Get/set Ctrl-C check — roundtrip |
| 65h | Get extended country info (NLS), verify buffer filled |
| 66h | Get global code page, verify non-zero |
| 69h | Get disk serial number, verify structure |

### FCB legacy (selective — verify not broken)
| AH | Test |
|----|------|
| 29h | Parse filename into FCB, verify fields |
| 11h/12h | FCB find first/next, verify DTA |

### Not tested (by design)
- 00h, 31h (terminate/TSR — can't return from these)
- 4Bh (exec — complex, tested separately in E2E suite)
- 5Dh-5Fh (network — not relevant)
- 03h-05h (aux/printer — hardware dependent)
- IOCTL 44h (device-specific, too many subfunctions)

---

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
