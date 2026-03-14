# MS-DOS 4.0 Build — TODO

## E2E Tests — Per-Command, Per-Option Coverage

Goal: every command (external tool and COMMAND.COM built-in) and every
recognized option gets at least one integration test. Tests run the real
DOS binary under kvikdos or QEMU, check exit code and/or COM1/stdout output.

**Harness setup:**
- [x] Add CI step for `make test-sys`.
- External tools (MEM, XCOPY, etc.): invoke via kvikdos directly where
  possible; fall back to QEMU+COM1 for disk-heavy operations.
- Built-ins: invoke as `COMMAND /C "CMD args"` via kvikdos or QEMU.
- For `/?` tests: check that the tool prints something and exits 0. Add as fast smoke tests in CI (kvikdos invocation, very cheap to run).
- For functional tests: set up a minimal disk image with known files/state,
  run command, inspect result (file presence, content, exit code, output).
- [ ] Add CI job that pins `MS-DOS` submodule to `main` and verifies
  `tests/golden.sha256` still passes (ensures toolchain works with unmodified source).

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
- [ ] `FORMAT A: /?` — usage

#### MEM
- [ ] `MEM` — basic output (totals)
- [ ] `MEM /PROGRAM` — show loaded programs
- [ ] `MEM /DEBUG` — show internal drivers
- [ ] `MEM /?` — usage

#### CHKDSK
- [ ] `CHKDSK` — check current drive
- [ ] `CHKDSK A:` — check specific drive
- [ ] `CHKDSK A: /F` — fix errors
- [ ] `CHKDSK A: /V` — verbose (all paths)
- [ ] `CHKDSK A:*.*` — check specific files
- [ ] `CHKDSK /?` — usage

#### XCOPY
- [ ] `XCOPY src dest` — basic copy
- [ ] `XCOPY src dest /S` — include subdirs
- [ ] `XCOPY src dest /S /E` — include empty subdirs
- [ ] `XCOPY src dest /A` — archive flag only
- [ ] `XCOPY src dest /M` — archive flag, then clear
- [ ] `XCOPY src dest /D:01-01-88` — by date
- [ ] `XCOPY src dest /P` — prompt per file
- [ ] `XCOPY src dest /V` — verify
- [ ] `XCOPY src dest /W` — wait before start
- [ ] `XCOPY /?` — usage

#### ATTRIB
- [ ] `ATTRIB file` — show attributes
- [ ] `ATTRIB +R file` — set read-only
- [ ] `ATTRIB -R file` — clear read-only
- [ ] `ATTRIB +A file` — set archive
- [ ] `ATTRIB -A file` — clear archive
- [ ] `ATTRIB +R +A file /S` — recursive subdirs
- [ ] `ATTRIB /?` — usage

#### FIND
- [ ] `FIND "string" file` — basic search
- [ ] `FIND /V "string" file` — non-matching lines
- [ ] `FIND /C "string" file` — count only
- [ ] `FIND /N "string" file` — with line numbers
- [ ] `FIND /?` — usage

#### SORT
- [ ] `SORT < file` — sort stdin
- [ ] `SORT /R < file` — reverse sort
- [ ] `SORT /+3 < file` — sort by column 3
- [ ] `SORT /?` — usage

#### TREE
- [ ] `TREE` — directory tree
- [ ] `TREE /F` — include filenames
- [ ] `TREE /A` — ASCII chars (no line-drawing)
- [ ] `TREE /?` — usage

#### REPLACE
- [ ] `REPLACE src dest` — replace existing
- [ ] `REPLACE src dest /A` — add new files only
- [ ] `REPLACE src dest /P` — prompt
- [ ] `REPLACE src dest /R` — overwrite read-only
- [ ] `REPLACE src dest /S` — recurse subdirs
- [ ] `REPLACE src dest /U` — only if dest older
- [ ] `REPLACE src dest /W` — wait before start
- [ ] `REPLACE /?` — usage

#### BACKUP
- [ ] `BACKUP C: A:` — basic backup
- [ ] `BACKUP C: A: /S` — include subdirs
- [ ] `BACKUP C: A: /M` — modified only
- [ ] `BACKUP C: A: /A` — append to existing set
- [ ] `BACKUP C: A: /D:01-01-88` — since date
- [ ] `BACKUP C: A: /T:00:00:00` — since time
- [ ] `BACKUP C: A: /L:backup.log` — write log
- [ ] `BACKUP C: A: /F` — format target if needed
- [ ] `BACKUP /?` — usage

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
- [ ] `RESTORE /?` — usage

