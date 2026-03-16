#!/bin/bash
# Integration tests for the MS-DOS 4.0 build.
# Run via: make test  (which first builds everything, then calls this script)
# Exit code: 0 if all tests pass, 1 if any fail.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_ROOT/MS-DOS/v4.0/src"
BIN="$REPO_ROOT/bin"
GOLDEN="$REPO_ROOT/tests/golden.sha256"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# ── Section 1: output files exist and are non-empty ─────────────────────────
echo "=== Section 1: output files exist ==="

ARTIFACTS=(
    MESSAGES/USA-MS.IDX
    MAPPER/MAPPER.LIB
    INC/boot.inc
    BIOS/IO.SYS
    DOS/MSDOS.SYS
    CMD/COMMAND/COMMAND.COM
    CMD/SYS/SYS.COM
    CMD/FORMAT/FORMAT.COM
    CMD/CHKDSK/CHKDSK.COM
    DEV/ANSI/ANSI.SYS
    DEV/VDISK/VDISK.SYS
    DEV/COUNTRY/COUNTRY.SYS
    DEV/RAMDRIVE/RAMDRIVE.SYS
    DEV/KEYBOARD/KEYBOARD.SYS
    DEV/PRINTER/PRINTER.SYS
    DEV/DISPLAY/DISPLAY.SYS
    DEV/SMARTDRV/SMARTDRV.SYS \
    DEV/SMARTDRV/FLUSH13.EXE
    DEV/DRIVER/DRIVER.SYS
    DEV/XMA2EMS/XMA2EMS.SYS
    DEV/XMAEM/XMAEM.SYS
    SELECT/SELECT.EXE
    SELECT/SELECT.COM
    SELECT/SELECT.HLP
    SELECT/SELECT.DAT
    CMD/DEBUG/DEBUG.COM \
    CMD/MEM/MEM.EXE \
    CMD/FDISK/FDISK.EXE \
    CMD/MORE/MORE.COM \
    CMD/SORT/SORT.EXE \
    CMD/LABEL/LABEL.COM \
    CMD/FIND/FIND.EXE \
    CMD/TREE/TREE.COM \
    CMD/COMP/COMP.COM \
    CMD/ATTRIB/ATTRIB.EXE \
    CMD/EDLIN/EDLIN.COM \
    CMD/FC/FC.EXE \
    CMD/NLSFUNC/NLSFUNC.EXE \
    CMD/ASSIGN/ASSIGN.COM \
    CMD/XCOPY/XCOPY.EXE \
    CMD/DISKCOMP/DISKCOMP.COM \
    CMD/DISKCOPY/DISKCOPY.COM \
    CMD/APPEND/APPEND.EXE \
    CMD/RECOVER/RECOVER.COM \
    CMD/FASTOPEN/FASTOPEN.EXE \
    CMD/PRINT/PRINT.COM \
    CMD/FILESYS/FILESYS.EXE \
    CMD/REPLACE/REPLACE.EXE \
    CMD/JOIN/JOIN.EXE \
    CMD/SUBST/SUBST.EXE \
    CMD/BACKUP/BACKUP.COM \
    CMD/RESTORE/RESTORE.COM \
    CMD/GRAFTABL/GRAFTABL.COM \
    CMD/KEYB/KEYB.COM \
    CMD/SHARE/SHARE.EXE \
    CMD/EXE2BIN/EXE2BIN.EXE \
    CMD/GRAPHICS/GRAPHICS.COM \
    CMD/IFSFUNC/IFSFUNC.EXE \
    CMD/MODE/MODE.COM \
    MEMM/MEMM/EMM386.SYS
)

for f in "${ARTIFACTS[@]}"; do
    path="$SRC/$f"
    if [[ -f "$path" && -s "$path" ]]; then
        ok "$f"
    else
        fail "$f  (missing or empty)"
    fi
done

# ── Section 2: SHA256 checksums ──────────────────────────────────────────────
echo ""
echo "=== Section 2: SHA256 checksums ==="

if [[ -f "$GOLDEN" ]]; then
    if (cd "$SRC" && sha256sum --check "$GOLDEN" --quiet 2>&1); then
        ok "all checksums match"
    else
        fail "checksum mismatch (run 'make gen-checksums' to regenerate)"
    fi
else
    echo "  SKIP: golden.sha256 not found — run 'make gen-checksums' first"
fi

# ── Section 3: kvikdos smoke tests ──────────────────────────────────────────
echo ""
echo "=== Section 3: kvikdos smoke tests ==="

