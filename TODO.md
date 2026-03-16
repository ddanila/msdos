# MS-DOS 4.0 Build — TODO

## Done

- ~~COMMAND /?~~ — added to `INIT.ASM`
- ~~E2E functional tests (kvikdos)~~ — 167 tests in `run_tests.sh` (artifacts, checksums, /? help, functional: MEM, FIND, FC, TREE, SORT, COMP, ATTRIB, MORE, DEBUG, LABEL, EDLIN, REPLACE, XCOPY, GRAFTABL 437/850/STATUS, SUBST, JOIN, ASSIGN)
- ~~E2E functional tests (QEMU, built-ins + FIND)~~ — 51 tests in `test_builtins.sh` (built-in commands + FIND functional: basic, /C, /N, /V, case-sensitivity, errorlevel)
- ~~CI golden checksums~~ — dropped (not worth maintenance)
- ~~CHKDSK /?~~ — added
- ~~EXEPACK fix verification~~ — verified via `make test-help-qemu` (EXEPACK corruption check)

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

## E2E Tests — Per-Command, Per-Option Coverage

Goal: every command (external tool and COMMAND.COM built-in) and every
recognized option gets at least one integration test. Tests run the real
DOS binary under kvikdos or QEMU, check exit code and/or COM1/stdout output.

**Harness:** kvikdos for fast tests (`run_tests.sh`), QEMU+COM1 for disk-heavy ops (`test_builtins.sh`). CI runs `make test` → `test-sys` → `test-builtins` → `test-help-qemu`.

### COMMAND.COM built-in commands

Built-ins from `COMTAB` in `CMD/COMMAND/TDATA.ASM`.

| Command | Options / forms to test |
|---------|------------------------|
| DIR | no args (list CWD), path, `*` wildcard, `/W` (wide), `/P` (pause/page) |
| COPY | src dest, src+src2 dest (concat), `/A` (ASCII), `/B` (binary), `/V` (verify) |
| DEL / ERASE | single file, wildcard `*.*`, read-only file (should fail) |
| REN / RENAME | simple rename, rename to existing (should fail) |
| TYPE | text file, binary file (^Z mid-file) |
| MD / MKDIR | new dir, nested path, already-exists (should fail) |
| CD / CHDIR | relative, absolute, drive-rooted, no-arg (print CWD) |
| RD / RMDIR | empty dir, non-empty dir (should fail) |
| SET | set new var, overwrite var, clear var (`SET VAR=`), no-arg (print env) |
| PATH | set path, clear path (`PATH ;`), no-arg (print current) |
| PROMPT | set prompt string, clear prompt |
| DATE | no-arg (show date), set date |
| TIME | no-arg (show time), set time |
| VER | no args (shows version) |
| VOL | no-arg (current drive), `drive:` |
| BREAK | `BREAK ON`, `BREAK OFF`, no-arg (show state) |
| VERIFY | `VERIFY ON`, `VERIFY OFF`, no-arg (show state) |
| ECHO | `ECHO message`, `ECHO ON`, `ECHO OFF`, `ECHO.` (blank line) |
| CLS | no args |
| EXIT | exits secondary COMMAND shell |
| CTTY | redirect to device (e.g., `CTTY COM1`) |
| PAUSE | no-arg (waits for keypress) |
| REM | comment — no output |
| CHCP | no-arg (show code page), `CHCP nnn` (set code page) |
| TRUENAME | path (returns canonical full path) |
| CALL | `CALL batchfile [args]` — calls sub-batch, returns |
| GOTO | `GOTO label` in batch |
| SHIFT | shift batch `%1..%9` arguments left |
| IF | `IF EXIST file cmd`, `IF ERRORLEVEL n cmd`, `IF str==str cmd`, `IF NOT ...` |

#### ~~Strengthen Tier 1 built-in tests~~ — done (all 6 items verified functionally)
| FOR | `FOR %%v IN (set) DO cmd` |

### External CMD tools

#### FORMAT
- [ ] `FORMAT A: /V:LABEL` — format with volume label
- [ ] `FORMAT A: /S` — format + system files
- [ ] `FORMAT A: /B` — format + reserve space
- [ ] `FORMAT A: /F:720` — format specific size
- [ ] `FORMAT A: /T:80 /N:9` — explicit tracks+sectors
- [ ] `FORMAT A: /4` — 360K in 1.2MB drive
- [ ] `FORMAT A: /1` — single-sided
- [ ] `FORMAT A: /8` — 8 sectors/track
- [x] `FORMAT A: /?` — usage

