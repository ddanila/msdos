# MS-DOS 4.0 Build — TODO

## E2E Tests — Per-Command, Per-Option Coverage

Goal: every command (external tool and COMMAND.COM built-in) and every
recognized option gets at least one integration test. Tests run the real
DOS binary under kvikdos or QEMU, check exit code and/or COM1/stdout output.

**Harness setup:**
- [ ] Add CI step for `make test-sys`.
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
Each tool needs a `/?` check at startup that prints usage and exits 0.

Switches are extracted directly from each tool's parser source,
including undocumented ones that are actually parsed and handled.

### FORMAT (FORPARSE.INC)
```
FORMAT drive: [/V[:label]] [/S] [/B] [/F:size]
             [/T:tracks /N:sectors] [/4] [/1] [/8]
             [/SELECT] [/BACKUP] [/AUTOTEST]

  /V[:label]   Volume label
  /S           Copy system files (make bootable)
  /B           Reserve space for system files (don't copy)
  /F:size      Disk size (160, 180, 320, 360, 720, 1200, 1440 [K/KB/M/MB])
  /T:n         Tracks per side
  /N:n         Sectors per track
  /4           Format 360K disk in 1.2MB drive
  /1           Single-sided format
  /8           8 sectors per track
  /SELECT      Shell integration (SELECT utility)
  /BACKUP      Shell integration (BACKUP utility)
  /AUTOTEST    Non-interactive format (no prompts)
```

### MEM (MEM.C)
```
MEM [/PROGRAM | /DEBUG]

  /PROGRAM   Display loaded programs and their memory use
  /DEBUG     Display loaded programs, internal drivers, and other info
```

### KEYB (PARSER.ASM)
```
KEYB [xx[,[yyy][,[drive:][path]filename]]] [/ID:nnn]

  xx                       Two-letter keyboard code (e.g., US, UK, GR)
  yyy                      Code page for the character set (e.g., 437, 850)
  [drive:][path]filename   Keyboard definition file (default: KEYBOARD.SYS)
  /ID:nnn                  Keyboard hardware ID (for countries with multiple layouts)
```

### XCOPY (XCOPYPAR.ASM)
```
XCOPY source [dest] [/A] [/D:date] [/E] [/M] [/P] [/S] [/V] [/W]

  /A        Copy only files with archive attribute set (don't clear it)
  /D:date   Copy files changed on or after date
  /E        Copy subdirectories even if empty (used with /S)
  /M        Like /A but clears archive attribute after copy
  /P        Prompt before creating each destination file
  /S        Copy subdirectories (except empty ones)
  /V        Verify each written file
  /W        Wait for keypress before starting
```

### BACKUP (BACKUP.C)
```
BACKUP source dest: [/S] [/M] [/A] [/F[:size]] [/D:date] [/T:time] [/L:[path]logfile]

  /S             Back up subdirectories
  /M             Back up only files modified since last backup
  /A             Add to existing backup set (don't reformat)
  /F[:size]      Format target disk if needed (size optional)
  /D:date        Back up files modified on or after date
  /T:time        Back up files modified at or after time
  /L:[path]file  Write backup log to file
```

### RESTORE (RESTPARS.C)
```
RESTORE source: dest [/S] [/P] [/M] [/N] [/B:date] [/A:date] [/E:time] [/L:time]

  /S        Restore subdirectories
  /P        Prompt before restoring over read-only or changed files
  /M        Restore only files modified since backup
  /N        Restore only files that no longer exist on destination
  /B:date   Restore only files last modified on or before date
  /A:date   Restore only files last modified on or after date
  /E:time   Restore only files last modified at or before time
  /L:time   Restore only files last modified at or after time
```

### REPLACE (REPLACE.C)
```
REPLACE source [dest] [/A] [/P] [/R] [/S] [/U] [/W]

  /A    Add new files (cannot be used with /U or /S)
  /P    Prompt before replacing/adding each file
  /R    Replace read-only files
  /S    Search subdirectories (not with /A)
  /U    Replace only files older than source
  /W    Wait for keypress before starting
```

### ATTRIB (ATTRIBA.ASM)
```
ATTRIB [+R|-R] [+A|-A] [[drive:][path]filename] [/S]

  +R / -R   Set or clear Read-Only attribute
  +A / -A   Set or clear Archive attribute
  /S        Process files in subdirectories
```