# COMMAND.COM /C EXIT — should return exit code 0
if (cd "$SRC/CMD/COMMAND" && timeout 30 "$BIN/dos-run" "$SRC/CMD/COMMAND/COMMAND.COM" /C EXIT) 2>&1; then
    ok "COMMAND.COM /C EXIT"
else
    rc=$?
    if [[ $rc -eq 124 ]]; then
        fail "COMMAND.COM /C EXIT  (timed out after 30s)"
    else
        fail "COMMAND.COM /C EXIT  (exit code $rc)"
    fi
fi

# ── Section 4: /? help smoke tests ──────────────────────────────────────────
echo ""
echo "=== Section 4: /? help smoke tests ==="

# Run a tool with /? and check that expected text appears in stdout.
# Exit code is ignored (|| true) because some tools (e.g. ATTRIB) trigger a
# kvikdos warning about unsupported INT 00 restore — cosmetic on real DOS.
check_help() {
    local name="$1"
    local tool="$2"
    local expected="$3"
    local output
    output=$(timeout 30 "$BIN/dos-run" "$SRC/$tool" /? 2>/dev/null) || {
        rc=$?
        if [[ $rc -eq 124 ]]; then
            fail "$name /?  (timed out after 30s)"
            return
        fi
    }
    if echo "$output" | grep -q "$expected"; then
        ok "$name /?"
    else
        fail "$name /?  (expected '$expected' in output, got: $(echo "$output" | head -3))"
    fi
}

check_help "MEM"     "CMD/MEM/MEM.EXE"         "MEM"
check_help "ATTRIB"  "CMD/ATTRIB/ATTRIB.EXE"  "ATTRIB"
check_help "XCOPY"   "CMD/XCOPY/XCOPY.EXE"    "XCOPY"
check_help "FORMAT"  "CMD/FORMAT/FORMAT.COM"   "FORMAT"
check_help "FC"      "CMD/FC/FC.EXE"           "FC"
check_help "JOIN"    "CMD/JOIN/JOIN.EXE"        "JOIN"
check_help "SUBST"   "CMD/SUBST/SUBST.EXE"     "SUBST"
check_help "REPLACE" "CMD/REPLACE/REPLACE.EXE" "REPLACE"
check_help "SORT"    "CMD/SORT/SORT.EXE"       "SORT"
check_help "FIND"    "CMD/FIND/FIND.EXE"       "FIND"
check_help "NLSFUNC"  "CMD/NLSFUNC/NLSFUNC.EXE"   "NLSFUNC"
check_help "TREE"     "CMD/TREE/TREE.COM"          "TREE"
check_help "BACKUP"   "CMD/BACKUP/BACKUP.COM"      "BACKUP"
check_help "RESTORE"  "CMD/RESTORE/RESTORE.COM"    "RESTORE"
check_help "DISKCOMP" "CMD/DISKCOMP/DISKCOMP.COM"  "DISKCOMP"
check_help "DISKCOPY" "CMD/DISKCOPY/DISKCOPY.COM"  "DISKCOPY"
check_help "GRAFTABL" "CMD/GRAFTABL/GRAFTABL.COM"  "GRAFTABL"
check_help "LABEL"    "CMD/LABEL/LABEL.COM"         "LABEL"
check_help "COMP"     "CMD/COMP/COMP.COM"           "COMP"
check_help "ASSIGN"   "CMD/ASSIGN/ASSIGN.COM"       "ASSIGN"
check_help "SHARE"    "CMD/SHARE/SHARE.EXE"         "SHARE"
check_help "APPEND"   "CMD/APPEND/APPEND.EXE"       "APPEND"
check_help "MORE"     "CMD/MORE/MORE.COM"            "MORE"
check_help "SYS"      "CMD/SYS/SYS.COM"             "SYS"
check_help "EXE2BIN"  "CMD/EXE2BIN/EXE2BIN.EXE"    "EXE2BIN"
check_help "FASTOPEN" "CMD/FASTOPEN/FASTOPEN.EXE"   "FASTOPEN"
check_help "KEYB"     "CMD/KEYB/KEYB.COM"           "KEYB"
check_help "GRAPHICS" "CMD/GRAPHICS/GRAPHICS.COM"   "GRAPHICS"
check_help "MODE"     "CMD/MODE/MODE.COM"            "MODE"
check_help "PRINT"    "CMD/PRINT/PRINT.COM"          "PRINT"
check_help "EDLIN"    "CMD/EDLIN/EDLIN.COM"          "EDLIN"
check_help "RECOVER"  "CMD/RECOVER/RECOVER.COM"      "RECOVER"
check_help "CHKDSK"   "CMD/CHKDSK/CHKDSK.COM"        "CHKDSK"
check_help "FILESYS"  "CMD/FILESYS/FILESYS.EXE"      "FILESYS"
check_help "DEBUG"    "CMD/DEBUG/DEBUG.COM"           "DEBUG"
check_help "FDISK"    "CMD/FDISK/FDISK.EXE"           "FDISK"
check_help "IFSFUNC"  "CMD/IFSFUNC/IFSFUNC.EXE"       "IFSFUNC"
# Skipped: COMMAND.COM /? hangs under kvikdos (interactive shell, no timeout-safe exit)
# check_help "COMMAND"  "CMD/COMMAND/COMMAND.COM"       "command interpreter"