#### ~~MEM~~ — done (basic totals, /?). Remaining: /PROGRAM, /DEBUG (need QEMU — kvikdos lacks full MCB chain)

#### CHKDSK
- [x] `CHKDSK` — check current drive (QEMU)
- [x] `CHKDSK A:` — check specific drive (QEMU)
- [ ] `CHKDSK A: /F` — fix errors
- [x] `CHKDSK A: /V` — verbose (all paths) (QEMU)
- [ ] `CHKDSK A:*.*` — check specific files
- [x] `CHKDSK /?` — usage

#### XCOPY
- [ ] `XCOPY src dest` — basic copy (copies 0 files under kvikdos; needs investigation)
- [ ] `XCOPY src dest /S` — include subdirs
- [ ] `XCOPY src dest /S /E` — include empty subdirs
- [ ] `XCOPY src dest /A` — archive flag only
- [ ] `XCOPY src dest /M` — archive flag, then clear
- [ ] `XCOPY src dest /D:01-01-88` — by date
- [ ] `XCOPY src dest /P` — prompt per file
- [ ] `XCOPY src dest /V` — verify
- [ ] `XCOPY src dest /W` — wait before start
- [x] `XCOPY /?` — usage

#### ~~ATTRIB~~ — done (show, +R, -R, +R+A combined, /?). Remaining: -A (needs QEMU — kvikdos hardcodes archive bit), /S (needs QEMU — kvikdos FindFirst doesn't recurse subdirs)

#### ~~FIND~~ — done (all options: basic, /V, /C, /N, /?)
#### ~~SORT~~ — done (all options: basic, /R, /+N, /?)
#### ~~TREE~~ — done (all options: basic, /F, /A, /?)

#### REPLACE
- [ ] `REPLACE src dest` — replace existing (needs wildcard FindFirst on absolute paths)
- [x] `REPLACE src dest /A` — add new files only
- [ ] `REPLACE src dest /P` — prompt
- [ ] `REPLACE src dest /R` — overwrite read-only
- [ ] `REPLACE src dest /S` — recurse subdirs
- [ ] `REPLACE src dest /U` — only if dest older
- [ ] `REPLACE src dest /W` — wait before start
- [x] `REPLACE /?` — usage

#### BACKUP
- [ ] `BACKUP C: A:` — basic backup
- [ ] `BACKUP C: A: /S` — include subdirs
- [ ] `BACKUP C: A: /M` — modified only
- [ ] `BACKUP C: A: /A` — append to existing set
- [ ] `BACKUP C: A: /D:01-01-88` — since date
- [ ] `BACKUP C: A: /T:00:00:00` — since time
- [ ] `BACKUP C: A: /L:backup.log` — write log
- [ ] `BACKUP C: A: /F` — format target if needed
- [x] `BACKUP /?` — usage

#### RESTORE
- [ ] `RESTORE A: C:` — restore all
- [ ] `RESTORE A: C: /S` — include subdirs
- [ ] `RESTORE A: C: /P` — prompt on conflicts
- [ ] `RESTORE A: C: /M` — modified only
- [ ] `RESTORE A: C: /N` — missing files only
- [ ] `RESTORE A: C: /B:01-01-88` — on or before date
- [ ] `RESTORE A: C: /A:01-01-88` — on or after date
- [ ] `RESTORE A: C: /E:12:00:00` — on or before time
- [ ] `RESTORE A: C: /L:12:00:00` — on or after time
- [x] `RESTORE /?` — usage

#### ~~FC~~ — done (basic, /B, /C, /L, /N, /W, /?). Remaining: /T (tab expansion), /5 (resync count)

#### DISKCOMP
- [ ] `DISKCOMP A: A:` — compare floppies
- [ ] `DISKCOMP A: A: /1` — single-sided only
- [ ] `DISKCOMP A: A: /8` — 8 sectors/track only
- [x] `DISKCOMP /?` — usage

#### DISKCOPY
- [ ] `DISKCOPY A: A:` — copy floppy
- [ ] `DISKCOPY A: A: /1` — single-sided
- [ ] `DISKCOPY A: A: /V` — verify after
- [x] `DISKCOPY /?` — usage

#### ~~COMP~~ — done (same files, different files, /?)

#### ~~LABEL~~ — done (show volume info, /?). Remaining: set/remove label (needs FCB delete, QEMU)

#### EDLIN
- [x] `EDLIN file` — open file (list + quit tested; insert mode needs Ctrl+C pipe fix)
- [ ] `EDLIN file /B` — binary (ignore ^Z)
- [x] `EDLIN /?` — usage