### CHKDSK (CHKPARSE.INC)
```
CHKDSK [drive:][[path]filename] [/F] [/V]

  /F    Fix errors on disk
  /V    Display full path of every file on disk
```

### SORT (SORT.ASM)
```
SORT [/R] [/+n]

  /R    Sort in reverse order
  /+n   Sort starting at column n
```

### FIND (FIND.ASM)
```
FIND [/V] [/C] [/N] "string" [drive:][path]filename [...]

  /V    Display lines not containing string
  /C    Count matching lines only
  /N    Display line numbers
```

### TREE (TREEPAR.ASM)
```
TREE [drive:][path] [/F] [/A]

  /F    Display filenames in each directory
  /A    Use ASCII characters (not extended graphics) for tree lines
```

### APPEND (APPENDP.INC)
```
APPEND [[drive:]path[;...]] [/X[:ON|OFF]] [/PATH:ON|OFF] [/E]

  /X[:ON|OFF]      Extend search to EXEC and file search
  /PATH:ON|OFF     Search appended dirs for files with explicit paths
  /E               Store appended path list in PATH environment variable
```

### ASSIGN (ASSGPARM.INC)
```
ASSIGN [x[:]=y[:] [...]] [/STATUS]

  /STATUS   Display current drive assignments
```

### PRINT (PRINT_T.ASM)
```
PRINT [/D:device] [/B:bufsiz] [/U:busytick] [/M:maxtick]
      [/S:timeslice] [/Q:queuelen] [/T] [/C] [/P]
      [[drive:][path]filename [...]]

  /D:device     Print device (default PRN)
  /B:n          Internal buffer size in bytes
  /U:n          Busy-wait tick count
  /M:n          Max ticks per time slice
  /S:n          Time-slice scheduler quantum
  /Q:n          Max files in print queue
  /T            Terminate all files (cancel queue)
  /C            Remove preceding file(s) from queue
  /P            Add preceding file(s) to queue
```

### GRAFTABL (GRTABPAR.ASM)
```
GRAFTABL [nnn] [/STATUS]

  nnn       Code page number to load (e.g., 437, 850, 860, 863, 865)
  /STATUS   Display currently loaded code page
```

### SHARE (GSHARE2.ASM)
```
SHARE [/F:filespace] [/L:locks]

  /F:n    Space in bytes for file-sharing info (default 2048)
  /L:n    Number of simultaneous file locks (default 20)
```

### GRAPHICS (GRPARMS.ASM)
```
GRAPHICS [type] [[drive:][path]filename] [/R] [/B] [/LCD] [/PB[:STD|LCD]]

  type             Printer type (e.g., COLOR1, COLOR4, COLOR8, HPDEFAULT, ...)
  /R               Print image in reverse (black on white)
  /B               Print background color (COLOR4/COLOR8 only)
  /LCD             Use LCD aspect ratio
  /PB[:STD|LCD]    Select print box (STD or LCD)
```

### FASTOPEN (FASTINIT.ASM)
```
FASTOPEN drive:[=n] [...] [/X]

  drive:[=n]   Drive to cache, with optional entry count (10–999)
  /X           Create name cache in expanded memory
```

### NLSFUNC (NLSPARM.ASM)
```
NLSFUNC [[drive:][path]filename]

  filename   National Language Support definition file (default: COUNTRY.SYS)
```

### DISKCOMP (DCOMPPAR.ASM)
```
DISKCOMP [d1:] [d2:] [/1] [/8]

  /1    Compare only first side
  /8    Compare only 8 sectors per track
```

### DISKCOPY (DCOPYPAR.ASM)
```
DISKCOPY [d1:] [d2:] [/1] [/V]

  /1    Copy only first side
  /V    Verify after copy
```

### FC (FC.C)
```
FC [/A] [/B] [/C] [/L] [/LBn] [/N] [/T] [/W] [/nnnn] file1 file2

  /A     Display only first and last lines of differing sections (ASCII)
  /B     Binary comparison
  /C     Case-insensitive comparison
  /L     Compare as ASCII text (default)
  /LBn   Set line buffer to n lines
  /N     Display line numbers (ASCII mode)
  /T     Don't expand tabs to spaces
  /W     Compress whitespace for comparison
  /nnnn  Number of consecutive matching lines to resync
```

### EDLIN (EDLPARSE.ASM)
```
EDLIN [drive:][path]filename [/B]

  /B    Ignore Ctrl-Z (EOF) characters — treat file as binary text
```