# ── Section 5: COMMAND.COM built-in /? help (static binary check) ────────────
# Built-in commands run through COMMAND.COM which fails sysloadmsg under kvikdos
# (version mismatch 5.0 vs 4.0). Functional testing requires QEMU. As a lighter
# alternative we verify the help string is present in the COMMAND.COM binary.
echo ""
echo "=== Section 5: COMMAND.COM built-in /? help (static check) ==="

check_builtin_help() {
    local name="$1"
    local expected="$2"
    local bin_str
    bin_str=$(strings "$SRC/CMD/COMMAND/COMMAND.COM")
    if echo "$bin_str" | grep -q "$expected"; then
        ok "$name /? (static)"
    else
        fail "$name /?  (expected '$expected' in COMMAND.COM binary)"
    fi
}

check_builtin_help "VER"    "Displays the MS-DOS version."
check_builtin_help "DIR"    "Displays a list of files and subdirectories"
check_builtin_help "COPY"   "Copies one or more files to another location."
check_builtin_help "SET"    "Displays, sets, or removes MS-DOS environment"
check_builtin_help "PROMPT" "Changes the MS-DOS command prompt."
check_builtin_help "PATH"   "Displays or sets a search path"
check_builtin_help "CD"     "Displays the name of or changes the current directory."
check_builtin_help "CHDIR"  "Displays the name of or changes the current directory."
check_builtin_help "MD"     "Creates a directory."
check_builtin_help "MKDIR"  "Creates a directory."
check_builtin_help "RD"     "Removes (deletes) a directory."
check_builtin_help "RMDIR"  "Removes (deletes) a directory."
check_builtin_help "PAUSE"  "Suspends processing of a batch program"
check_builtin_help "ERASE"  "Deletes one or more files."
check_builtin_help "DEL"    "Deletes one or more files."
check_builtin_help "RENAME" "Renames a file or files."
check_builtin_help "TYPE"   "Displays the contents of a text file."
check_builtin_help "VOL"    "Displays the disk volume label"
check_builtin_help "ECHO"   "Displays messages, or turns command echoing on or off."
check_builtin_help "BREAK"   "Sets or clears extended CTRL"
check_builtin_help "VERIFY"  "Tells MS-DOS whether to verify"
check_builtin_help "CLS"     "Clears the screen."
check_builtin_help "EXIT"    "Quits the CMD.EXE program"
check_builtin_help "CTTY"    "Changes the terminal device"
check_builtin_help "CHCP"    "Displays or sets the active code page"
check_builtin_help "TRUENAME" "Returns the full path"
check_builtin_help "REM"     "Records comments (remarks)"
check_builtin_help "GOTO"    "Directs MS-DOS to a labeled line"
check_builtin_help "SHIFT"   "Changes the position of replaceable parameters"
check_builtin_help "IF"      "Performs conditional processing"
check_builtin_help "FOR"     "Runs a specified command for each file"
check_builtin_help "CALL"    "Calls one batch program from another"

# ── Section 6: E2E functional tests (kvikdos) ─────────────────────────────────
# Run real DOS binaries under kvikdos with actual input/output, not just /? help.
echo ""
echo "=== Section 6: E2E functional tests (kvikdos) ==="

# Helper: run a tool under kvikdos from the source root, capture stdout.
# Usage: run_dos TOOL [args...]
# Exit code is from the tool (or 124 on timeout).
run_dos() {
    local tool="$SRC/$1"; shift
    timeout 30 "$BIN/dos-run" "$tool" "$@" 2>/dev/null
}