#### FC
- [ ] `FC file1 file2` — ASCII diff
- [ ] `FC /B file1 file2` — binary diff
- [ ] `FC /C file1 file2` — case-insensitive
- [ ] `FC /L file1 file2` — explicit ASCII mode
- [ ] `FC /N file1 file2` — line numbers
- [ ] `FC /T file1 file2` — no tab expansion
- [ ] `FC /W file1 file2` — compress whitespace
- [ ] `FC /5 file1 file2` — custom resync count
- [ ] `FC /?` — usage

#### DISKCOMP
- [ ] `DISKCOMP A: A:` — compare floppies
- [ ] `DISKCOMP A: A: /1` — single-sided only
- [ ] `DISKCOMP A: A: /8` — 8 sectors/track only
- [ ] `DISKCOMP /?` — usage

#### DISKCOPY
- [ ] `DISKCOPY A: A:` — copy floppy
- [ ] `DISKCOPY A: A: /1` — single-sided
- [ ] `DISKCOPY A: A: /V` — verify after
- [ ] `DISKCOPY /?` — usage

#### COMP
- [ ] `COMP file1 file2` — compare files (same)
- [ ] `COMP file1 file2` — compare files (different)
- [ ] `COMP /?` — usage

#### LABEL
- [ ] `LABEL` — prompt for label
- [ ] `LABEL A:MYLABEL` — set label directly
- [ ] `LABEL A:` — remove label (empty)
- [ ] `LABEL /?` — usage

#### EDLIN
- [ ] `EDLIN file` — open file for editing
- [ ] `EDLIN file /B` — binary (ignore ^Z)
- [ ] `EDLIN /?` — usage

#### FDISK
- [ ] `FDISK` — interactive (smoke test: launches and exits)
- [ ] `FDISK /PRI` — create primary partition
- [ ] `FDISK /?` — usage

#### DEBUG
- [ ] `DEBUG` — launch and quit (`Q` command)
- [ ] `DEBUG file` — load file
- [ ] `DEBUG /?` — usage

#### MORE
- [ ] `MORE < file` — page through file
- [ ] `command | MORE` — piped input
- [ ] `MORE /?` — usage

#### PRINT
- [ ] `PRINT /D:PRN file` — print to device
- [ ] `PRINT /T` — cancel queue
- [ ] `PRINT file /P` — add to queue
- [ ] `PRINT file /C` — remove from queue
- [ ] `PRINT /Q:5 file` — set queue size
- [ ] `PRINT /?` — usage

#### SYS
- [ ] `SYS A:` — transfer system files
- [ ] `SYS /?` — usage

#### KEYB
- [ ] `KEYB US` — load US keyboard
- [ ] `KEYB GR,,KEYBOARD.SYS` — explicit file
- [ ] `KEYB UK,850,KEYBOARD.SYS /ID:166` — with ID
- [ ] `KEYB` — show current layout
- [ ] `KEYB /?` — usage

#### NLSFUNC
- [ ] `NLSFUNC` — load with default COUNTRY.SYS
- [ ] `NLSFUNC C:\COUNTRY.SYS` — explicit path
- [ ] `NLSFUNC /?` — usage

#### GRAFTABL
- [ ] `GRAFTABL 437` — load code page 437
- [ ] `GRAFTABL 850` — load code page 850
- [ ] `GRAFTABL /STATUS` — show current
- [ ] `GRAFTABL /?` — usage

#### APPEND
- [ ] `APPEND /E` — init with environment
- [ ] `APPEND C:\DOS` — set append path
- [ ] `APPEND ;` — clear append path
- [ ] `APPEND /PATH:ON` — search appended dirs for explicit paths
- [ ] `APPEND /X` — extend to EXEC search
- [ ] `APPEND` — show current path
- [ ] `APPEND /?` — usage

#### ASSIGN
- [ ] `ASSIGN A=B` — redirect A: to B:
- [ ] `ASSIGN` — clear all assignments
- [ ] `ASSIGN /STATUS` — show assignments
- [ ] `ASSIGN /?` — usage