### JOIN (JOIN.C)
```
JOIN [drive1:] [drive2:]path
JOIN drive1: /D
JOIN (no args: display current joins)

  /D    Delete (remove) a JOIN
```

### SUBST (SUBST.C)
```
SUBST [drive1: [drive2:]path]
SUBST drive1: /D
SUBST (no args: display current substitutions)

  /D    Delete a substitution
```

### EXE2BIN (E2BPARSE.INC)
```
EXE2BIN [drive:][path]input[.EXE] [[drive:][path]output[.BIN]]
```

### LABEL (LABEL.ASM)
```
LABEL [drive:][label]
```

### COMP (COMPPAR.ASM)
```
COMP [data1] [data2]
```

### RECOVER (RECOVER.ASM)
```
RECOVER [drive:][path]filename
RECOVER drive:
```

### SYS (SYS1.ASM)
```
SYS [source] drive:
```

### MORE (MORE.CLA)
```
MORE
(reads stdin, displays one screenful at a time)
```

### COMMAND (INIT.ASM / CPARSE.ASM)
```
COMMAND [[drive:]path] [device] [/E:nnnnn] [/P] [/MSG] [/C string]

  /E:nnnnn   Set environment size in bytes
  /P         Make permanent (no EXIT)
  /MSG       Store error messages in memory (for floppy use)
  /C string  Run command string then return
```

### FDISK (PARSE.H / _PARSE.ASM)
```
FDISK [/PRI[:n]] [/EXT[:n]] [/LOG[:n]] [/Q]

  /PRI[:n]   Create primary DOS partition (size in MB or %)
  /EXT[:n]   Create extended DOS partition
  /LOG[:n]   Create logical drive in extended partition
  /Q         Quiet (no prompts); used with above switches
```

### MODE
```
MODE COMn[:] [baud[,parity[,databits[,stopbits[,P]]]]]
MODE LPTn[:] [cols[,lines[,retry]]]
MODE CON[:] [COLS=c] [LINES=n]
MODE CON[:] [RATE=r DELAY=d]
MODE device [/STATUS]
MODE display[,shift[,T]]
MODE drive: CODEPAGE PREPARE=((cp[,...]) [path]filename)
MODE drive: CODEPAGE SELECT=cp
MODE drive: CODEPAGE REFRESH
MODE drive: CODEPAGE [/STATUS]
```

### DEBUG
```
DEBUG [[drive:][path]filename [arglist]]
```
Interactive debugger — no command-line switches; all control via
interactive commands (A, D, E, G, N, P, Q, R, T, U, W, etc.).

### FILESYS / IFSFUNC
Internal TSR utilities — no user-facing `/?` help planned.

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
- [ ] **CHKDSK** — **SKIPPED** (see note below).

#### CHKDSK /? implementation — blocked by convert tool format

CHKDSK uses a custom `CONVERT.EXE` tool (not standard EXE2BIN) that produces a non-standard COM file:
the output is `[3-byte JMP] + "Converted" label + [embedded MZ EXE]`. The JMP jumps to the entry
within the embedded EXE (offset 0x45D8 in CS space). Labels in CHKDSK1.ASM (CODE segment in DG group)
have DG-relative offsets. At runtime CS=DS=PSP segment. DG base is at paragraph 0x0007 = image offset 0x70.

Addressing works correctly for jumps (near JMP displacement is relative, cancels the DG offset difference).
But `lea dx, string_label` gives the DG-relative offset which, when used with DS=PSP, resolves to a
DIFFERENT memory location than the string actually occupies at runtime (off by the DG base + COM embed
offset). The `call/pop` position-independent trick also fails for the same reason — the pushed IP is
correct (actual runtime IP), but DS doesn't align with it.

**To implement CHKDSK /?**: The help string would need to be accessed via `CS:` override (not DS),
OR find the exact runtime offset formula for this embed format. Alternatively, check if CHKDSK
can be patched to embed a plain `ORG 100h` COM structure instead.

### Implementation approach

1. For each tool: add a `/?` check at the very start of `main`/init.
   - ASM tools: check PSP command tail for `/?`, print help via DOS int 21h
     function 09h (print $-terminated string), then `int 21h` AH=4Ch.
   - C tools: `strcmp` argv[1] with `"/?"`; print via `printf`; `exit(0)`.
2. Keep help strings compact (≤24 lines) to fit a standard 25-line screen.
3. Build and test each tool after adding help.
4. Update `tests/golden.sha256` after all changes.
