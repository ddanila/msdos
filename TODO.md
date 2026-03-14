# MS-DOS 4.0 Build — TODO

## CMD Utilities

All 38 CMD utilities have been built from source. ✅

## DEV Device Drivers

All 11 device drivers built from source. ✅
DEV/SMARTDRV/FLUSH13.EXE (auxiliary cache control utility) also built. ✅

## Core Modules

All core modules built from source: BIOS/IO.SYS, DOS/MSDOS.SYS, BOOT, INC, MAPPER, MESSAGES, SELECT, MEMM/EMM386.SYS. ✅

## Source Audit Notes

- `INC/STRING.C` — not a build target; referenced only as a comment in KSTRING.C; superseded code.
- `INC/KSTRING.C` — built on-demand for FC.EXE (not a standalone `inc` target); covered.
- `TOOLS/` — pre-built compiler toolchain (MASM, CL, LINK, etc.), not MS-DOS OS source.
- `DEV/SMARTDRV/SMARTDRV.SYS` — already built by `dev` target. ✅

## Floppy Image

- Currently boots with all built utilities: IO.SYS, MSDOS.SYS, COMMAND.COM, SYS.COM, FORMAT.COM, CHKDSK.COM, DEBUG.COM, MEM.EXE, FDISK.EXE, MORE.COM, SORT.EXE, LABEL.COM, FIND.EXE, TREE.COM, COMP.COM, ATTRIB.EXE, EDLIN.COM, FC.EXE, NLSFUNC.EXE, ASSIGN.COM, XCOPY.EXE, DISKCOMP.COM, DISKCOPY.COM, APPEND.EXE, RECOVER.COM, FASTOPEN.EXE, PRINT.COM, FILESYS.EXE, REPLACE.EXE, JOIN.EXE, SUBST.EXE, BACKUP.COM, RESTORE.COM, GRAFTABL.COM, KEYB.COM, SHARE.EXE, EXE2BIN.EXE, GRAPHICS.COM + GRAPHICS.PRO, IFSFUNC.EXE, MODE.COM.

## Testing

- Extend `make test-sys` / add more e2e tests.
- Add CI step for `make test-sys`.

## Add /? Usage Strings to CMD Tools

All tools should print usage when invoked with `/?`, like MS-DOS 6.22.
Changes go in a dedicated branch in the MS-DOS fork (`dos4-enhancements`)
to keep the original source clean. Each tool needs a `/? ` check at startup
that prints usage to stdout (or stderr) and exits with errorlevel 0.

Switches below are extracted directly from each tool's parser source —
including undocumented ones, all of which are actually parsed and handled.

---

### FORMAT (FORPARSE.INC — verified)
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

### MEM (MEM.C — verified)
```
MEM [/PROGRAM | /DEBUG]

  /PROGRAM   Display loaded programs and their memory use
  /DEBUG     Display loaded programs, internal drivers, and other info
```

### KEYB (PARSER.ASM — verified)
```
KEYB [xx[,[yyy][,[drive:][path]filename]]] [/ID:nnn]

  xx                       Two-letter keyboard code (e.g., US, UK, GR)
  yyy                      Code page for the character set (e.g., 437, 850)
  [drive:][path]filename   Keyboard definition file (default: KEYBOARD.SYS)
  /ID:nnn                  Keyboard hardware ID (for countries with multiple layouts)
```

### XCOPY (XCOPYPAR.ASM — verified)
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

### BACKUP (BACKUP.C — verified; 7 switches)
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

### RESTORE (RESTPARS.C — verified; 8 switches)
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

### REPLACE (REPLACE.C — verified)
```
REPLACE source [dest] [/A] [/P] [/R] [/S] [/U] [/W]

  /A    Add new files (cannot be used with /U or /S)
  /P    Prompt before replacing/adding each file
  /R    Replace read-only files
  /S    Search subdirectories (not with /A)
  /U    Replace only files older than source
  /W    Wait for keypress before starting
```

### ATTRIB (ATTRIBA.ASM / PARSE.H — verified)
```
ATTRIB [+R|-R] [+A|-A] [[drive:][path]filename] [/S]

  +R / -R   Set or clear Read-Only attribute
  +A / -A   Set or clear Archive attribute
  /S        Process files in subdirectories
```

### CHKDSK (CHKPARSE.INC — agent-verified)
```
CHKDSK [drive:][[path]filename] [/F] [/V]

  /F    Fix errors on disk
  /V    Display full path of every file on disk
```

### SORT (SORT.ASM — agent-verified)
```
SORT [/R] [/+n]

  /R    Sort in reverse order
  /+n   Sort starting at column n
```

### FIND (FIND.ASM — agent-verified)
```
FIND [/V] [/C] [/N] "string" [drive:][path]filename [...]

  /V    Display lines not containing string
  /C    Count matching lines only
  /N    Display line numbers
```

### TREE (TREEPAR.ASM — agent-verified)
```
TREE [drive:][path] [/F] [/A]

  /F    Display filenames in each directory
  /A    Use ASCII characters (not extended graphics) for tree lines
```

### APPEND (APPENDP.INC — agent-verified)
```
APPEND [[drive:]path[;...]] [/X[:ON|OFF]] [/PATH:ON|OFF] [/E]

  /X[:ON|OFF]      Extend search to EXEC and file search (DOS 5+: /X:ON/OFF)
  /PATH:ON|OFF     Search appended dirs for files with explicit paths
  /E               Store appended path list in PATH environment variable
```