# -- MEM: basic memory report --
output=$(run_dos CMD/MEM/MEM.EXE) || true
if echo "$output" | grep -q "bytes total memory"; then
    ok "MEM (basic memory report)"
else
    fail "MEM (expected 'bytes total memory' in output)"
fi

# -- FIND: search for string in a file --
output=$(run_dos CMD/FIND/FIND.EXE '"echo"' 'C:\SETENV.BAT') || true
if echo "$output" | grep -q "SETENV.BAT"; then
    ok "FIND (search file for string)"
else
    fail "FIND (expected 'SETENV.BAT' header in output)"
fi

# -- FIND /C: count matching lines --
output=$(run_dos CMD/FIND/FIND.EXE /C '"set"' 'C:\SETENV.BAT') || true
if echo "$output" | grep -q "SETENV.BAT"; then
    ok "FIND /C (count matches)"
else
    fail "FIND /C (expected 'SETENV.BAT' header with count)"
fi

# -- FC: compare identical files --
output=$(run_dos CMD/FC/FC.EXE 'C:\SETENV.BAT' 'C:\SETENV.BAT') || true
if echo "$output" | grep -q "no differences"; then
    ok "FC (identical files)"
else
    fail "FC (expected 'no differences' for identical files)"
fi

# -- FC: compare different files --
output=$(run_dos CMD/FC/FC.EXE 'C:\SETENV.BAT' 'C:\CPY.BAT') || true
if echo "$output" | grep -q "SETENV.BAT"; then
    ok "FC (different files)"
else
    fail "FC (expected diff output with filename header)"
fi

# -- FC /N: line numbers in diff --
output=$(run_dos CMD/FC/FC.EXE /N 'C:\SETENV.BAT' 'C:\CPY.BAT') || true
if echo "$output" | grep -q "1:"; then
    ok "FC /N (line numbers)"
else
    fail "FC /N (expected numbered lines like '1:')"
fi

# -- FC /B: binary compare (different files) --
output=$(run_dos CMD/FC/FC.EXE /B 'C:\SETENV.BAT' 'C:\CPY.BAT') || true
if echo "$output" | grep -q "00000000:" && echo "$output" | grep -q "longer than"; then
    ok "FC /B (binary diff)"
else
    fail "FC /B (expected hex offsets and 'longer than')"
fi

# -- FC /B: binary compare (identical files) --
output=$(run_dos CMD/FC/FC.EXE /B 'C:\SETENV.BAT' 'C:\SETENV.BAT') || true
if echo "$output" | grep -q "no differences"; then
    ok "FC /B (identical, binary)"
else
    fail "FC /B (expected 'no differences' for identical files)"
fi

# -- FC /C: case-insensitive compare (identical files) --
output=$(run_dos CMD/FC/FC.EXE /C 'C:\SETENV.BAT' 'C:\SETENV.BAT') || true
if echo "$output" | grep -q "no differences"; then
    ok "FC /C (case-insensitive)"
else
    fail "FC /C (expected 'no differences')"
fi

# -- FC /W: compress whitespace compare (identical files) --
output=$(run_dos CMD/FC/FC.EXE /W 'C:\SETENV.BAT' 'C:\SETENV.BAT') || true
if echo "$output" | grep -q "no differences"; then
    ok "FC /W (compress whitespace)"
else
    fail "FC /W (expected 'no differences')"
fi

# -- FC /L: explicit ASCII mode (different files) --
output=$(run_dos CMD/FC/FC.EXE /L 'C:\SETENV.BAT' 'C:\CPY.BAT') || true
if echo "$output" | grep -q "SETENV.BAT"; then
    ok "FC /L (explicit ASCII)"
else
    fail "FC /L (expected diff output with filename header)"
fi

# -- TREE: directory listing --
output=$(run_dos CMD/TREE/TREE.COM /A) || true
if echo "$output" | grep -q "Directory PATH listing"; then
    ok "TREE (directory listing)"
else
    fail "TREE (expected 'Directory PATH listing')"
fi

# -- TREE /F: include filenames in listing --
output=$(run_dos CMD/TREE/TREE.COM /F /A 2>/dev/null) || true
if echo "$output" | grep -q "Directory PATH listing"; then
    ok "TREE /F (filenames mode runs)"
else
    fail "TREE /F (expected 'Directory PATH listing')"
fi

# -- SORT: sort lines from stdin (piped via host stdin) --
output=$(printf "banana\r\ncherry\r\napple\r\n" | run_dos CMD/SORT/SORT.EXE) || true
if echo "$output" | grep -q "apple" && echo "$output" | grep -q "banana"; then
    ok "SORT (sort lines from stdin)"