#### JOIN
- [ ] `JOIN A: C:\FLOPPY` — join drive to path
- [ ] `JOIN A: /D` — remove join
- [ ] `JOIN` — show current joins
- [ ] `JOIN /?` — usage

#### SUBST
- [ ] `SUBST X: C:\LONGPATH` — create substitution
- [ ] `SUBST X: /D` — remove substitution
- [ ] `SUBST` — show substitutions
- [ ] `SUBST /?` — usage

#### SHARE
- [ ] `SHARE` — load with defaults
- [ ] `SHARE /F:4096 /L:40` — custom file space and locks
- [ ] `SHARE /?` — usage

#### FASTOPEN
- [ ] `FASTOPEN C:=50` — cache 50 entries
- [ ] `FASTOPEN C:=50 /X` — use expanded memory
- [ ] `FASTOPEN /?` — usage

#### GRAPHICS
- [ ] `GRAPHICS` — load default (GRAPHICS.PRO)
- [ ] `GRAPHICS COLOR4 /R` — color4 reversed
- [ ] `GRAPHICS HPDEFAULT /B` — with background
- [ ] `GRAPHICS /?` — usage

#### MODE
- [ ] `MODE COM1: 9600,N,8,1` — configure serial
- [ ] `MODE LPT1: 80,66` — configure parallel
- [ ] `MODE CON COLS=80 LINES=25` — configure console
- [ ] `MODE CON RATE=30 DELAY=1` — typematic rate
- [ ] `MODE CON /STATUS` — show console status
- [ ] `MODE /?` — usage

#### RECOVER
- [ ] `RECOVER A:file` — recover bad-sector file
- [ ] `RECOVER A:` — recover entire disk
- [ ] `RECOVER /?` — usage

#### EXE2BIN
- [ ] `EXE2BIN prog.exe prog.bin` — basic conversion
- [ ] `EXE2BIN /?` — usage

#### IFSFUNC
- [ ] `IFSFUNC` — load IFS driver (smoke test)
- [ ] `IFSFUNC /?` — usage

#### FILESYS
- [ ] `FILESYS` — load (smoke test, internal tool)
- [ ] `FILESYS /?` — usage

## Add /? Usage Strings to CMD Tools

All tools should print usage when invoked with `/?`, like MS-DOS 6.22.
Changes go in the `dos4-enhancements` branch of the MS-DOS fork.
- ASM tools: check PSP:81h for `/?`, print $-terminated string via INT 21h/09h, exit via INT 21h/4Ch.
- C tools: `strcmp` argv[1] with `"/?"`; print via `printf`; `exit(0)`.
- Keep help strings compact (≤24 lines) to fit a standard 25-line screen.

### Pending usage strings

#### RECOVER (RECOVER.ASM)
```
RECOVER [drive:][path]filename
RECOVER drive:
```

#### COMMAND (INIT.ASM / CPARSE.ASM)
```
COMMAND [[drive:]path] [device] [/E:nnnnn] [/P] [/MSG] [/C string]

  /E:nnnnn   Set environment size in bytes
  /P         Make permanent (no EXIT)
  /MSG       Store error messages in memory (for floppy use)
  /C string  Run command string then return
```

#### FDISK (PARSE.H / _PARSE.ASM)
```
FDISK [/PRI[:n]] [/EXT[:n]] [/LOG[:n]] [/Q]

  /PRI[:n]   Create primary DOS partition (size in MB or %)
  /EXT[:n]   Create extended DOS partition
  /LOG[:n]   Create logical drive in extended partition
  /Q         Quiet (no prompts); used with above switches
```

#### DEBUG
```
DEBUG [[drive:][path]filename [arglist]]
```
Interactive debugger — no command-line switches; all control via
interactive commands (A, D, E, G, N, P, Q, R, T, U, W, etc.).

#### FILESYS / IFSFUNC
Internal TSR utilities — no user-facing `/?` help planned.

#### CHKDSK — SKIPPED (see note below)

### Implementation status (dos4-enhancements branch)