#### FDISK
- [ ] `FDISK` — interactive (smoke test: launches and exits)
- [ ] `FDISK /PRI` — create primary partition
- [x] `FDISK /?` — usage

#### ~~DEBUG~~ — done (launch+quit, register dump, /?). Remaining: load file (needs QEMU)
#### ~~MORE~~ — done (piped stdin, /?)

#### PRINT
- [ ] `PRINT /D:PRN file` — print to device
- [ ] `PRINT /T` — cancel queue
- [ ] `PRINT file /P` — add to queue
- [ ] `PRINT file /C` — remove from queue
- [ ] `PRINT /Q:5 file` — set queue size
- [x] `PRINT /?` — usage

#### SYS
- [ ] `SYS A:` — transfer system files
- [x] `SYS /?` — usage

#### KEYB
- [ ] `KEYB US` — load US keyboard
- [ ] `KEYB GR,,KEYBOARD.SYS` — explicit file
- [ ] `KEYB UK,850,KEYBOARD.SYS /ID:166` — with ID
- [ ] `KEYB` — show current layout
- [x] `KEYB /?` — usage

#### NLSFUNC
- [ ] `NLSFUNC` — load with default COUNTRY.SYS
- [ ] `NLSFUNC C:\COUNTRY.SYS` — explicit path
- [x] `NLSFUNC /?` — usage

#### GRAFTABL
- [x] `GRAFTABL 437` — load code page 437
- [x] `GRAFTABL 850` — load code page 850
- [x] `GRAFTABL /STATUS` — show current
- [x] `GRAFTABL /?` — usage

#### APPEND
- [ ] `APPEND /E` — init with environment
- [ ] `APPEND C:\DOS` — set append path
- [ ] `APPEND ;` — clear append path
- [ ] `APPEND /PATH:ON` — search appended dirs for explicit paths
- [ ] `APPEND /X` — extend to EXEC search
- [ ] `APPEND` — show current path
- [x] `APPEND /?` — usage

#### ASSIGN
- [ ] `ASSIGN A=B` — redirect A: to B: (TSR operation, needs QEMU)
- [ ] `ASSIGN` — clear all assignments (TSR operation, needs QEMU)
- [x] `ASSIGN /STATUS` — show assignments
- [x] `ASSIGN /?` — usage

#### JOIN
- [ ] `JOIN A: C:\FLOPPY` — join drive to path (needs QEMU)
- [ ] `JOIN A: /D` — remove join (needs QEMU)
- [x] `JOIN` — show current joins
- [x] `JOIN /?` — usage

#### SUBST
- [ ] `SUBST X: C:\LONGPATH` — create substitution (needs QEMU)
- [ ] `SUBST X: /D` — remove substitution (needs QEMU)
- [x] `SUBST` — show substitutions
- [x] `SUBST /?` — usage

#### SHARE
- [ ] `SHARE` — load with defaults
- [ ] `SHARE /F:4096 /L:40` — custom file space and locks
- [x] `SHARE /?` — usage

#### FASTOPEN
- [ ] `FASTOPEN C:=50` — cache 50 entries
- [ ] `FASTOPEN C:=50 /X` — use expanded memory
- [x] `FASTOPEN /?` — usage

#### GRAPHICS
- [ ] `GRAPHICS` — load default (GRAPHICS.PRO)
- [ ] `GRAPHICS COLOR4 /R` — color4 reversed
- [ ] `GRAPHICS HPDEFAULT /B` — with background
- [x] `GRAPHICS /?` — usage

#### MODE
- [ ] `MODE COM1: 9600,N,8,1` — configure serial
- [ ] `MODE LPT1: 80,66` — configure parallel
- [ ] `MODE CON COLS=80 LINES=25` — configure console
- [ ] `MODE CON RATE=30 DELAY=1` — typematic rate
- [ ] `MODE CON /STATUS` — show console status
- [x] `MODE /?` — usage

#### RECOVER
- [ ] `RECOVER A:file` — recover bad-sector file
- [ ] `RECOVER A:` — recover entire disk
- [x] `RECOVER /?` — usage

#### EXE2BIN
- [ ] `EXE2BIN prog.exe prog.bin` — basic conversion
- [x] `EXE2BIN /?` — usage

#### IFSFUNC
- [ ] `IFSFUNC` — load IFS driver (smoke test)
- [x] `IFSFUNC /?` — usage

#### FILESYS
- [ ] `FILESYS` — load (smoke test, internal tool)
- [x] `FILESYS /?` — usage

## ~~Add /? Usage Strings~~ — done (all external CMD tools)