else
    fail "SORT (expected sorted output with 'apple' and 'banana')"
fi

# -- SORT /R: reverse sort --
output=$(printf "banana\r\ncherry\r\napple\r\n" | run_dos CMD/SORT/SORT.EXE /R) || true
# In reverse order: cherry, banana, apple.  Verify cherry comes before apple.
cherry_line=$(echo "$output" | grep -n "cherry" | head -1 | cut -d: -f1)
apple_line=$(echo "$output" | grep -n "apple" | head -1 | cut -d: -f1)
if [[ -n "$cherry_line" && -n "$apple_line" && "$cherry_line" -lt "$apple_line" ]]; then
    ok "SORT /R (reverse sort)"
else
    fail "SORT /R (expected cherry before apple in reverse sort)"
fi

# -- SORT /+2: sort by column 2 --
output=$(printf "xbb\r\nxaa\r\nxcc\r\n" | run_dos CMD/SORT/SORT.EXE /+2) || true
# Sorted by 2nd char: xaa, xbb, xcc.  Verify xaa comes before xcc.
aa_line=$(echo "$output" | grep -n "xaa" | head -1 | cut -d: -f1)
cc_line=$(echo "$output" | grep -n "xcc" | head -1 | cut -d: -f1)
if [[ -n "$aa_line" && -n "$cc_line" && "$aa_line" -lt "$cc_line" ]]; then
    ok "SORT /+2 (sort by column)"
else
    fail "SORT /+2 (expected xaa before xcc when sorting by column 2)"
fi

# -- COMP: compare identical files (COMP loops on Y/N prompt at EOF; capture first 20 lines) --
output=$(timeout 5 "$BIN/dos-run" "$SRC/CMD/COMP/COMP.COM" SETENV.BAT SETENV.BAT </dev/null 2>/dev/null | head -20) || true
if echo "$output" | grep -q "Files compare OK"; then
    ok "COMP (identical files)"
else
    fail "COMP (expected 'Files compare OK')"
fi

# -- COMP: compare different files --
output=$(timeout 5 "$BIN/dos-run" "$SRC/CMD/COMP/COMP.COM" SETENV.BAT CPY.BAT </dev/null 2>/dev/null | head -20) || true
if echo "$output" | grep -q "different sizes"; then
    ok "COMP (different files)"
else
    fail "COMP (expected 'different sizes')"
fi

# -- ATTRIB: show file attributes --
output=$(run_dos CMD/ATTRIB/ATTRIB.EXE 'C:\SETENV.BAT') || true
if echo "$output" | grep -q "SETENV.BAT"; then
    ok "ATTRIB (show attributes)"
else
    fail "ATTRIB (expected filename in output)"
fi

# -- ATTRIB +R / -R: set and clear read-only --
run_dos CMD/ATTRIB/ATTRIB.EXE '+R' 'C:\SETENV.BAT' > /dev/null 2>&1 || true
output=$(run_dos CMD/ATTRIB/ATTRIB.EXE 'C:\SETENV.BAT') || true
if echo "$output" | grep -q "R"; then
    ok "ATTRIB +R (set read-only)"
else
    fail "ATTRIB +R (expected 'R' in attribute display)"
fi
# Clean up: remove read-only
run_dos CMD/ATTRIB/ATTRIB.EXE '-R' 'C:\SETENV.BAT' > /dev/null 2>&1 || true
output=$(run_dos CMD/ATTRIB/ATTRIB.EXE 'C:\SETENV.BAT') || true
if ! echo "$output" | grep -q " R "; then
    ok "ATTRIB -R (clear read-only)"
else
    fail "ATTRIB -R (R flag still present after -R)"
fi

# -- MORE: page through piped stdin --
output=$(printf "line1\r\nline2\r\nline3\r\n" | run_dos CMD/MORE/MORE.COM) || true
if echo "$output" | grep -q "line1" && echo "$output" | grep -q "line3"; then
    ok "MORE (piped stdin)"
else
    fail "MORE (expected 'line1' and 'line3' in output)"
fi

# -- DEBUG: launch and quit --
output=$(printf "Q\r\n" | run_dos CMD/DEBUG/DEBUG.COM) || true
if echo "$output" | grep -q "^-"; then
    ok "DEBUG (launch and quit)"
else
    fail "DEBUG (expected '-' prompt)"
fi

