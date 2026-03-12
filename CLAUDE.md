# MS-DOS 4.0 Build — Key Notes

## Workflow Rules
- Commit after every step that succeeds, push to remote (ddanila).

## Line Ending Rules

**CRLF required** (DOS tools parse as text, BUILDIDX computes byte offsets):
- MSG, SKL, LBR, LNK, INF, BAT, INI, IDX files

**LF only** (source code — CRLF corrupts MASM THEADR records in .OBJ output):
- ASM, C, H, INC files

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
| Module   | Status     | Output           |
|----------|-----------|-----------------|
| MESSAGES | ✅ done    | USA-MS.IDX       |
| MAPPER   | ✅ done    | MAPPER.LIB       |
| BOOT     | ✅ done    | INC/boot.inc     |
| INC      | pending   |                  |
| BIOS     | pending   | io.sys           |
| DOS      | pending   | msdos.sys        |
| CMD      | pending   | command.com      |
| DEV      | pending   |                  |
| SELECT   | pending   |                  |
| MEMM     | pending   |                  |

## kvikdos Modifications (in kvikdos/kvikdos.c)
- `current_dir[DRIVE_COUNT]` expanded from 1 to 64 bytes per drive.
- `ah=0x3b` (CHDIR) implemented.
- `ah=0x29` (Parse Filename for FCB) fully implemented.
- `cd <path>` support added to batch interpreter.
- Filenames starting with `.` allowed (needed for `.CL1` files).
- `--cwd=<drive>:\<path>\` flag added to set initial DOS current directory.