### ASSIGN (ASSGPARM.INC — agent-verified)
```
ASSIGN [x[:]=y[:] [...]] [/STATUS]

  /STATUS   Display current drive assignments
```

### PRINT (PRINT_T.ASM — agent-verified)
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

### GRAFTABL (GRTABPAR.ASM — agent-verified)
```
GRAFTABL [nnn] [/STATUS]

  nnn       Code page number to load (e.g., 437, 850, 860, 863, 865)
  /STATUS   Display currently loaded code page
```

### SHARE (GSHARE2.ASM — agent-verified)
```
SHARE [/F:filespace] [/L:locks]

  /F:n    Space in bytes for file-sharing info (default 2048)
  /L:n    Number of simultaneous file locks (default 20)
```

### GRAPHICS (GRPARMS.ASM — agent-verified)
```
GRAPHICS [type] [[drive:][path]filename] [/R] [/B] [/LCD] [/PB[:STD|LCD]]

  type             Printer type (e.g., COLOR1, COLOR4, COLOR8, HPDEFAULT, ...)
  /R               Print image in reverse (black on white)
  /B               Print background color (COLOR4/COLOR8 only)
  /LCD             Use LCD aspect ratio
  /PB[:STD|LCD]    Select print box (STD or LCD)
```

### FASTOPEN (FASTINIT.ASM — agent-verified)
```
FASTOPEN drive:[=n] [...] [/X]

  drive:[=n]   Drive to cache, with optional entry count (10–999)
  /X           Create name cache in expanded memory
```

### NLSFUNC (NLSPARM.ASM — agent-verified)
```
NLSFUNC [[drive:][path]filename]

  filename   National Language Support definition file (default: COUNTRY.SYS)
```

### DISKCOMP (DCOMPPAR.ASM — agent-verified)
```
DISKCOMP [d1:] [d2:] [/1] [/8]

  /1    Compare only first side
  /8    Compare only 8 sectors per track
```

### DISKCOPY (DCOPYPAR.ASM — agent-verified)
```
DISKCOPY [d1:] [d2:] [/1] [/V]

  /1    Copy only first side
  /V    Verify after copy
```

### FC (FC.C — agent-verified)
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

### EDLIN (EDLPARSE.ASM — agent-verified)
```
EDLIN [drive:][path]filename [/B]

  /B    Ignore Ctrl-Z (EOF) characters — treat file as binary text
```

### JOIN (JOIN.C — agent-verified)
```
JOIN [drive1:] [drive2:]path
JOIN drive1: /D
JOIN (no args: display current joins)

  /D    Delete (remove) a JOIN
```

### SUBST (SUBST.C — agent-verified)
```
SUBST [drive1: [drive2:]path]
SUBST drive1: /D
SUBST (no args: display current substitutions)

  /D    Delete a substitution
```

### EXE2BIN (E2BPARSE.INC — agent-verified)
```
EXE2BIN [drive:][path]input[.EXE] [[drive:][path]output[.BIN]]
```

### LABEL (LABEL.ASM — agent-verified)
```
LABEL [drive:][label]
```

### COMP (COMPPAR.ASM — agent-verified)
```
COMP [data1] [data2]
```

### RECOVER (RECOVER.ASM — agent-verified)
```
RECOVER [drive:][path]filename
RECOVER drive:
```

### SYS (SYS1.ASM — agent-verified)
```
SYS [source] drive:
```

### MORE (MORE.CLA)
```
MORE
(reads stdin, displays one screenful at a time)
```

### COMMAND (INIT.ASM / CPARSE.ASM — agent-verified)
```
COMMAND [[drive:]path] [device] [/E:nnnnn] [/P] [/MSG] [/C string]

  /E:nnnnn   Set environment size in bytes
  /P         Make permanent (no EXIT)
  /MSG       Store error messages in memory (for floppy use)
  /C string  Run command string then return
```

### FDISK (PARSE.H / _PARSE.ASM — agent-verified)
```
FDISK [/PRI[:n]] [/EXT[:n]] [/LOG[:n]] [/Q]

  /PRI[:n]   Create primary DOS partition (size in MB or %)
  /EXT[:n]   Create extended DOS partition
  /LOG[:n]   Create logical drive in extended partition
  /Q         Quiet (no prompts); used with above switches
```

### MODE
MODE is complex with multiple sub-commands. Usage per sub-command:
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
DEBUG is an interactive debugger. Usage:
```
DEBUG [[drive:][path]filename [arglist]]
```
No command-line switches; all control is via interactive commands (A, D, E, G, N, P, Q, R, T, U, W, etc.).

### FILESYS / IFSFUNC
Internal TSR utilities — no user-facing `/? ` help planned.

---

### Implementation approach

1. Create branch `dos4-enhancements` in the MS-DOS fork submodule.
2. For each tool: add a `/? ` check at the very start of `main`/init.
   - For ASM tools: check PSP command tail for `/?`, print help via DOS int 21h
     function 09h (print $-terminated string), then `int 21h` AH=4Ch.
   - For C tools: `strcmp` argv[1] with `"/?"`; print via `printf`; `exit(0)`.
3. Keep help strings compact (≤24 lines) to fit a standard 25-line screen.
4. Build and test each tool after adding help.
5. Update `tests/golden.sha256` after all changes.
