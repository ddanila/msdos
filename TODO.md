# MS-DOS 4.0 Build — TODO

## What's Next (prioritized)

1. ~~**COMMAND /?**~~ — done. Added to `INIT.ASM` before `sysloadmsg`; works under kvikdos too.
2. ~~**E2E functional tests for read-only external tools**~~ — done (partial). MEM, FIND, FC, TREE wired into `run_tests.sh` Section 6. kvikdos extended with INT 21h/33h/AL=03h (boot drive) and INT 21h/69h (disk serial number) stubs. **Remaining:** SORT (insufficient memory — C runtime can't shrink allocation under kvikdos), COMP (uses INT 21h/11h FCB search — not implemented in kvikdos).
3. ~~**E2E functional tests for COMMAND.COM built-ins via QEMU**~~ — done. VER, ECHO, SET, PATH, DIR, VOL tested via `make test-builtins` (single QEMU boot, CTTY AUX + COM1 capture). **Known issue:** `SET FOO=BAR` (environment write) hangs batch processing on floppy boot — likely environment resize issue with minimal env space. Read-only SET (no args) works fine.
4. **CI job: pin submodule to `main` and verify golden checksums** — the one remaining `[ ]` in harness setup. Guards against regressions where toolchain changes break unmodified upstream source.
5. ~~**CHKDSK /?**~~ — done. Added using CONVERT COM pattern (CALL/POP trick), same as DEBUG/PRINT.
6. ~~**Verify EXEPACK fix on real DOS/QEMU**~~ — done. FIND, FDISK, IFSFUNC, EXE2BIN verified via `make test-exepack` (QEMU boot, /? invocation, no "Packed file is corrupt"). SELECT.EXE not on floppy (tested implicitly via make test-sys).

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
- [x] `CHKDSK /?` — usage

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
- [x] `FDISK /?` — usage

#### DEBUG
- [ ] `DEBUG` — launch and quit (`Q` command)
- [ ] `DEBUG file` — load file
- [x] `DEBUG /?` — usage

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
- [x] `IFSFUNC /?` — usage

#### FILESYS
- [ ] `FILESYS` — load (smoke test, internal tool)
- [x] `FILESYS /?` — usage

## Add /? Usage Strings to CMD Tools

All tools should print usage when invoked with `/?`, like MS-DOS 6.22.
Changes go in the `dos4-enhancements` branch of the MS-DOS fork.
- ASM tools: check PSP:81h for `/?`, print $-terminated string via INT 21h/09h, exit via INT 21h/4Ch.
- C tools: `strcmp` argv[1] with `"/?"`; print via `printf`; `exit(0)`.
- Keep help strings compact (≤24 lines) to fit a standard 25-line screen.

### Pending usage strings

All external CMD tools now have /? help implemented.

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