- [x] **MEM** — `main(argc, argv)` in `MEM.C`; insert before `sysloadmsg`. Uses `printf`+`exit(0)`.
- [x] **ATTRIB** — `inmain(line)` in `ATTRIB.C`; scan raw command tail, insert before `main(line)` call.
- [x] **XCOPY** — `MAIN PROC FAR` in `XCOPY.ASM`; scan DS:81h at EXE startup (DS=PSP), `MOV AX,DGROUP; MOV DS,AX` to reach help string, print+exit.
- [x] **FORMAT** — `Main_Init` in `FORINIT.ASM`; after `Set_Data_Segment`+`GetCurrentPSP`, push ES, set ES=PSP, scan ES:81h, pop ES, print+exit.
- [x] **FC** — `main(c, v)` in `FC.C`; insert before version check. `stdio.h` already included via `tools.h`.
- [x] **JOIN** — `main(c, v)` in `JOIN.C`; insert before `load_msg()`. Compile with `-IC:\H` for `cds.h`.
- [x] **SUBST** — `main(c, v)` in `SUBST.C`; insert before `load_msg()`. Compile with `-IC:\H`.
- [x] **REPLACE** — `main(argc, argv)` in `REPLACE.C`; added `stdio.h`+`stdlib.h` includes, insert before `load_msg()`.
- [x] **SORT** — `SORT:` in `SORT.ASM`; EXE, DS=PSP at entry. Help string before entry label; `push cs/pop ds` before print. Build needs `-I. -IC:\INC` and separate `SORTMES.ASM` assembly.
- [x] **FIND** — `START:` in `FIND.ASM`; EXE, DS=PSP at entry (DS changed to CS immediately after). Check before `mov ax,cs`. Build needs `-I. -IC:\INC` (for `find.inc` macros like `ljc`).
- [x] **NLSFUNC** — `MAIN PROC FAR` in `NLSFUNC.ASM`; EXE, DS=PSP at entry. Help string in `NLS_DATA` segment; switch DS to `NLS_DATA` before print.
- [x] **TREE** — `BEGIN PROC` in `TREE.ASM`; COM via EXE2BIN, CS=DS=PSP throughout. `OFFSET label` gives correct segment-relative address directly.
- [x] **BACKUP** — `main(argc, argv)` in `BACKUP.C`; added `stdio.h` include; insert after no local vars, before `init()`. Uses `printf`+`exit(0)`.
- [x] **RESTORE** — `void main(argc, argv)` in `RESTORE.C`; added `stdio.h`, `string.h`, `stdlib.h` includes; insert after local variable declarations, before `sysloadmsg()`. Uses `printf`+`exit(0)`.
- [x] **DISKCOMP** — `BEGIN PROC NEAR` in `DISKCOMP.ASM`; COM file (ORG 100H), CS=DS=PSP. Help string in data area; scan PSP:81h before `MOV SP, OFFSET MY_STACK_PTR`.
- [x] **DISKCOPY** — `BEGIN PROC NEAR` in `DISKCOPY.ASM`; COM file (ORG 100H), CS=DS=PSP. Help string in data area; scan PSP:81h before `MOV SP, OFFSET MY_STACK_PTR`.
- [x] **GRAFTABL** — `MAIN PROC NEAR / ENTRY_POINT` in `GRTAB.ASM`; COM file, jumped to from ORG 100H in `GRTABHAN.ASM`. CS=DS=PSP at entry. Help string in data area before `MAIN PROC`.
- [x] **LABEL** — `Main_Begin Proc Near` in `LABEL.ASM`; COM file. Help string before `HEADER` macro invocation; scan before `mov sp,offset End_Stack_Area`.
- [x] **COMP** — `init proc near` in `COMP2.ASM`; COM file, jumped to from `START:` in `COMP1.ASM`. Help string before `init proc`; scan at start of `init`.
- [x] **ASSIGN** — `INITIALIZATION:` in `ASSGMAIN.ASM`; COM file, jumped to from `ENTRY_POINT:` at ORG 100H. Help string before `INITIALIZATION:`; scan checks DS:[SI], uses `PUSH CS / POP DS` pattern (but COM so CS=DS — safe either way).
- [x] **SHARE** — `Procedure SHAREINIT,NEAR` in `GSHARE2.ASM`; EXE file. DS=PSP at entry, CS=SHARE segment. Check DS:[SI]; `PUSH CS / POP DS` to access help string before `MOV DX, OFFSET SHARE_HELP_STR`.
- [x] **APPEND** — `main_begin:` in `APPEND.ASM`; EXE file (cseg segment). DS=PSP at entry, CS=cseg. Help string in cseg data area; `PUSH CS / POP DS` before printing.
- [x] **MORE** — `START:` in `MORE.ASM`; COM via EXE2BIN, single CODE segment, CS=DS=PSP throughout. Help string in data area after check code, before existing querylist data; scan PSP:81h, jump to `START1`.
- [x] **SYS** — `START:` in `SYS1.ASM`; COM via EXE2BIN, `ORG 80H` (PSP overlap trick). At entry CS=DS=PSP. Check DS:81h; `PUSH CS/POP DS` not needed since CS=DS. Help string placed after check code, before `BEGIN`.
- [x] **EXE2BIN** — `Main_Init` in `E2BINIT.ASM`; EXE, DS=PSP at entry (CS=CODE). Check DS:81h before `PUSH DS`; `PUSH CS/POP DS` to access help string in CODE segment.
- [x] **FASTOPEN** — `START:` in `FASTINIT.ASM`; EXE, DS=PSP at entry (CS=CSEG_INIT). Check DS:81h before `push cs/pop ds` setup. Help string placed before `START:` in CSEG_INIT data area; `PUSH CS/POP DS` to access.
- [x] **KEYB** — `START:` in `KEYB.ASM`; COM via EXE2BIN, single `CODE` segment, CS=DS=PSP throughout. Help string inline after /? check; jump to `KEYB_COMMAND` if no help.
- [x] **GRAPHICS** — `START:` in `GRAPHICS.ASM`; COM via EXE2BIN, single `CODE` segment, CS=DS=PSP throughout. Help string inline after /? check; jump to `GRAPHICS_INSTALL` if no help.
- [x] **MODE** — `ENTPT:` in `RESCODE.ASM` (ORG 100H); COM via EXE2BIN. At entry CS=DS=PSP. Check DS:81h, print help string in same segment, then `JMP MAIN`.
- [x] **PRINT** — `TRANSIENT:` in `PRINT_T.ASM`; CONVERT COM. CONVERT init does FAR JMP so CS=DG at entry (not PSP). Pattern: `INT 21h/62h` → ES=PSP, check `ES:[81h]` for `/?`; `CALL/POP` → DX=runtime addr of help string; `PUSH CS/POP DS` (CS=DG=string segment) for INT 21h/09h print.
- [ ] **CHKDSK** — pending (CONVERT COM; same pattern as PRINT should work; see note below).
- [ ] **RECOVER** — pending (same CONVERT COM pattern).
- [x] **EDLIN** — `EDLIN:` in `EDLIN.ASM`; CONVERT COM. Same pattern as PRINT: INT 21h/62h → ES=PSP, ES:[81h] check, CALL/POP + PUSH CS/POP DS for print.

#### CHKDSK / RECOVER /? — use CONVERT COM pattern from KEYNOTES.md

Entry points:
- CHKDSK: `CHKMAIN:` in `CHKDSK.ASM` (DG:0x45D8)
- RECOVER: entry label in `RECSEG.INC` (DG:0x136F)

## Known Issues

### USA-MS.MSG spurious git diff

After any `make` build, `v4.0/src/MESSAGES/USA-MS.MSG` always shows as modified in
the MS-DOS submodule even though file content (and SHA256) is identical to HEAD.

**Root cause (suspected):** `.gitattributes` sets `*.MSG text eol=crlf`, so git
internally normalizes the blob to LF but checks out CRLF to the working tree.
Something in the build pipeline (possibly `make clean` + re-checkout, or a tool
that touches the file) causes the index to diverge from HEAD's blob, producing a
spurious 1186-line diff that is purely a CRLF↔LF conversion with no real changes.

**Impact:** Cosmetic only — `git status` in the submodule always shows the file as
dirty. Does not affect builds or CI.

**To fix:** Investigate whether the build rewrites the file (check makefiles for
any rule targeting `USA-MS.MSG`). If not, the gitattribute may need adjustment
(e.g., `*.MSG -text` to store as-is without normalization).