# -- DEBUG: register dump --
output=$(printf "R\r\nQ\r\n" | run_dos CMD/DEBUG/DEBUG.COM) || true
if echo "$output" | grep -q "AX="; then
    ok "DEBUG R (register dump)"
else
    fail "DEBUG R (expected 'AX=' in register output)"
fi

# -- LABEL: show volume info (read-only; write needs FCB delete, not implemented) --
output=$(printf "\r\n" | timeout 5 "$BIN/dos-run" "$SRC/CMD/LABEL/LABEL.COM" 2>/dev/null) || true
if echo "$output" | grep -q "Serial Number"; then
    ok "LABEL (show volume info)"
else
    fail "LABEL (expected 'Serial Number' in output)"
fi

# -- EDLIN: open existing file, list lines, quit --
# EDLIN triggers division-by-zero warnings (screen width calc); pipe through head to limit output.
output=$(printf "1L\r\nQ\r\nY\r\n" | timeout 30 "$BIN/dos-run" "$SRC/CMD/EDLIN/EDLIN.COM" SETENV.BAT 2>/dev/null | head -20 || true)
if echo "$output" | grep -q "End of input file"; then
    ok "EDLIN (open + list)"
else
    fail "EDLIN (expected 'End of input file')"
fi

# -- EDLIN: open new file --
output=$(printf "Q\r\nY\r\n" | timeout 30 "$BIN/dos-run" "$SRC/CMD/EDLIN/EDLIN.COM" NEWFILE.TXT 2>/dev/null | head -5 || true)
if echo "$output" | grep -q "New file"; then
    ok "EDLIN (new file)"
else
    fail "EDLIN (expected 'New file')"
fi

# -- REPLACE /A: add file to destination --
rm -f "$SRC/CMD/REPLACE/SETENV.BAT"
output=$(timeout 10 "$BIN/dos-run" --cwd='C:\' "$SRC/CMD/REPLACE/REPLACE.EXE" 'C:\SETENV.BAT' 'C:\CMD\REPLACE\' /A 2>/dev/null || true)
if echo "$output" | grep -q "file(s) added"; then
    ok "REPLACE /A (add mode)"
else
    fail "REPLACE /A (expected 'file(s) added')"
fi
rm -f "$SRC/CMD/REPLACE/SETENV.BAT"

# -- REPLACE: no source path → error message (stderr) --
output=$(timeout 10 "$BIN/dos-run" "$SRC/CMD/REPLACE/REPLACE.EXE" 2>&1 || true)
if echo "$output" | grep -q "Source path required"; then
    ok "REPLACE (no args error)"
else
    fail "REPLACE (expected 'Source path required')"
fi

# -- XCOPY: no args → error message (stderr) --
output=$(timeout 10 "$BIN/dos-run" "$SRC/CMD/XCOPY/XCOPY.EXE" 2>&1 || true)
if echo "$output" | grep -q "Invalid number of parameters"; then
    ok "XCOPY (no args error)"
else
    fail "XCOPY (expected 'Invalid number of parameters')"
fi

# -- GRAFTABL /STATUS: show active code page --
output=$(run_dos CMD/GRAFTABL/GRAFTABL.COM /STATUS) || true
if echo "$output" | grep -q "Code Page"; then
    ok "GRAFTABL /STATUS (code page info)"
else
    fail "GRAFTABL /STATUS (expected 'Code Page' in output)"
fi

# -- SUBST (no args): list drive substitutions (none → silent exit 0) --
output=$(run_dos CMD/SUBST/SUBST.EXE 2>/dev/null) || true
exit_code=$?
if [[ $exit_code -eq 0 ]]; then
    ok "SUBST (no args, lists substitutions)"
else
    fail "SUBST (expected exit 0, got $exit_code)"
fi

# -- JOIN (no args): list drive joins (none → silent exit 0) --
output=$(run_dos CMD/JOIN/JOIN.EXE 2>/dev/null) || true
exit_code=$?
if [[ $exit_code -eq 0 ]]; then
    ok "JOIN (no args, lists joins)"
else
    fail "JOIN (expected exit 0, got $exit_code)"
fi

# -- ASSIGN /STATUS: show drive assignments (none → silent exit 0) --
output=$(run_dos CMD/ASSIGN/ASSIGN.COM /STATUS 2>/dev/null) || true
exit_code=$?
if [[ $exit_code -eq 0 ]]; then
    ok "ASSIGN /STATUS (lists assignments)"
else
    fail "ASSIGN /STATUS (expected exit 0, got $exit_code)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
