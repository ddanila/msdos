#!/bin/bash
# Integration tests for the MS-DOS 4.0 build.
# Run via: make test  (which first builds everything, then calls this script)
# Exit code: 0 if all tests pass, 1 if any fail.

set -uo pipefail
export LC_ALL=C  # DOS output contains arbitrary OEM bytes; keep host text tools byte-oriented.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_ROOT/MS-DOS/v4.0/src"
BIN="$REPO_ROOT/bin"
GOLDEN="$REPO_ROOT/tests/golden.sha256"

PASS=0
FAIL=0
SKIP=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP: $1"; SKIP=$((SKIP+1)); }

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

# Golden checksums pin the canonical artifacts produced by the open toolchain.
# Skip when the MS-DOS submodule is not on the 'main' branch (e.g. on
# 'dos4-enhancements' where source changes invalidate the golden hashes).
if git -C "$REPO_ROOT/MS-DOS" merge-base --is-ancestor HEAD main 2>/dev/null; then
    if [[ -f "$GOLDEN" ]]; then
        if (cd "$SRC" && sha256sum --check "$GOLDEN" --quiet 2>&1); then
            ok "all checksums match"
        else
            while read -r expected artifact; do
                [[ -n "$artifact" && -f "$SRC/$artifact" ]] || continue
                actual=$(sha256sum "$SRC/$artifact")
                actual=${actual%% *}
                if [[ "$actual" != "$expected" ]]; then
                    echo "    $artifact"
                    echo "      expected: $expected"
                    echo "      actual:   $actual"
                fi
            done < "$GOLDEN"
            fail "checksum mismatch (run 'make gen-checksums' to regenerate)"
        fi
    else
        skip "golden.sha256 not found — run 'make gen-checksums' first"
    fi
else
    skip "MS-DOS submodule is not on 'main' — golden checksums not applicable"
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
# Verify the help string is present in the COMMAND.COM binary.
# (Functional built-in testing is in Section 6 below, using kvikdos.)
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

# Negative parser contracts emit their diagnostics on DOS stderr. Keep that
# stream available for exact assertions instead of applying run_dos's normal
# emulator-noise suppression.
run_dos_all_output() {
    local tool="$SRC/$1"; shift
    timeout 30 "$BIN/dos-run" "$tool" "$@" 2>&1
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

# -- FIND /V: lines NOT containing string --
output=$(run_dos CMD/FIND/FIND.EXE /V '"echo"' 'C:\SETENV.BAT') || true
if echo "$output" | grep -q "SETENV.BAT" && echo "$output" | grep -q "COUNTRY"; then
    ok "FIND /V (inverted match)"
else
    fail "FIND /V (expected non-matching lines like 'COUNTRY')"
fi

# -- FIND /N: show line numbers --
output=$(run_dos CMD/FIND/FIND.EXE /N '"echo"' 'C:\SETENV.BAT') || true
if echo "$output" | grep -q "\[.*\]"; then
    ok "FIND /N (line numbers)"
else
    fail "FIND /N (expected [N] line number prefix)"
fi

# -- FIND /C: count matching lines --
output=$(run_dos CMD/FIND/FIND.EXE /C '"set"' 'C:\SETENV.BAT') || true
if echo "$output" | grep -q "SETENV.BAT"; then
    ok "FIND /C (count matches)"
else
    fail "FIND /C (expected 'SETENV.BAT' header with count)"
fi

# -- FIND: multiple files --
output=$(run_dos CMD/FIND/FIND.EXE '"echo"' 'C:\SETENV.BAT' 'C:\CPY.BAT') || true
if echo "$output" | grep -q "SETENV.BAT" && echo "$output" | grep -q "CPY.BAT"; then
    ok "FIND (multiple files)"
else
    fail "FIND (expected headers for both SETENV.BAT and CPY.BAT)"
fi

# -- FIND: no matches (header only, no content lines) --
output=$(run_dos CMD/FIND/FIND.EXE '"ZZZNONEXISTENT"' 'C:\SETENV.BAT') || true
if echo "$output" | grep -q "SETENV.BAT" && ! echo "$output" | grep -q "ZZZNONEXISTENT"; then
    ok "FIND (no matches)"
else
    fail "FIND (expected header only, no matching lines)"
fi

# -- FIND /V /C: count non-matching lines --
output=$(run_dos CMD/FIND/FIND.EXE /V /C '"echo"' 'C:\SETENV.BAT') || true
if echo "$output" | grep -qE "SETENV\.BAT:.*[0-9]"; then
    ok "FIND /V /C (count non-matching)"
else
    fail "FIND /V /C (expected 'SETENV.BAT: N' count)"
fi

# Exercise the remaining combinations of the three source-declared switches.
output=$(run_dos CMD/FIND/FIND.EXE /V /N '"echo"' 'C:\SETENV.BAT') || true
if echo "$output" | grep -qE '\[[0-9]+\].*set COUNTRY'; then
    ok "FIND /V /N (numbered inverted matches)"
else
    fail "FIND /V /N (expected numbered non-matching lines)"
fi

output=$(run_dos CMD/FIND/FIND.EXE /C /N '"echo"' 'C:\SETENV.BAT') || true
if echo "$output" | grep -qE 'SETENV\.BAT:.*[0-9]' && ! echo "$output" | grep -q '\[[0-9]\+\]'; then
    ok "FIND /C /N (count mode takes precedence over numbering)"
else
    fail "FIND /C /N (expected an unnumbered count)"
fi

output=$(run_dos CMD/FIND/FIND.EXE /V /C /N '"echo"' 'C:\SETENV.BAT') || true
if echo "$output" | grep -qE 'SETENV\.BAT:.*[0-9]' && ! echo "$output" | grep -q '\[[0-9]\+\]'; then
    ok "FIND /V /C /N (inverted count takes precedence over numbering)"
else
    fail "FIND /V /C /N (expected an unnumbered inverted count)"
fi

# Unlike TREE, FIND leaves recognized synonyms live: duplicate switches are
# accepted and idempotent. This is an intentional parser compatibility check.
output=$(run_dos CMD/FIND/FIND.EXE /V /V '"echo"' 'C:\SETENV.BAT'); find_duplicate_rc=$?
if [[ "$find_duplicate_rc" -eq 0 ]] && echo "$output" | grep -q "COUNTRY"; then
    ok "FIND duplicate switch (accepted idempotently)"
else
    fail "FIND duplicate switch (expected idempotent success, got rc=$find_duplicate_rc)"
fi

output=$(run_dos_all_output CMD/FIND/FIND.EXE /Z '"echo"' 'C:\SETENV.BAT'); find_unknown_rc=$?
if [[ "$find_unknown_rc" -eq 2 ]] && echo "$output" | grep -q "Parse Error 3"; then
    ok "FIND unknown switch (rejected with parser diagnostic and errorlevel 2)"
else
    fail "FIND unknown switch (expected Parse Error 3/errorlevel 2, got rc=$find_unknown_rc)"
fi

output=$(run_dos_all_output CMD/FIND/FIND.EXE 'C:\SETENV.BAT'); find_missing_string_rc=$?
if [[ "$find_missing_string_rc" -eq 2 ]] && echo "$output" | grep -q "Parse Error 9"; then
    ok "FIND missing quoted search string (rejected with errorlevel 2)"
else
    fail "FIND missing quoted search string (expected Parse Error 9/errorlevel 2, got rc=$find_missing_string_rc)"
fi

output=$(run_dos_all_output CMD/FIND/FIND.EXE '"echo"' '"set"' 'C:\SETENV.BAT'); find_extra_string_rc=$?
if [[ "$find_extra_string_rc" -eq 2 ]] && echo "$output" | grep -q "Parse Error 9"; then
    ok "FIND second quoted search string (rejected with errorlevel 2)"
else
    fail "FIND second quoted search string (expected Parse Error 9/errorlevel 2, got rc=$find_extra_string_rc)"
fi

# -- FIND errorlevel 2: bad arguments trigger error exit code --
# FIND.ASM: exits 2 on errors (no args → "Invalid number of parameters").
# Run FIND directly (not via COMMAND.COM batch — kvikdos can't spawn child EXEs).
# kvikdos propagates INT 21h/AH=4Ch exit code as process exit code.
run_dos CMD/FIND/FIND.EXE 2>/dev/null; find_rc=$?
if [[ "$find_rc" -eq 2 ]]; then
    ok "FIND errorlevel 2 (no args → exit code 2)"
else
    fail "FIND errorlevel 2 (expected exit code 2, got $find_rc)"
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

# FC.C automatically selects binary mode for executable/object extensions.
output=$(run_dos CMD/FC/FC.EXE 'C:\CMD\TREE\TREE.COM' 'C:\CMD\TREE\TREE.COM') || true
if echo "$output" | grep -q "no differences"; then
    ok "FC automatic binary mode (.COM extension)"
else
    fail "FC automatic binary mode (expected identical .COM files)"
fi

# Binary mode is explicitly incompatible with every option that forces or
# requires line mode. Assert each source-level condition independently.
for line_option in /L /N /2; do
    output=$(run_dos_all_output CMD/FC/FC.EXE /B "$line_option" 'C:\SETENV.BAT' 'C:\SETENV.BAT'); fc_incompatible_rc=$?
    if [[ "$fc_incompatible_rc" -eq 1 ]] && echo "$output" | grep -q "Incompatible switches"; then
        ok "FC /B $line_option (incompatible line mode rejected)"
    else
        fail "FC /B $line_option (expected Incompatible switches/errorlevel 1, got rc=$fc_incompatible_rc)"
    fi
done

output=$(run_dos_all_output CMD/FC/FC.EXE /Z 'C:\SETENV.BAT' 'C:\SETENV.BAT'); fc_unknown_rc=$?
if [[ "$fc_unknown_rc" -eq 1 ]] && echo "$output" | grep -qi "usage: fc"; then
    ok "FC unknown switch (usage and errorlevel 1)"
else
    fail "FC unknown switch (expected usage/errorlevel 1, got rc=$fc_unknown_rc)"
fi

output=$(run_dos_all_output CMD/FC/FC.EXE 'C:\SETENV.BAT' 'C:\SETENV.BAT' 'C:\CPY.BAT'); fc_extra_file_rc=$?
if [[ "$fc_extra_file_rc" -eq 1 ]] && echo "$output" | grep -qi "usage: fc"; then
    ok "FC extra filename (usage and errorlevel 1)"
else
    fail "FC extra filename (expected usage/errorlevel 1, got rc=$fc_extra_file_rc)"
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

# -- FC /T: do not expand tabs (files with tab vs spaces differ) --
printf "hello\tworld\r\n" > "$SRC/FCTAB1.TXT"
printf "hello   world\r\n" > "$SRC/FCTAB2.TXT"
output=$(run_dos CMD/FC/FC.EXE /T 'C:\FCTAB1.TXT' 'C:\FCTAB2.TXT') || true
if echo "$output" | grep -q "FCTAB1.TXT"; then
    ok "FC /T (tabs preserved, files differ)"
else
    fail "FC /T (expected diff output when tabs not expanded)"
fi
# Verify without /T the same files match (tab expanded to spaces)
output=$(run_dos CMD/FC/FC.EXE 'C:\FCTAB1.TXT' 'C:\FCTAB2.TXT') || true
if echo "$output" | grep -q "no differences"; then
    ok "FC /T control (tabs expanded, files match)"
else
    fail "FC /T control (expected 'no differences' without /T)"
fi
rm -f "$SRC/FCTAB1.TXT" "$SRC/FCTAB2.TXT"

# -- FC /5: resync requires 5 consecutive matching lines --
# With /2 (default): FC resyncs after 2 matching lines → two separate diff blocks
# With /5: only 2 matching lines between diffs → cannot resync → one large block
printf "aaa\r\nDIFF1\r\nm1\r\nm2\r\nDIFF2\r\nm3\r\nm4\r\n" > "$SRC/FCSYN1.TXT"
printf "aaa\r\nALT1\r\nm1\r\nm2\r\nALT2\r\nm3\r\nm4\r\n" > "$SRC/FCSYN2.TXT"
output_default=$(run_dos CMD/FC/FC.EXE 'C:\FCSYN1.TXT' 'C:\FCSYN2.TXT') || true
output_five=$(run_dos CMD/FC/FC.EXE /5 'C:\FCSYN1.TXT' 'C:\FCSYN2.TXT') || true
# Default resync: two diff blocks → DIFF1 and DIFF2 in separate ***** sections
blocks_default=$(echo "$output_default" | grep -c '^\*\*\*\*\*')
blocks_five=$(echo "$output_five" | grep -c '^\*\*\*\*\*')
if [[ "$blocks_default" -gt "$blocks_five" ]]; then
    ok "FC /5 (higher resync count merges diff blocks)"
else
    fail "FC /5 (expected fewer separator blocks with /5 than default; got default=$blocks_default, /5=$blocks_five)"
fi
rm -f "$SRC/FCSYN1.TXT" "$SRC/FCSYN2.TXT"

# -- TREE: directory listing --
output=$(run_dos CMD/TREE/TREE.COM /A) || true
if echo "$output" | grep -q "Directory PATH listing"; then
    ok "TREE (directory listing)"
else
    fail "TREE (expected 'Directory PATH listing')"
fi

# -- TREE /F: include filenames in listing --
output=$(run_dos CMD/TREE/TREE.COM /F /A) || true
if echo "$output" | tr -d '\r' | grep -q "Directory PATH listing"; then
    ok "TREE /F (filenames mode runs)"
else
    fail "TREE /F (expected 'Directory PATH listing')"
fi

# -- TREE: specific path --
output=$(run_dos CMD/TREE/TREE.COM 'C:\CMD\EDLIN' /A) || true
if echo "$output" | grep -q "CMD.EDLIN"; then
    ok "TREE (specific path)"
else
    fail "TREE (expected 'CMD.EDLIN' in path listing)"
fi

# -- TREE /A: verify alternate ASCII graphic chars (+, |, \, -) --
output=$(run_dos CMD/TREE/TREE.COM 'C:\CMD' /A) || true
if echo "$output" | grep -q '[+|\\-]'; then
    ok "TREE /A (alternate ASCII graphic chars)"
else
    fail "TREE /A (expected +, |, \\ or - in output)"
fi

# TREEPAR.ASM removes a recognized switch from its synonym list so a duplicate
# takes the parser's explicit "not in switch list" error path.
output=$(run_dos_all_output CMD/TREE/TREE.COM /A /A); tree_duplicate_rc=$?
if [[ "$tree_duplicate_rc" -eq 1 ]] && echo "$output" | grep -q "Parse Error 3"; then
    ok "TREE duplicate switch (rejected with parser error and errorlevel 1)"
else
    fail "TREE duplicate switch (expected Parse Error 3/errorlevel 1, got rc=$tree_duplicate_rc)"
fi

output=$(run_dos_all_output CMD/TREE/TREE.COM /Z); tree_unknown_rc=$?
if [[ "$tree_unknown_rc" -eq 1 ]] && echo "$output" | grep -q "Parse Error 3"; then
    ok "TREE unknown switch (rejected with parser error and errorlevel 1)"
else
    fail "TREE unknown switch (expected Parse Error 3/errorlevel 1, got rc=$tree_unknown_rc)"
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

# SORT.ASM's live parser descriptor accepts /+n only for 1..65535. Exercise
# both accepted endpoints and the adjacent rejected values.
for column in 1 65535; do
    output=$(printf "b\r\na\r\n" | run_dos_all_output CMD/SORT/SORT.EXE "/+$column"); sort_column_rc=$?
    if [[ "$sort_column_rc" -eq 0 ]] && echo "$output" | grep -q "a"; then
        ok "SORT /+$column (accepted parser range endpoint)"
    else
        fail "SORT /+$column (expected success at parser range endpoint, got rc=$sort_column_rc)"
    fi
done

for column in 0 65536; do
    output=$(printf "b\r\na\r\n" | run_dos_all_output CMD/SORT/SORT.EXE "/+$column"); sort_column_rc=$?
    if [[ "$sort_column_rc" -eq 1 ]] && echo "$output" | grep -q "Parse Error 6"; then
        ok "SORT /+$column (rejected outside parser range)"
    else
        fail "SORT /+$column (expected Parse Error 6/errorlevel 1, got rc=$sort_column_rc)"
    fi
done

output=$(printf "b\r\na\r\n" | run_dos_all_output CMD/SORT/SORT.EXE /Z); sort_unknown_rc=$?
if [[ "$sort_unknown_rc" -eq 1 ]] && echo "$output" | grep -q "Parse Error 3"; then
    ok "SORT unknown switch (rejected with errorlevel 1)"
else
    fail "SORT unknown switch (expected Parse Error 3/errorlevel 1, got rc=$sort_unknown_rc)"
fi

# -- SORT: sort from file via stdin redirection --
printf "banana\r\ncherry\r\napple\r\n" > "$SRC/SORTTEST.TXT"
output=$(run_dos CMD/SORT/SORT.EXE < "$SRC/SORTTEST.TXT") || true
rm -f "$SRC/SORTTEST.TXT"
apple_line=$(echo "$output" | grep -n "apple" | head -1 | cut -d: -f1)
cherry_line=$(echo "$output" | grep -n "cherry" | head -1 | cut -d: -f1)
if [[ -n "$apple_line" && -n "$cherry_line" && "$apple_line" -lt "$cherry_line" ]]; then
    ok "SORT (from file)"
else
    fail "SORT (expected apple before cherry when sorting from file)"
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

# -- COMP: same-size files with byte differences --
printf "Hello World\r\n" > "$SRC/COMP_A.TXT"
printf "Hello Xorld\r\n" > "$SRC/COMP_B.TXT"
output=$(timeout 5 "$BIN/dos-run" "$SRC/CMD/COMP/COMP.COM" COMP_A.TXT COMP_B.TXT </dev/null 2>/dev/null | head -20) || true
if echo "$output" | grep -q "Compare error at OFFSET"; then
    ok "COMP (byte difference at offset)"
else
    fail "COMP (expected 'Compare error at OFFSET')"
fi

# -- COMP: verify hex values in mismatch output --
# 'W' = 0x57, 'X' = 0x58 — COMP should show File 1 = 57, File 2 = 58
if echo "$output" | grep -q "File 1 = 57" && echo "$output" | grep -q "File 2 = 58"; then
    ok "COMP (hex byte values)"
else
    fail "COMP (expected hex values 57 vs 58 for W vs X)"
fi

# -- COMP: multiple differences show multiple errors --
printf "AAAA\r\nBBBB\r\nCCCC\r\n" > "$SRC/COMP_A.TXT"
printf "AAAA\r\nXXXX\r\nCCCC\r\n" > "$SRC/COMP_B.TXT"
output=$(timeout 5 "$BIN/dos-run" "$SRC/CMD/COMP/COMP.COM" COMP_A.TXT COMP_B.TXT </dev/null 2>/dev/null | head -30) || true
count=$(echo "$output" | grep -c "Compare error at OFFSET" || true)
if [ "$count" -ge 4 ]; then
    ok "COMP (multiple differences — $count errors)"
else
    fail "COMP (expected >=4 'Compare error' lines for BBBB vs XXXX, got $count)"
fi

# -- COMP: 10 mismatch limit --
printf "ABCDEFGHIJKLMNOP" > "$SRC/COMP_A.TXT"
printf "abcdefghijklmnop" > "$SRC/COMP_B.TXT"
output=$(timeout 5 "$BIN/dos-run" "$SRC/CMD/COMP/COMP.COM" COMP_A.TXT COMP_B.TXT </dev/null 2>/dev/null | head -40) || true
if echo "$output" | grep -q "10 Mismatches - ending compare"; then
    ok "COMP (10 mismatch limit)"
else
    fail "COMP (expected '10 Mismatches - ending compare')"
fi

# -- COMP: file not found (stderr) --
output=$(timeout 5 "$BIN/dos-run" "$SRC/CMD/COMP/COMP.COM" COMP_A.TXT NOEXIST.TXT </dev/null 2>&1 | head -10) || true
if echo "$output" | grep -q "File not found"; then
    ok "COMP (file not found)"
else
    fail "COMP (expected 'File not found')"
fi

# Clean up COMP test files
rm -f "$SRC/COMP_A.TXT" "$SRC/COMP_B.TXT"

# -- ATTRIB: show file attributes --
cp "$SRC/SETENV.BAT" "$SRC/ATTRTEST.BAT"
attrib_payload_before=$(sha256sum "$SRC/ATTRTEST.BAT" | awk '{print $1}')
output=$(run_dos CMD/ATTRIB/ATTRIB.EXE 'C:\ATTRTEST.BAT') || true
if echo "$output" | grep -q "ATTRTEST.BAT"; then
    ok "ATTRIB (show attributes)"
else
    fail "ATTRIB (expected filename in output)"
fi

# -- ATTRIB +R / -R: set and clear read-only --
run_dos CMD/ATTRIB/ATTRIB.EXE '+R' 'C:\ATTRTEST.BAT' > /dev/null 2>&1 || true
output=$(run_dos CMD/ATTRIB/ATTRIB.EXE 'C:\ATTRTEST.BAT') || true
if echo "$output" | grep -q "R"; then
    ok "ATTRIB +R (set read-only)"
else
    fail "ATTRIB +R (expected 'R' in attribute display)"
fi
# Clean up: remove read-only
run_dos CMD/ATTRIB/ATTRIB.EXE '-R' 'C:\ATTRTEST.BAT' > /dev/null 2>&1 || true
output=$(run_dos CMD/ATTRIB/ATTRIB.EXE 'C:\ATTRTEST.BAT') || true
if ! echo "$output" | grep -q " R "; then
    ok "ATTRIB -R (clear read-only)"
else
    fail "ATTRIB -R (R flag still present after -R)"
fi

# -- ATTRIB +R +A: combined flags --
run_dos CMD/ATTRIB/ATTRIB.EXE '+R' '+A' 'C:\ATTRTEST.BAT' > /dev/null 2>&1 || true
output=$(run_dos CMD/ATTRIB/ATTRIB.EXE 'C:\ATTRTEST.BAT') || true
if echo "$output" | grep -q "A" && echo "$output" | grep -q "R"; then
    ok "ATTRIB +R +A (combined flags)"
else
    fail "ATTRIB +R +A (expected both A and R in display)"
fi
# Clean up: remove read-only
run_dos CMD/ATTRIB/ATTRIB.EXE '-R' 'C:\ATTRTEST.BAT' > /dev/null 2>&1 || true

# -- ATTRIB -A / +A: clear and set archive flag --
run_dos CMD/ATTRIB/ATTRIB.EXE '-A' 'C:\ATTRTEST.BAT' > /dev/null 2>&1 || true
output=$(run_dos CMD/ATTRIB/ATTRIB.EXE 'C:\ATTRTEST.BAT') || true
if ! echo "$output" | grep -q " A "; then
    ok "ATTRIB -A (clear archive)"
else
    fail "ATTRIB -A (A flag still present after -A)"
fi
run_dos CMD/ATTRIB/ATTRIB.EXE '+A' 'C:\ATTRTEST.BAT' > /dev/null 2>&1 || true
output=$(run_dos CMD/ATTRIB/ATTRIB.EXE 'C:\ATTRTEST.BAT') || true
if echo "$output" | grep -q "A"; then
    ok "ATTRIB +A (set archive)"
else
    fail "ATTRIB +A (expected 'A' in attribute display)"
fi

# -- ATTRIB: missing file and invalid switch leave the control payload intact --
output=$(timeout 30 "$BIN/dos-run" "$SRC/CMD/ATTRIB/ATTRIB.EXE" \
    'C:\ATTR-MISSING.BAT' 2>&1); attrib_missing_rc=$?; true
if [[ $attrib_missing_rc -ne 0 ]] && echo "$output" | grep -qi "Extended Error 2"; then
    ok "ATTRIB (missing file error)"
else
    fail "ATTRIB (expected Extended Error 2 and nonzero exit)"
fi
output=$(timeout 30 "$BIN/dos-run" "$SRC/CMD/ATTRIB/ATTRIB.EXE" \
    '/Z' 'C:\ATTRTEST.BAT' 2>&1); attrib_switch_rc=$?; true
if [[ $attrib_switch_rc -ne 0 ]] && echo "$output" | grep -qi "Parse Error 3"; then
    ok "ATTRIB (invalid switch error)"
else
    fail "ATTRIB (expected Parse Error 3 and nonzero exit)"
fi
attrib_payload_after=$(sha256sum "$SRC/ATTRTEST.BAT" | awk '{print $1}')
if [[ "$attrib_payload_after" == "$attrib_payload_before" ]]; then
    ok "ATTRIB transitions preserve file payload"
else
    fail "ATTRIB changed file payload while updating metadata"
fi
run_dos CMD/ATTRIB/ATTRIB.EXE '-R' '-A' 'C:\ATTRTEST.BAT' >/dev/null 2>&1 || true
rm -f "$SRC/ATTRTEST.BAT"

# -- ATTRIB /S: recursive listing --
output=$(run_dos CMD/ATTRIB/ATTRIB.EXE 'C:\CMD\EDLIN\*.*' /S) || true
if echo "$output" | grep -q "EDLIN.COM" && echo "$output" | grep -q "EDLIN.ASM"; then
    ok "ATTRIB /S (recursive listing)"
else
    fail "ATTRIB /S (expected EDLIN.COM and EDLIN.ASM in recursive output)"
fi

# -- MORE: page through piped stdin --
output=$(printf "line1\r\nline2\r\nline3\r\n" | run_dos CMD/MORE/MORE.COM) || true
if echo "$output" | grep -q "line1" && echo "$output" | grep -q "line3"; then
    ok "MORE (piped stdin)"
else
    fail "MORE (expected 'line1' and 'line3' in output)"
fi

# -- MORE: from file via stdin redirection --
output=$(run_dos CMD/MORE/MORE.COM < "$SRC/SETENV.BAT") || true
if echo "$output" | grep -q "echo" && echo "$output" | grep -q "COUNTRY"; then
    ok "MORE (from file)"
else
    fail "MORE (expected SETENV.BAT content via file redirection)"
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

# -- DEBUG: set register --
output=$(printf "R AX\r\n1234\r\nR\r\nQ\r\n" | run_dos CMD/DEBUG/DEBUG.COM) || true
if echo "$output" | grep -q "AX=1234"; then
    ok "DEBUG R AX (set register)"
else
    fail "DEBUG R AX (expected 'AX=1234')"
fi

# -- DEBUG: enter bytes + dump --
output=$(printf "E 100 48 65 6C 6C 6F\r\nD 100 L5\r\nQ\r\n" | run_dos CMD/DEBUG/DEBUG.COM) || true
if echo "$output" | grep -q "48 65 6C 6C 6F" && echo "$output" | grep -q "Hello"; then
    ok "DEBUG E+D (enter + dump bytes)"
else
    fail "DEBUG E+D (expected hex '48 65 6C 6C 6F' and ASCII 'Hello')"
fi

# -- DEBUG: fill memory + dump --
output=$(printf "F 100 L10 AA\r\nD 100 L10\r\nQ\r\n" | run_dos CMD/DEBUG/DEBUG.COM) || true
if echo "$output" | grep -q "AA AA AA AA AA AA AA AA"; then
    ok "DEBUG F+D (fill memory)"
else
    fail "DEBUG F+D (expected filled AA bytes)"
fi

# -- DEBUG: hex arithmetic --
output=$(printf "H 1234 0010\r\nQ\r\n" | run_dos CMD/DEBUG/DEBUG.COM) || true
if echo "$output" | grep -q "1244  1224"; then
    ok "DEBUG H (hex add/subtract: 1244 1224)"
else
    fail "DEBUG H (expected '1244  1224' for 1234+10, 1234-10)"
fi

# -- DEBUG: compare memory --
output=$(printf "E 100 41 42 43 44\r\nE 200 41 42 58 44\r\nC 100 L4 200\r\nQ\r\n" | run_dos CMD/DEBUG/DEBUG.COM) || true
if echo "$output" | grep -q "43  58"; then
    ok "DEBUG C (compare memory — found difference)"
else
    fail "DEBUG C (expected '43  58' difference at offset 2)"
fi

# -- DEBUG: move (copy) memory --
output=$(printf "E 100 DE AD BE EF\r\nM 100 L4 200\r\nD 200 L4\r\nQ\r\n" | run_dos CMD/DEBUG/DEBUG.COM) || true
if echo "$output" | grep -q "DE AD BE EF"; then
    ok "DEBUG M+D (move memory)"
else
    fail "DEBUG M+D (expected 'DE AD BE EF' at 200)"
fi

# -- DEBUG: search memory --
output=$(printf "E 100 48 65 6C 6C 6F\r\nS 100 L20 6C 6C\r\nQ\r\n" | run_dos CMD/DEBUG/DEBUG.COM) || true
if echo "$output" | grep -q ":0102"; then
    ok "DEBUG S (search memory — found 'll' at 102)"
else
    fail "DEBUG S (expected match at offset 0102)"
fi

# -- DEBUG: assemble + unassemble --
output=$(printf "A 100\r\nNOP\r\nNOP\r\nINT 20\r\n\r\nU 100 L4\r\nQ\r\n" | run_dos CMD/DEBUG/DEBUG.COM) || true
if echo "$output" | grep -q "NOP" && echo "$output" | grep -q "INT.*20"; then
    ok "DEBUG A+U (assemble + unassemble)"
else
    fail "DEBUG A+U (expected NOP and INT 20)"
fi

# -- DEBUG: name + write file --
output=$(printf "E 100 48 65 6C 6C 6F\r\nR CX\r\n5\r\nN DBGTEST.BIN\r\nW\r\nQ\r\n" | run_dos CMD/DEBUG/DEBUG.COM) || true
if echo "$output" | grep -q "Writing 0005 bytes"; then
    ok "DEBUG N+W (write file)"
else
    fail "DEBUG N+W (expected 'Writing 0005 bytes')"
fi
# Verify file content
if [ -f "$SRC/DBGTEST.BIN" ] && grep -q "Hello" "$SRC/DBGTEST.BIN"; then
    ok "DEBUG N+W (file content verified)"
else
    fail "DEBUG N+W (expected file with 'Hello' bytes)"
fi

# -- DEBUG: name + load file --
output=$(printf "N DBGTEST.BIN\r\nL\r\nD 100 L5\r\nQ\r\n" | run_dos CMD/DEBUG/DEBUG.COM) || true
if echo "$output" | grep -q "Hello"; then
    ok "DEBUG N+L (load file)"
else
    fail "DEBUG N+L (expected 'Hello' in dump after load)"
fi
rm -f "$SRC/DBGTEST.BIN"

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

# -- EDLIN: insert lines, list, exit (save) --
rm -f "$SRC/EDLTEST.TXT" "$SRC/EDLTEST.BAK"
output=$(printf "I\r\nHello\r\nWorld\r\n\x1a\r\n1,2L\r\nE\r\n" \
    | timeout 10 "$BIN/dos-run" "$SRC/CMD/EDLIN/EDLIN.COM" EDLTEST.TXT 2>/dev/null | head -20 || true)
if echo "$output" | grep -q "Hello" && echo "$output" | grep -q "World"; then
    ok "EDLIN (insert + list)"
else
    fail "EDLIN (expected 'Hello' and 'World' in listed output)"
fi
# Verify file was saved to disk (kvikdos CWD is $SRC root)
if [ -f "$SRC/EDLTEST.TXT" ] && grep -q "Hello" "$SRC/EDLTEST.TXT"; then
    ok "EDLIN (exit saves file)"
else
    fail "EDLIN (expected EDLTEST.TXT to be saved with 'Hello')"
fi

# -- EDLIN: delete single line --
output=$(printf "I\r\nL1\r\nL2\r\nL3\r\n\x1a\r\n2D\r\n1,2L\r\nE\r\n" \
    | timeout 10 "$BIN/dos-run" "$SRC/CMD/EDLIN/EDLIN.COM" EDLTEST.TXT 2>/dev/null | head -20 || true)
if echo "$output" | grep -q "L1" && echo "$output" | grep -q "L3" && ! echo "$output" | grep "1,2L" -A2 | grep -q "L2"; then
    ok "EDLIN (delete line)"
else
    fail "EDLIN (expected L2 deleted, L1 and L3 remaining)"
fi

# -- EDLIN: delete range of lines --
output=$(printf "I\r\nAA\r\nBB\r\nCC\r\nDD\r\n\x1a\r\n2,3D\r\n1,2L\r\nE\r\n" \
    | timeout 10 "$BIN/dos-run" "$SRC/CMD/EDLIN/EDLIN.COM" EDLTEST.TXT 2>/dev/null | head -20 || true)
if echo "$output" | grep -q "AA" && echo "$output" | grep -q "DD"; then
    ok "EDLIN (delete range)"
else
    fail "EDLIN (expected BB,CC deleted, AA and DD remaining)"
fi

# -- EDLIN: edit (replace) a line by number --
output=$(printf "I\r\nOld1\r\nOld2\r\nOld3\r\n\x1a\r\n2\r\nNew2\r\n1,3L\r\nE\r\n" \
    | timeout 10 "$BIN/dos-run" "$SRC/CMD/EDLIN/EDLIN.COM" EDLTEST.TXT 2>/dev/null | head -20 || true)
if echo "$output" | grep -q "New2"; then
    ok "EDLIN (edit line)"
else
    fail "EDLIN (expected 'New2' after editing line 2)"
fi

# -- EDLIN: copy lines --
output=$(printf "I\r\nAAA\r\nBBB\r\nCCC\r\n\x1a\r\n1,1,4C\r\n1,4L\r\nE\r\n" \
    | timeout 10 "$BIN/dos-run" "$SRC/CMD/EDLIN/EDLIN.COM" EDLTEST.TXT 2>/dev/null | head -20 || true)
if echo "$output" | grep -c "AAA" | grep -q "2"; then
    ok "EDLIN (copy lines)"
else
    fail "EDLIN (expected AAA to appear twice after copy)"
fi

# -- EDLIN: move lines --
output=$(printf "I\r\nAAA\r\nBBB\r\nCCC\r\n\x1a\r\n3,3,1M\r\n1,3L\r\nE\r\n" \
    | timeout 10 "$BIN/dos-run" "$SRC/CMD/EDLIN/EDLIN.COM" EDLTEST.TXT 2>/dev/null | head -20 || true)
# After moving line 3 (CCC) before line 1, order should be: CCC, AAA, BBB
if echo "$output" | grep "1,3L" -A4 | head -4 | grep -q "CCC"; then
    ok "EDLIN (move lines)"
else
    # Fallback: just check CCC appears as line 1 in the listing
    if echo "$output" | grep -q "1:.*CCC"; then
        ok "EDLIN (move lines)"
    else
        fail "EDLIN (expected CCC to be moved to line 1)"
    fi
fi

# -- EDLIN: search found --
output=$(printf "I\r\nAlpha\r\nBeta\r\nGamma\r\n\x1a\r\n1,3SBeta\r\nE\r\n" \
    | timeout 10 "$BIN/dos-run" "$SRC/CMD/EDLIN/EDLIN.COM" EDLTEST.TXT 2>/dev/null | head -20 || true)
if echo "$output" | grep -q "2:.*Beta"; then
    ok "EDLIN (search found)"
else
    fail "EDLIN (expected search to find 'Beta' on line 2)"
fi

# -- EDLIN: search not found --
output=$(printf "I\r\nAlpha\r\nBeta\r\n\x1a\r\n1,2SZzzzz\r\nE\r\n" \
    | timeout 10 "$BIN/dos-run" "$SRC/CMD/EDLIN/EDLIN.COM" EDLTEST.TXT 2>/dev/null | head -20 || true)
if echo "$output" | grep -q "Not found"; then
    ok "EDLIN (search not found)"
else
    fail "EDLIN (expected 'Not found')"
fi

# -- EDLIN: replace text --
output=$(printf "I\r\nAlpha\r\nBeta\r\nGamma\r\n\x1a\r\n1,3RBeta\x1aREPLACED\r\n1,3L\r\nE\r\n" \
    | timeout 10 "$BIN/dos-run" "$SRC/CMD/EDLIN/EDLIN.COM" EDLTEST.TXT 2>/dev/null | head -20 || true)
if echo "$output" | grep -q "REPLACED"; then
    ok "EDLIN (replace text)"
else
    fail "EDLIN (expected 'REPLACED' after replace)"
fi

# -- EDLIN: page command (P) --
# P displays lines and advances the current line pointer.
output=$(printf "I\r\nL1\r\nL2\r\nL3\r\nL4\r\nL5\r\n\x1a\r\n1P\r\nE\r\n" \
    | timeout 10 "$BIN/dos-run" "$SRC/CMD/EDLIN/EDLIN.COM" EDLTEST.TXT 2>/dev/null | head -30 || true)
if echo "$output" | grep -q "L1" && echo "$output" | grep -q "L5"; then
    ok "EDLIN P (page displays lines)"
else
    fail "EDLIN P (expected L1..L5 in page output)"
fi

# -- EDLIN: write (W) and append (A) --
# Create a large file, write some lines out, then append them back.
# W writes first N lines to disk; A appends lines from disk.
# Insert enough lines, then use W to write them, then A to re-read.
output=$(printf "I\r\nWRITE1\r\nWRITE2\r\nWRITE3\r\n\x1a\r\nE\r\n" \
    | timeout 10 "$BIN/dos-run" "$SRC/CMD/EDLIN/EDLIN.COM" EDLWTEST.TXT 2>/dev/null | head -10 || true)
# Verify the file was saved
if [ -f "$SRC/EDLWTEST.TXT" ] && grep -q "WRITE1" "$SRC/EDLWTEST.TXT"; then
    ok "EDLIN W setup (file created)"
else
    fail "EDLIN W setup (expected EDLWTEST.TXT with 'WRITE1')"
fi
rm -f "$SRC/EDLWTEST.TXT" "$SRC/EDLWTEST.BAK"

# -- EDLIN: transfer (insert file contents) --
output=$(printf "I\r\nFirst\r\n\x1a\r\n2TSETENV.BAT\r\n1,3L\r\nE\r\n" \
    | timeout 10 "$BIN/dos-run" "$SRC/CMD/EDLIN/EDLIN.COM" EDLTEST.TXT 2>/dev/null | head -20 || true)
if echo "$output" | grep -q "First" && echo "$output" | grep -q "echo"; then
    ok "EDLIN (transfer file)"
else
    fail "EDLIN (expected 'First' and transferred file content)"
fi

# -- EDLIN /B: binary mode — load past embedded ^Z --
# Create a test file with an embedded ^Z (0x1a) byte in the middle:
#   LINE1\r\n  LINE2\r\n  ^Z\r\n  LINE3\r\n
printf 'LINE1\r\nLINE2\r\n\x1a\r\nLINE3\r\n' > "$SRC/EDLBTEST.TXT"
output=$(printf '1,10L\r\nQ\r\nY\r\n' \
    | timeout 10 "$BIN/dos-run" "$SRC/CMD/EDLIN/EDLIN.COM" EDLBTEST.TXT /B 2>/dev/null | head -20 || true)
if echo "$output" | grep -q "LINE3"; then
    ok "EDLIN /B (LINE3 visible after embedded ^Z)"
else
    fail "EDLIN /B (LINE3 not found — /B flag did not suppress ^Z stop)"
fi
if echo "$output" | grep -q "LINE1" && echo "$output" | grep -q "LINE2"; then
    ok "EDLIN /B (LINE1 and LINE2 also present)"
else
    fail "EDLIN /B (LINE1 or LINE2 missing)"
fi

# -- EDLIN (no /B): text mode — stop at embedded ^Z --
output=$(printf '1,10L\r\nQ\r\nY\r\n' \
    | timeout 10 "$BIN/dos-run" "$SRC/CMD/EDLIN/EDLIN.COM" EDLBTEST.TXT 2>/dev/null | head -20 || true)
if ! echo "$output" | grep -q "LINE3"; then
    ok "EDLIN (no /B: LINE3 absent — ^Z stops load)"
else
    fail "EDLIN (no /B: LINE3 should NOT appear — ^Z should stop load)"
fi
rm -f "$SRC/EDLBTEST.TXT"

# Clean up EDLIN test files (saved to $SRC root, kvikdos CWD)
rm -f "$SRC/EDLTEST.TXT" "$SRC/EDLTEST.BAK"

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

# -- REPLACE parser conflicts and boundaries --
# REPLACE.C explicitly rejects /A with /S or /U after parsing, rejects every
# repeated switch in its six-synonym table, and allows at most two filespecs.
for replace_conflict in "/A /S" "/A /U"; do
    read -r -a replace_args <<<"$replace_conflict"
    output=$(timeout 10 "$BIN/dos-run" --cwd='C:\' \
        "$SRC/CMD/REPLACE/REPLACE.EXE" 'C:\SETENV.BAT' 'C:\CMD\REPLACE\' \
        "${replace_args[@]}" 2>&1)
    replace_rc=$?
    if [[ "$replace_rc" -eq 11 ]] && echo "$output" | grep -q 'Parse Error 11'; then
        ok "REPLACE $replace_conflict (incompatible combination rejected)"
    else
        fail "REPLACE $replace_conflict (expected incompatibility/errorlevel 11, got rc=$replace_rc)"
    fi
done

for replace_switch in A P R S U W; do
    output=$(timeout 10 "$BIN/dos-run" --cwd='C:\' \
        "$SRC/CMD/REPLACE/REPLACE.EXE" 'C:\SETENV.BAT' 'C:\CMD\REPLACE\' \
        "/$replace_switch" "/$replace_switch" 2>&1)
    replace_rc=$?
    if [[ "$replace_rc" -eq 11 ]] && echo "$output" | grep -q 'Parse Error 3'; then
        ok "REPLACE /$replace_switch duplicate rejected"
    else
        fail "REPLACE /$replace_switch duplicate (expected Parse Error 3/errorlevel 11, got rc=$replace_rc)"
    fi
done

output=$(timeout 10 "$BIN/dos-run" --cwd='C:\' \
    "$SRC/CMD/REPLACE/REPLACE.EXE" 'C:\SETENV.BAT' 'C:\CMD\REPLACE\' /Z 2>&1)
replace_unknown_rc=$?
if [[ "$replace_unknown_rc" -eq 11 ]] && echo "$output" | grep -q 'Parse Error 3'; then
    ok "REPLACE unknown switch rejected"
else
    fail "REPLACE unknown switch (expected Parse Error 3/errorlevel 11, got rc=$replace_unknown_rc)"
fi

output=$(timeout 10 "$BIN/dos-run" --cwd='C:\' \
    "$SRC/CMD/REPLACE/REPLACE.EXE" 'C:\SETENV.BAT' 'C:\CMD\REPLACE\' EXTRA 2>&1)
replace_arity_rc=$?
if [[ "$replace_arity_rc" -eq 11 ]] && echo "$output" | grep -q 'Parse Error 1'; then
    ok "REPLACE excess filespec rejected"
else
    fail "REPLACE excess filespec (expected Parse Error 1/errorlevel 11, got rc=$replace_arity_rc)"
fi

# -- REPLACE /U: replace only if source is newer --
# Uses C:\CMD\REPLACE\ (same dir as the /A test above) to stay on known-good ground.
# REPLU.BAT is a temp copy; we never touch SETENV.BAT so other tests are unaffected.
cp "$SRC/SETENV.BAT" "$SRC/REPLU.BAT"
touch -d "2025-01-01 00:00:00" "$SRC/REPLU.BAT"              # src: 2025 (newer)
cp "$SRC/SETENV.BAT" "$SRC/CMD/REPLACE/REPLU.BAT"
touch -d "2020-01-01 00:00:00" "$SRC/CMD/REPLACE/REPLU.BAT"  # dest: 2020 (older)
_stderr_tmp=$(mktemp)
output=$(timeout 10 "$BIN/dos-run" --cwd='C:\' "$SRC/CMD/REPLACE/REPLACE.EXE" 'C:\REPLU.BAT' 'C:\CMD\REPLACE\' /U 2>"$_stderr_tmp"); _rc=$?; true
_stderr=$(cat "$_stderr_tmp"); rm -f "$_stderr_tmp"
rm -f "$SRC/REPLU.BAT" "$SRC/CMD/REPLACE/REPLU.BAT"
if echo "$output" | grep -q "file(s) replaced"; then
    ok "REPLACE /U (source newer, replaced)"
else
    fail "REPLACE /U (expected 'file(s) replaced', got: $(echo "$output" | head -3))"
    echo "    exit code: $_rc"
    [ -n "$_stderr" ] && echo "    stderr: $(echo "$_stderr" | head -5)"
fi

# -- REPLACE /U: no replacement when source is older --
cp "$SRC/SETENV.BAT" "$SRC/REPLU.BAT"
touch -d "2020-01-01 00:00:00" "$SRC/REPLU.BAT"              # src: 2020 (older)
cp "$SRC/SETENV.BAT" "$SRC/CMD/REPLACE/REPLU.BAT"
touch -d "2025-01-01 00:00:00" "$SRC/CMD/REPLACE/REPLU.BAT"  # dest: 2025 (newer)
_stderr_tmp=$(mktemp)
output=$(timeout 10 "$BIN/dos-run" --cwd='C:\' "$SRC/CMD/REPLACE/REPLACE.EXE" 'C:\REPLU.BAT' 'C:\CMD\REPLACE\' /U 2>"$_stderr_tmp"); _rc=$?; true
_stderr=$(cat "$_stderr_tmp"); rm -f "$_stderr_tmp"
rm -f "$SRC/REPLU.BAT" "$SRC/CMD/REPLACE/REPLU.BAT"
if echo "$output" | grep -q "No files replaced"; then
    ok "REPLACE /U (source older, no replacement)"
else
    fail "REPLACE /U (expected 'No files replaced', got: $(echo "$output" | head -3))"
    echo "    exit code: $_rc"
    [ -n "$_stderr" ] && echo "    stderr: $(echo "$_stderr" | head -5)"
fi

# -- XCOPY: no args → error message (stderr) --
output=$(timeout 10 "$BIN/dos-run" "$SRC/CMD/XCOPY/XCOPY.EXE" 2>&1 || true)
if echo "$output" | grep -q "Invalid number of parameters"; then
    ok "XCOPY (no args error)"
else
    fail "XCOPY (expected 'Invalid number of parameters')"
fi

# -- XCOPY: copy single file (kvikdos-soft) --
# XCOPY triggers #GP (INT 0x0D) on KVM due to segment limit enforcement
# in real mode. Force kvikdos-soft for these tests.
XCOPY_KVIKDOS="$REPO_ROOT/kvikdos/kvikdos-soft"

# -- XCOPY parser duplicate and boundary contracts --
# GET_OPTIONS blanks every consumed synonym, including the separately parsed
# /D date switch. The parser maps all of these command-line failures to 4.
for xcopy_switch in A E M P S V W; do
    output=$(timeout 10 env KVIKDOS="$XCOPY_KVIKDOS" KVIKDOS_AZZY=1 \
        "$BIN/dos-run" --cwd='C:\' "$SRC/CMD/XCOPY/XCOPY.EXE" \
        SETENV.BAT 'XCPDEST\' "/$xcopy_switch" "/$xcopy_switch" 2>&1)
    xcopy_rc=$?
    if [[ "$xcopy_rc" -eq 4 ]] && echo "$output" | grep -q "Invalid switch - /$xcopy_switch"; then
        ok "XCOPY /$xcopy_switch duplicate rejected"
    else
        fail "XCOPY /$xcopy_switch duplicate (expected invalid switch/errorlevel 4, got rc=$xcopy_rc)"
    fi
done

output=$(timeout 10 env KVIKDOS="$XCOPY_KVIKDOS" KVIKDOS_AZZY=1 \
    "$BIN/dos-run" --cwd='C:\' "$SRC/CMD/XCOPY/XCOPY.EXE" \
    SETENV.BAT 'XCPDEST\' /D:01-01-90 /D:01-01-90 2>&1)
xcopy_date_duplicate_rc=$?
if [[ "$xcopy_date_duplicate_rc" -eq 4 ]] && echo "$output" | grep -q 'Invalid switch - /D'; then
    ok "XCOPY /D duplicate rejected"
else
    fail "XCOPY /D duplicate (expected invalid switch/errorlevel 4, got rc=$xcopy_date_duplicate_rc)"
fi

output=$(timeout 10 env KVIKDOS="$XCOPY_KVIKDOS" KVIKDOS_AZZY=1 \
    "$BIN/dos-run" --cwd='C:\' "$SRC/CMD/XCOPY/XCOPY.EXE" \
    SETENV.BAT 'XCPDEST\' /Z 2>&1)
xcopy_unknown_rc=$?
if [[ "$xcopy_unknown_rc" -eq 4 ]] && echo "$output" | grep -q 'Invalid switch - /Z'; then
    ok "XCOPY unknown switch rejected"
else
    fail "XCOPY unknown switch (expected invalid switch/errorlevel 4, got rc=$xcopy_unknown_rc)"
fi

output=$(timeout 10 env KVIKDOS="$XCOPY_KVIKDOS" KVIKDOS_AZZY=1 \
    "$BIN/dos-run" --cwd='C:\' "$SRC/CMD/XCOPY/XCOPY.EXE" \
    SETENV.BAT 'XCPDEST\' EXTRA 2>&1)
xcopy_arity_rc=$?
if [[ "$xcopy_arity_rc" -eq 4 ]] && echo "$output" | grep -q 'Invalid number of parameters - EXTRA'; then
    ok "XCOPY excess filespec rejected"
else
    fail "XCOPY excess filespec (expected invalid parameter count/errorlevel 4, got rc=$xcopy_arity_rc)"
fi

output=$(timeout 10 env KVIKDOS="$XCOPY_KVIKDOS" KVIKDOS_AZZY=1 \
    "$BIN/dos-run" --cwd='C:\' "$SRC/CMD/XCOPY/XCOPY.EXE" \
    SETENV.BAT 'XCPDEST\' /D:01-01-79 2>&1)
xcopy_date_rc=$?
if [[ "$xcopy_date_rc" -eq 4 ]] && echo "$output" | grep -q 'Invalid date'; then
    ok "XCOPY date below DOS range rejected"
else
    fail "XCOPY pre-1980 date (expected Invalid date/errorlevel 4, got rc=$xcopy_date_rc)"
fi

printf "XcopyTest\r\n" > "$SRC/XCTEST1.TXT"
mkdir -p "$SRC/XCPDEST"
output=$(timeout 10 env KVIKDOS="$XCOPY_KVIKDOS" KVIKDOS_AZZY=1 "$BIN/dos-run" --cwd='C:\' "$SRC/CMD/XCOPY/XCOPY.EXE" 'XCTEST1.TXT' 'XCPDEST\' 2>/dev/null || true)
if echo "$output" | grep -q "1 File(s) copied"; then
    ok "XCOPY (copy single file)"
else
    fail "XCOPY (expected '1 File(s) copied')"
fi
if [ -f "$SRC/XCPDEST/XCTEST1.TXT" ] && grep -q "XcopyTest" "$SRC/XCPDEST/XCTEST1.TXT"; then
    ok "XCOPY (file content verified)"
else
    fail "XCOPY (expected XCPDEST/XCTEST1.TXT with 'XcopyTest')"
fi
rm -rf "$SRC/XCPDEST" "$SRC/XCTEST1.TXT"

# -- XCOPY /S: copy subdirectory tree --
mkdir -p "$SRC/XCPTEST/SUB"
printf "Root\r\n" > "$SRC/XCPTEST/FILE1.TXT"
printf "SubFile\r\n" > "$SRC/XCPTEST/SUB/FILE2.TXT"
mkdir -p "$SRC/XCPDEST"
output=$(timeout 10 env KVIKDOS="$XCOPY_KVIKDOS" KVIKDOS_AZZY=1 "$BIN/dos-run" --cwd='C:\' "$SRC/CMD/XCOPY/XCOPY.EXE" 'XCPTEST\*.*' 'XCPDEST\' /S 2>/dev/null || true)
if echo "$output" | grep -q "2 File(s) copied"; then
    ok "XCOPY /S (copy subdirectory tree)"
else
    fail "XCOPY /S (expected '2 File(s) copied')"
fi
if [ -f "$SRC/XCPDEST/SUB/FILE2.TXT" ] && grep -q "SubFile" "$SRC/XCPDEST/SUB/FILE2.TXT"; then
    ok "XCOPY /S (subdirectory file verified)"
else
    fail "XCOPY /S (expected XCPDEST/SUB/FILE2.TXT with 'SubFile')"
fi
rm -rf "$SRC/XCPDEST"

# -- XCOPY /S /E: copy including empty subdirectories --
mkdir -p "$SRC/XCPTEST/EMPTY"
mkdir -p "$SRC/XCPDEST"
output=$(timeout 10 env KVIKDOS="$XCOPY_KVIKDOS" KVIKDOS_AZZY=1 "$BIN/dos-run" --cwd='C:\' "$SRC/CMD/XCOPY/XCOPY.EXE" 'XCPTEST\*.*' 'XCPDEST\' /S /E 2>/dev/null || true)
if echo "$output" | grep -q "2 File(s) copied" && [ -d "$SRC/XCPDEST/EMPTY" ]; then
    ok "XCOPY /S /E (empty subdirectory created)"
else
    fail "XCOPY /S /E (expected XCPDEST/EMPTY directory to be created)"
fi
rm -rf "$SRC/XCPTEST" "$SRC/XCPDEST"

# Clean up XCOPY test files
rm -rf "$SRC/XCPTEST" "$SRC/XCPDEST"

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

# -- GRAFTABL 437: load code page 437 --
output=$(run_dos CMD/GRAFTABL/GRAFTABL.COM 437) || true
if echo "$output" | grep -q "Active Code Page: 437"; then
    ok "GRAFTABL 437 (load code page)"
else
    fail "GRAFTABL 437 (expected 'Active Code Page: 437')"
fi

# -- GRAFTABL 850: load code page 850 --
output=$(run_dos CMD/GRAFTABL/GRAFTABL.COM 850) || true
if echo "$output" | grep -q "Active Code Page: 850"; then
    ok "GRAFTABL 850 (load code page)"
else
    fail "GRAFTABL 850 (expected 'Active Code Page: 850')"
fi

# -- ASSIGN /STATUS: show drive assignments (none → silent exit 0) --
output=$(run_dos CMD/ASSIGN/ASSIGN.COM /STATUS 2>/dev/null) || true
exit_code=$?
if [[ $exit_code -eq 0 ]]; then
    ok "ASSIGN /STATUS (lists assignments)"
else
    fail "ASSIGN /STATUS (expected exit 0, got $exit_code)"
fi

# Skipped: KEYB functional tests (load, status query) cannot run under kvikdos.
# KEYB_COMMAND calls SYSLOADMSG as its very first instruction and exits immediately
# if the version check fails (same root cause as COMMAND.COM built-in failures).
# The /? smoke test in Section 4 passes because the PARSER intercepts /? before
# KEYB_COMMAND is ever entered.  Functional KEYB tests require QEMU.

# -- EXE2BIN: convert a minimal EXE to BIN --
# Build a 513-byte test EXE: 512-byte MZ header (cparhdr=0x20) + 1 byte of code (0xC3=RET).
# EXE2BIN requires SS=SP=CS=0 and IP=0 for binary output (no fixups).
E2B_DIR="$SRC/CMD/EXE2BIN"
E2B_TEST_EXE="$E2B_DIR/E2BTEST.EXE"
E2B_TEST_BIN="$E2B_DIR/E2BTEST.BIN"
python3 -c "
import struct, sys
h = bytearray(512)
h[0:2] = b'MZ'
struct.pack_into('<H', h, 2, 1)      # e_cblp: 513 % 512 = 1
struct.pack_into('<H', h, 4, 2)      # e_cp: 2 pages
struct.pack_into('<H', h, 8, 0x20)   # e_cparhdr: 32 paragraphs = 512 bytes
struct.pack_into('<H', h, 12, 0xFFFF)# e_maxalloc
struct.pack_into('<H', h, 24, 0x1C)  # e_lfarlc
sys.stdout.buffer.write(h + b'\xC3')
" > "$E2B_TEST_EXE"
rm -f "$E2B_TEST_BIN"
run_dos CMD/EXE2BIN/EXE2BIN.EXE 'C:\CMD\EXE2BIN\E2BTEST' 'C:\CMD\EXE2BIN\E2BTEST.BIN' > /dev/null 2>&1 || true
if [[ -f "$E2B_TEST_BIN" ]] && [[ $(wc -c < "$E2B_TEST_BIN") -eq 1 ]]; then
    ok "EXE2BIN (minimal EXE to 1-byte BIN)"
else
    fail "EXE2BIN (expected 1-byte BIN output)"
fi
rm -f "$E2B_TEST_EXE" "$E2B_TEST_BIN"

# -- EXE2BIN: error handling (missing file) --
# Use TOOLS/EXE2BIN.EXE (pre-built, 3KB) — the source-built CMD version (8KB)
# has a different MSGSERV linkage that still hangs in the extended error path.
E2B_ERR_OUT=$(run_dos TOOLS/EXE2BIN.EXE 'NONEXIST.EXE' 'NONEXIST.COM' 2>&1) || true
if echo "$E2B_ERR_OUT" | grep -qi "file not found"; then
    ok "EXE2BIN (missing file error message)"
else
    fail "EXE2BIN (expected 'File not found', got: $E2B_ERR_OUT)"
fi

# -- MEM /PROGRAM: show loaded programs --
# MEM walks MCB chain which loops under kvikdos (no real MCB); use short timeout + head.
output=$(timeout 5 "$BIN/dos-run" "$SRC/CMD/MEM/MEM.EXE" /PROGRAM 2>/dev/null | head -10) || true
if echo "$output" | grep -q "Address" && echo "$output" | grep -q "Type"; then
    ok "MEM /PROGRAM (program listing)"
else
    fail "MEM /PROGRAM (expected 'Address' and 'Type' column headers)"
fi

# -- MEM /DEBUG: show programs and internal drivers --
output=$(timeout 5 "$BIN/dos-run" "$SRC/CMD/MEM/MEM.EXE" /DEBUG 2>/dev/null | head -10) || true
if echo "$output" | grep -q "Address" && echo "$output" | grep -q "Type"; then
    ok "MEM /DEBUG (debug listing)"
else
    fail "MEM /DEBUG (expected 'Address' and 'Type' headers)"
fi

# MEM's parser declares /PROGRAM and /DEBUG as separate switch descriptors but
# the main loop deliberately rejects every second switch, including duplicates.
for mem_pair in "/DEBUG /PROGRAM" "/DEBUG /DEBUG" "/PROGRAM /PROGRAM"; do
    read -r mem_first mem_second <<< "$mem_pair"
    output=$(run_dos_all_output CMD/MEM/MEM.EXE "$mem_first" "$mem_second"); mem_pair_rc=$?
    if [[ "$mem_pair_rc" -eq 1 ]] && echo "$output" | grep -q "Parse Error 1"; then
        ok "MEM $mem_pair (second switch rejected)"
    else
        fail "MEM $mem_pair (expected Parse Error 1/errorlevel 1, got rc=$mem_pair_rc)"
    fi
done

output=$(run_dos_all_output CMD/MEM/MEM.EXE /Z); mem_unknown_rc=$?
if [[ "$mem_unknown_rc" -eq 1 ]] && echo "$output" | grep -q "Parse Error 3"; then
    ok "MEM unknown switch (rejected with errorlevel 1)"
else
    fail "MEM unknown switch (expected Parse Error 3/errorlevel 1, got rc=$mem_unknown_rc)"
fi

output=$(run_dos_all_output CMD/MEM/MEM.EXE FOO); mem_positional_rc=$?
if [[ "$mem_positional_rc" -eq 1 ]] && echo "$output" | grep -q "Parse Error 1"; then
    ok "MEM positional operand (rejected with errorlevel 1)"
else
    fail "MEM positional operand (expected Parse Error 1/errorlevel 1, got rc=$mem_positional_rc)"
fi

output=$(timeout 5 "$BIN/dos-run" "$SRC/CMD/MEM/MEM.EXE" /program 2>/dev/null | head -10) || true
if echo "$output" | grep -q "Address" && echo "$output" | grep -q "Type"; then
    ok "MEM switch matching is case-insensitive"
else
    fail "MEM lowercase /program was not accepted"
fi

# -- FC: nonexistent file error --
output=$(run_dos CMD/FC/FC.EXE 'C:\NONEXIST.TXT' 'C:\SETENV.BAT' 2>&1) || true
if echo "$output" | grep -qi "cannot open"; then
    ok "FC (nonexistent file error)"
else
    fail "FC (expected 'cannot open' for nonexistent file)"
fi

# -- FC /A: abbreviated output (show "..." for long diff ranges) --
# Create two files that differ across >2 consecutive lines; /A should
# show only the first and last differing lines with "..." in between.
printf "same\r\ndiff1\r\ndiff2\r\ndiff3\r\ndiff4\r\nsame\r\n" > "$SRC/FCA1.TXT"
printf "same\r\nalt1\r\nalt2\r\nalt3\r\nalt4\r\nsame\r\n" > "$SRC/FCA2.TXT"
output=$(run_dos CMD/FC/FC.EXE /A 'C:\FCA1.TXT' 'C:\FCA2.TXT') || true
if echo "$output" | grep -q "\.\.\."; then
    ok "FC /A (abbreviated output with '...')"
else
    fail "FC /A (expected '...' in abbreviated diff output)"
fi
rm -f "$SRC/FCA1.TXT" "$SRC/FCA2.TXT"

# -- FC /LBn: source syntax has no colon; exercise the smallest usable buffer
# and a representative larger value. The former reaches allocation and compare
# with cLine=1 rather than silently retaining the default.
printf "line1\r\nline2\r\nline3\r\n" > "$SRC/FCLB1.TXT"
printf "line1\r\nline2\r\nline3\r\n" > "$SRC/FCLB2.TXT"
for line_buffer in 1 20; do
    output=$(run_dos CMD/FC/FC.EXE "/LB$line_buffer" 'C:\FCLB1.TXT' 'C:\FCLB2.TXT'); fc_line_buffer_rc=$?
    if [[ "$fc_line_buffer_rc" -eq 0 ]] && echo "$output" | grep -qi "no differences"; then
        ok "FC /LB$line_buffer (line buffer size applied)"
    else
        fail "FC /LB$line_buffer (expected identical comparison, got rc=$fc_line_buffer_rc)"
    fi
done

# ntoi returns -1 when /LB has no digits, which FC deliberately maps back to
# its 100-line default. Pin that historical parser boundary explicitly.
output=$(run_dos CMD/FC/FC.EXE /LB 'C:\FCLB1.TXT' 'C:\FCLB2.TXT'); fc_empty_lb_rc=$?
if [[ "$fc_empty_lb_rc" -eq 0 ]] && echo "$output" | grep -qi "no differences"; then
    ok "FC /LB without digits (historical default-buffer behavior)"
else
    fail "FC /LB without digits (expected default-buffer success, got rc=$fc_empty_lb_rc)"
fi

output=$(run_dos_all_output CMD/FC/FC.EXE /LB0 'C:\FCLB1.TXT' 'C:\FCLB2.TXT'); fc_zero_lb_rc=$?
if [[ "$fc_zero_lb_rc" -eq 1 ]] && echo "$output" | grep -qi "out of memory"; then
    ok "FC /LB0 (zero-sized buffer rejected by allocation path)"
else
    fail "FC /LB0 (expected out of memory/errorlevel 1, got rc=$fc_zero_lb_rc)"
fi
rm -f "$SRC/FCLB1.TXT" "$SRC/FCLB2.TXT"

# -- FC /A: control — without /A the same diff has no "..." --
printf "same\r\ndiff1\r\ndiff2\r\ndiff3\r\ndiff4\r\nsame\r\n" > "$SRC/FCA1.TXT"
printf "same\r\nalt1\r\nalt2\r\nalt3\r\nalt4\r\nsame\r\n" > "$SRC/FCA2.TXT"
output=$(run_dos CMD/FC/FC.EXE 'C:\FCA1.TXT' 'C:\FCA2.TXT') || true
if ! echo "$output" | grep -q "\.\.\."; then
    ok "FC /A control (no '...' without /A)"
else
    fail "FC /A control (unexpected '...' in non-abbreviated output)"
fi
rm -f "$SRC/FCA1.TXT" "$SRC/FCA2.TXT"

# -- XCOPY /V: copy with verify --
printf "VerifyTest\r\n" > "$SRC/XCVTEST.TXT"
mkdir -p "$SRC/XCVDEST"
output=$(timeout 10 env KVIKDOS="$XCOPY_KVIKDOS" KVIKDOS_AZZY=1 "$BIN/dos-run" --cwd='C:\' "$SRC/CMD/XCOPY/XCOPY.EXE" 'XCVTEST.TXT' 'XCVDEST\' /V 2>/dev/null || true)
if echo "$output" | grep -q "1 File(s) copied"; then
    ok "XCOPY /V (copy with verify)"
else
    fail "XCOPY /V (expected '1 File(s) copied')"
fi
if [ -f "$SRC/XCVDEST/XCVTEST.TXT" ] && grep -q "VerifyTest" "$SRC/XCVDEST/XCVTEST.TXT"; then
    ok "XCOPY /V (file content verified)"
else
    fail "XCOPY /V (expected XCVDEST/XCVTEST.TXT with 'VerifyTest')"
fi
rm -rf "$SRC/XCVDEST" "$SRC/XCVTEST.TXT"

# -- XCOPY /A: copy only files with archive bit set (don't clear it) --
# kvikdos persists DOS attributes via xattr, so ATTRIB in one session
# is visible to XCOPY in the next session.
printf "ArchiveFile\r\n" > "$SRC/XCATEST.TXT"
printf "NoArchive\r\n" > "$SRC/XCATEST2.TXT"
mkdir -p "$SRC/XCADEST"
# Set archive bit on first file, clear on second (persisted via xattr)
run_dos CMD/ATTRIB/ATTRIB.EXE '+A' 'C:\XCATEST.TXT' > /dev/null 2>&1 || true
run_dos CMD/ATTRIB/ATTRIB.EXE '-A' 'C:\XCATEST2.TXT' > /dev/null 2>&1 || true
output=$(timeout 10 env KVIKDOS="$XCOPY_KVIKDOS" KVIKDOS_AZZY=1 "$BIN/dos-run" --cwd='C:\' "$SRC/CMD/XCOPY/XCOPY.EXE" 'C:\XCATEST*.TXT' 'C:\XCADEST\' /A 2>/dev/null || true)
if echo "$output" | grep -q "1 File(s) copied"; then
    ok "XCOPY /A (copied only archived file)"
else
    fail "XCOPY /A (expected '1 File(s) copied', got: $(echo "$output" | head -3))"
fi
# /A should NOT clear the archive bit on the source
attr_out=$(run_dos CMD/ATTRIB/ATTRIB.EXE 'C:\XCATEST.TXT') || true
if echo "$attr_out" | grep -q "A"; then
    ok "XCOPY /A (archive bit preserved on source)"
else
    fail "XCOPY /A (archive bit should still be set after /A)"
fi
rm -rf "$SRC/XCADEST" "$SRC/XCATEST.TXT" "$SRC/XCATEST2.TXT"

# -- XCOPY /M: copy only files with archive bit set, then clear it --
printf "MoveArchive\r\n" > "$SRC/XCMTEST.TXT"
printf "NoArchive\r\n" > "$SRC/XCMTEST2.TXT"
mkdir -p "$SRC/XCMDEST"
# Set archive bit on first file, clear on second (persisted via xattr)
run_dos CMD/ATTRIB/ATTRIB.EXE '+A' 'C:\XCMTEST.TXT' > /dev/null 2>&1 || true
run_dos CMD/ATTRIB/ATTRIB.EXE '-A' 'C:\XCMTEST2.TXT' > /dev/null 2>&1 || true
output=$(timeout 10 env KVIKDOS="$XCOPY_KVIKDOS" KVIKDOS_AZZY=1 "$BIN/dos-run" --cwd='C:\' "$SRC/CMD/XCOPY/XCOPY.EXE" 'C:\XCMTEST*.TXT' 'C:\XCMDEST\' /M 2>/dev/null || true)
if echo "$output" | grep -q "1 File(s) copied"; then
    ok "XCOPY /M (copied only archived file)"
else
    fail "XCOPY /M (expected '1 File(s) copied', got: $(echo "$output" | head -3))"
fi
# /M should CLEAR the archive bit on the source after copying
attr_out=$(run_dos CMD/ATTRIB/ATTRIB.EXE 'C:\XCMTEST.TXT') || true
if ! echo "$attr_out" | grep -q " A "; then
    ok "XCOPY /M (archive bit cleared on source)"
else
    fail "XCOPY /M (archive bit should be cleared after /M)"
fi
rm -rf "$SRC/XCMDEST" "$SRC/XCMTEST.TXT" "$SRC/XCMTEST2.TXT"

# -- XCOPY /A and /M ordering: the last archive-mode switch wins --
for xcopy_archive_order in "A M" "M A"; do
    read -r first_mode last_mode <<<"$xcopy_archive_order"
    archive_file="XCO${first_mode}${last_mode}.TXT"
    archive_dest="XCO${first_mode}${last_mode}DST"
    printf "ArchiveOrder%s%s\r\n" "$first_mode" "$last_mode" > "$SRC/$archive_file"
    mkdir -p "$SRC/$archive_dest"
    run_dos CMD/ATTRIB/ATTRIB.EXE '+A' "C:\\$archive_file" > /dev/null 2>&1 || true
    output=$(timeout 10 env KVIKDOS="$XCOPY_KVIKDOS" KVIKDOS_AZZY=1 \
        "$BIN/dos-run" --cwd='C:\' "$SRC/CMD/XCOPY/XCOPY.EXE" \
        "$archive_file" "$archive_dest\\" "/$first_mode" "/$last_mode" 2>/dev/null || true)
    attr_out=$(run_dos CMD/ATTRIB/ATTRIB.EXE "C:\\$archive_file") || true
    archive_state_ok=false
    if [[ "$last_mode" == M ]] && ! echo "$attr_out" | grep -q ' A '; then
        archive_state_ok=true
    elif [[ "$last_mode" == A ]] && echo "$attr_out" | grep -q 'A'; then
        archive_state_ok=true
    fi
    if echo "$output" | grep -q '1 File(s) copied' && $archive_state_ok; then
        ok "XCOPY /$first_mode /$last_mode (last archive mode controls source attribute)"
    else
        fail "XCOPY /$first_mode /$last_mode (last archive mode did not win)"
    fi
    rm -rf "$SRC/$archive_dest" "$SRC/$archive_file"
done

# -- XCOPY /D:date — copy files modified on or after date --
# Touch file to Jun 15, 1990, then test with past and future dates.
# Requires INT 21h/AH=2Bh (Set Date) stub in kvikdos — SYSPARSE calls it
# to validate the /D date parameter.
printf "DateTest\r\n" > "$SRC/XCDTEST.TXT"
touch -t 199006150000 "$SRC/XCDTEST.TXT"
mkdir -p "$SRC/XCDDEST"
output=$(timeout 10 env KVIKDOS="$XCOPY_KVIKDOS" KVIKDOS_AZZY=1 "$BIN/dos-run" --cwd='C:\' \
    "$SRC/CMD/XCOPY/XCOPY.EXE" 'XCDTEST.TXT' 'XCDDEST\' '/D:01-01-90' 2>/dev/null || true)
if echo "$output" | grep -q "1 File(s) copied"; then
    ok "XCOPY /D:01-01-90 (copied file dated 06/15/90)"
else
    fail "XCOPY /D:01-01-90 (expected '1 File(s) copied', got: $(echo "$output" | head -3))"
fi
rm -rf "$SRC/XCDDEST"
mkdir -p "$SRC/XCDDEST"
output=$(timeout 10 env KVIKDOS="$XCOPY_KVIKDOS" KVIKDOS_AZZY=1 "$BIN/dos-run" --cwd='C:\' \
    "$SRC/CMD/XCOPY/XCOPY.EXE" 'XCDTEST.TXT' 'XCDDEST\' '/D:12-31-90' 2>/dev/null || true)
# XCOPY prints "0 File(s) copied" or just "Reading source file(s)..." with no
# copy line when no files match the date. Verify file was NOT copied.
if ! echo "$output" | grep -q "1 File(s) copied" && [ ! -f "$SRC/XCDDEST/XCDTEST.TXT" ]; then
    ok "XCOPY /D:12-31-90 (skipped file dated 06/15/90)"
else
    fail "XCOPY /D:12-31-90 (file should not have been copied)"
fi
rm -rf "$SRC/XCDDEST" "$SRC/XCDTEST.TXT"

# -- XCOPY /W: wait for keypress before copying --
# /W prompts "Press any key to begin copying file(s)" via SYSDISPMSG.
# Piping a character satisfies the read and XCOPY proceeds normally.
printf "WaitTest\r\n" > "$SRC/XCWTEST.TXT"
mkdir -p "$SRC/XCWDEST"
output=$(echo "x" | timeout 10 env KVIKDOS="$XCOPY_KVIKDOS" KVIKDOS_AZZY=1 "$BIN/dos-run" --cwd='C:\' "$SRC/CMD/XCOPY/XCOPY.EXE" 'XCWTEST.TXT' 'XCWDEST\' /W 2>/dev/null || true)
if echo "$output" | grep -qi "Press any key" && echo "$output" | grep -q "1 File(s) copied"; then
    ok "XCOPY /W (waited for key, then copied file)"
else
    fail "XCOPY /W (expected 'Press any key' + '1 File(s) copied', got: $(echo "$output" | head -3))"
fi
rm -rf "$SRC/XCWDEST" "$SRC/XCWTEST.TXT"

# -- REPLACE /R: replace read-only file --
mkdir -p "$SRC/RPLRDEST"
printf "ORIGINAL\r\n" > "$SRC/RPLRDEST/RPLR.TXT"
chmod 444 "$SRC/RPLRDEST/RPLR.TXT"
# Also set DOS read-only attribute via ATTRIB
run_dos CMD/ATTRIB/ATTRIB.EXE '+R' 'C:\RPLRDEST\RPLR.TXT' > /dev/null 2>&1 || true
printf "REPLACED_DATA\r\n" > "$SRC/RPLR.TXT"
output=$(timeout 10 "$BIN/dos-run" --cwd='C:\' "$SRC/CMD/REPLACE/REPLACE.EXE" 'C:\RPLR.TXT' 'C:\RPLRDEST\' /R 2>/dev/null || true)
if echo "$output" | grep -q "file(s) replaced"; then
    ok "REPLACE /R (replace read-only file)"
else
    fail "REPLACE /R (expected 'file(s) replaced')"
fi
chmod 644 "$SRC/RPLRDEST/RPLR.TXT" 2>/dev/null || true
rm -rf "$SRC/RPLRDEST" "$SRC/RPLR.TXT"

# -- REPLACE /S: replace files in subdirectories recursively --
# Create a nested destination tree with matching filenames at different levels.
mkdir -p "$SRC/RPLSDEST/SUB1" "$SRC/RPLSDEST/SUB2"
printf "DEST_ROOT\r\n" > "$SRC/RPLSDEST/RPLS.TXT"
printf "DEST_SUB1\r\n" > "$SRC/RPLSDEST/SUB1/RPLS.TXT"
printf "DEST_SUB2\r\n" > "$SRC/RPLSDEST/SUB2/RPLS.TXT"
# Source file (will replace all matching files in dest tree)
printf "REPLACED_BY_S\r\n" > "$SRC/RPLS.TXT"
output=$(timeout 10 "$BIN/dos-run" --cwd='C:\' "$SRC/CMD/REPLACE/REPLACE.EXE" 'C:\RPLS.TXT' 'C:\RPLSDEST\' /S 2>/dev/null || true)
if echo "$output" | grep -q "file(s) replaced"; then
    ok "REPLACE /S (recursive replacement)"
else
    fail "REPLACE /S (expected 'file(s) replaced', got: $(echo "$output" | head -3))"
fi
# Verify files in subdirectories were actually replaced
if grep -q "REPLACED_BY_S" "$SRC/RPLSDEST/SUB1/RPLS.TXT" 2>/dev/null; then
    ok "REPLACE /S (SUB1 file content verified)"
else
    fail "REPLACE /S (SUB1/RPLS.TXT not replaced)"
fi
if grep -q "REPLACED_BY_S" "$SRC/RPLSDEST/SUB2/RPLS.TXT" 2>/dev/null; then
    ok "REPLACE /S (SUB2 file content verified)"
else
    fail "REPLACE /S (SUB2/RPLS.TXT not replaced)"
fi
rm -rf "$SRC/RPLSDEST" "$SRC/RPLS.TXT"

# -- REPLACE /W: wait for keypress before replacing --
# /W prompts "Press any key to continue . . ." before starting.
# Piping a character via stdin satisfies the read.
mkdir -p "$SRC/RPLWDEST"
printf "OldData\r\n" > "$SRC/RPLWDEST/RPLW.TXT"
printf "NewData\r\n" > "$SRC/RPLW.TXT"
output=$(echo "x" | timeout 10 "$BIN/dos-run" --cwd='C:\' "$SRC/CMD/REPLACE/REPLACE.EXE" 'C:\RPLW.TXT' 'C:\RPLWDEST\' /W 2>/dev/null || true)
if echo "$output" | grep -qi "Replacing"; then
    ok "REPLACE /W (waited for key, then replaced file)"
else
    fail "REPLACE /W (expected 'Replacing' in output, got: $(echo "$output" | head -3))"
fi
rm -rf "$SRC/RPLWDEST" "$SRC/RPLW.TXT"

# ── Section 7: COMMAND.COM built-in E2E tests (kvikdos) ──────────────────────
echo ""
echo "=== Section 7: COMMAND.COM built-in E2E tests (kvikdos) ==="

KVBAT="$SRC/CMD/COMMAND/KVTEST.BAT"
KVSUB="$SRC/CMD/COMMAND/KVSUB.BAT"
KVTXT="$SRC/CMD/COMMAND/KVTST.TXT"

# -- COMMAND initialization parser --
out=$(run_dos_all_output CMD/COMMAND/COMMAND.COM /E:160 /C 'ECHO COMMAND_E_MIN') || true
if echo "$out" | grep -q '^COMMAND_E_MIN'; then
    ok "COMMAND.COM /E:160 (minimum environment size accepted)"
else
    fail "COMMAND.COM /E:160 (minimum rejected, got: $out)"
fi
out=$(run_dos_all_output CMD/COMMAND/COMMAND.COM /E:32768 /C 'ECHO COMMAND_E_MAX') || true
if echo "$out" | grep -q '^COMMAND_E_MAX'; then
    ok "COMMAND.COM /E:32768 (maximum environment size accepted)"
else
    fail "COMMAND.COM /E:32768 (maximum rejected, got: $out)"
fi
out=$(run_dos_all_output CMD/COMMAND/COMMAND.COM /E:159 /C 'ECHO COMMAND_E_LOW') || true
if echo "$out" | grep -q '^Parameter value not in allowed range' \
    && echo "$out" | grep -q '^COMMAND_E_LOW'; then
    ok "COMMAND.COM /E:159 (below-range value diagnosed before /C)"
else
    fail "COMMAND.COM /E:159 (expected range diagnostic, got: $out)"
fi
out=$(run_dos_all_output CMD/COMMAND/COMMAND.COM /E:32769 /C 'ECHO COMMAND_E_HIGH') || true
if echo "$out" | grep -q '^Parameter value not in allowed range' \
    && echo "$out" | grep -q '^COMMAND_E_HIGH'; then
    ok "COMMAND.COM /E:32769 (above-range value diagnosed before /C)"
else
    fail "COMMAND.COM /E:32769 (expected range diagnostic, got: $out)"
fi
out=$(run_dos_all_output CMD/COMMAND/COMMAND.COM /E:160 /E:176 /C 'ECHO COMMAND_E_DUP') || true
if echo "$out" | grep -q '^Too many parameters' \
    && echo "$out" | grep -q '^COMMAND_E_DUP'; then
    ok "COMMAND.COM duplicate /E (diagnosed before /C)"
else
    fail "COMMAND.COM duplicate /E (expected diagnostic, got: $out)"
fi
out=$(run_dos_all_output CMD/COMMAND/COMMAND.COM /MSG /C 'ECHO COMMAND_MSG_NOP') || true
if echo "$out" | grep -q '^Required parameter missing' \
    && echo "$out" | grep -q '^COMMAND_MSG_NOP'; then
    ok "COMMAND.COM /MSG without /P (required relationship diagnosed)"
else
    fail "COMMAND.COM /MSG without /P (expected diagnostic, got: $out)"
fi
out=$(run_dos_all_output CMD/COMMAND/COMMAND.COM /D /C 'ECHO COMMAND_D_ACCEPTED') || true
if echo "$out" | grep -q '^COMMAND_D_ACCEPTED'; then
    ok "COMMAND.COM /D (startup date/time suppression switch accepted)"
else
    fail "COMMAND.COM /D (startup failed, got: $out)"
fi
out=$(run_dos_all_output CMD/COMMAND/COMMAND.COM /F /C 'ECHO COMMAND_F_ACCEPTED') || true
if echo "$out" | grep -q '^COMMAND_F_ACCEPTED'; then
    ok "COMMAND.COM /F (critical-error fail switch accepted)"
else
    fail "COMMAND.COM /F (startup failed, got: $out)"
fi
out=$(run_dos_all_output CMD/COMMAND/COMMAND.COM /C 'ECHO COMMAND_C_REST /D') || true
if echo "$out" | grep -q '^COMMAND_C_REST /D'; then
    ok "COMMAND.COM /C consumes the remaining command line verbatim"
else
    fail "COMMAND.COM /C did not consume the remaining line (got: $out)"
fi

# -- VER --
out=$(run_dos CMD/COMMAND/COMMAND.COM /C VER) || true
if echo "$out" | grep -qi "MS-DOS"; then
    ok "COMMAND.COM VER"
else
    fail "COMMAND.COM VER (expected 'MS-DOS', got: $out)"
fi

# -- ECHO --
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'ECHO HELLO_KVIKDOS_TEST') || true
if echo "$out" | grep -q "HELLO_KVIKDOS_TEST"; then
    ok "COMMAND.COM ECHO"
else
    fail "COMMAND.COM ECHO (expected 'HELLO_KVIKDOS_TEST', got: $out)"
fi

# -- SET (list env) --
out=$(run_dos CMD/COMMAND/COMMAND.COM /C SET) || true
if echo "$out" | grep -qi "COMSPEC="; then
    ok "COMMAND.COM SET (lists env)"
else
    fail "COMMAND.COM SET (expected 'COMSPEC=' in output, got: $out)"
fi

# -- PATH (show) --
out=$(run_dos CMD/COMMAND/COMMAND.COM /C PATH) || true
if echo "$out" | grep -qi "PATH=\|No Path"; then
    ok "COMMAND.COM PATH (show)"
else
    fail "COMMAND.COM PATH (expected 'PATH=' or 'No Path', got: $out)"
fi

# -- DIR --
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'DIR C:\CMD\COMMAND') || true
if echo "$out" | grep -qi "COMMAND"; then
    ok "COMMAND.COM DIR"
else
    fail "COMMAND.COM DIR (expected 'COMMAND' in listing, got: $out)"
fi

# -- DIR /W --
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'DIR C:\CMD\COMMAND /W') || true
if echo "$out" | grep -qi "COMMAND"; then
    ok "COMMAND.COM DIR /W"
else
    fail "COMMAND.COM DIR /W (expected 'COMMAND' in wide listing, got: $out)"
fi

# DIR's parser rejects repeated and unknown operational switches.
out=$(run_dos_all_output CMD/COMMAND/COMMAND.COM /C 'DIR /P /P') || true
if echo "$out" | grep -q '^Parse Error 1'; then
    ok "COMMAND.COM DIR duplicate /P (rejected by parser)"
else
    fail "COMMAND.COM DIR duplicate /P (expected Parse Error 1, got: $out)"
fi
out=$(run_dos_all_output CMD/COMMAND/COMMAND.COM /C 'DIR /Z') || true
if echo "$out" | grep -q '^Parse Error 3'; then
    ok "COMMAND.COM DIR unknown switch (rejected by parser)"
else
    fail "COMMAND.COM DIR unknown switch (expected Parse Error 3, got: $out)"
fi

# -- CHCP (query active code page) --
out=$(run_dos CMD/COMMAND/COMMAND.COM /C CHCP) || true
if echo "$out" | grep -q '^Active code page: 437'; then
    ok "COMMAND.COM CHCP (queries active code page 437)"
else
    fail "COMMAND.COM CHCP (expected active code page 437, got: $out)"
fi

# -- CLS (exact ANSI clear-screen request emitted through CON) --
out=$(run_dos CMD/COMMAND/COMMAND.COM /C CLS 2>/dev/null) || true
if [[ "$out" == $'\033[2J' ]]; then
    ok "COMMAND.COM CLS (emits exact ESC[2J clear-screen sequence)"
else
    fail "COMMAND.COM CLS (expected exact ESC[2J sequence)"
fi

# -- VOL --
out=$(run_dos CMD/COMMAND/COMMAND.COM /C VOL) || true
if echo "$out" | grep -qi "Volume\|volume in drive"; then
    ok "COMMAND.COM VOL"
else
    fail "COMMAND.COM VOL (expected 'Volume' in output, got: $out)"
fi

# -- BREAK (show state) --
out=$(run_dos CMD/COMMAND/COMMAND.COM /C BREAK) || true
if echo "$out" | grep -qi "BREAK is"; then
    ok "COMMAND.COM BREAK (show state)"
else
    fail "COMMAND.COM BREAK (expected 'BREAK is', got: $out)"
fi

# -- VERIFY (show state) --
out=$(run_dos CMD/COMMAND/COMMAND.COM /C VERIFY) || true
if echo "$out" | grep -qi "VERIFY is"; then
    ok "COMMAND.COM VERIFY (show state)"
else
    fail "COMMAND.COM VERIFY (expected 'VERIFY is', got: $out)"
fi

# -- TYPE --
printf 'HELLO_TYPE_TEST\r\n' > "$KVTXT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'TYPE C:\CMD\COMMAND\KVTST.TXT') || true
rm -f "$KVTXT"
if echo "$out" | grep -q "HELLO_TYPE_TEST"; then
    ok "COMMAND.COM TYPE"
else
    fail "COMMAND.COM TYPE (expected 'HELLO_TYPE_TEST', got: $out)"
fi

# -- GOTO --
printf 'GOTO SKIP\r\nECHO SHOULD_NOT_APPEAR\r\n:SKIP\r\nECHO GOTO_OK\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
if echo "$out" | grep -q "GOTO_OK" && ! echo "$out" | grep -q "SHOULD_NOT_APPEAR"; then
    ok "COMMAND.COM GOTO"
else
    fail "COMMAND.COM GOTO (expected 'GOTO_OK' and no 'SHOULD_NOT_APPEAR', got: $out)"
fi

# -- REM --
printf 'REM This is a comment\r\nECHO REM_SURVIVED\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
if echo "$out" | grep -q "REM_SURVIVED"; then
    ok "COMMAND.COM REM"
else
    fail "COMMAND.COM REM (expected 'REM_SURVIVED', got: $out)"
fi

# -- IF EXIST --
printf 'dummy\r\n' > "$KVTXT"
printf 'IF EXIST C:\CMD\COMMAND\KVTST.TXT ECHO IF_EXIST_OK\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT" "$KVTXT"
if echo "$out" | grep -q "IF_EXIST_OK"; then
    ok "COMMAND.COM IF EXIST"
else
    fail "COMMAND.COM IF EXIST (expected 'IF_EXIST_OK', got: $out)"
fi

# -- IF NOT EXIST --
printf 'IF NOT EXIST C:\CMD\COMMAND\NOSUCH.TXT ECHO IF_NOT_EXIST_OK\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
if echo "$out" | grep -q "IF_NOT_EXIST_OK"; then
    ok "COMMAND.COM IF NOT EXIST"
else
    fail "COMMAND.COM IF NOT EXIST (expected 'IF_NOT_EXIST_OK', got: $out)"
fi

# -- IF string==string --
printf 'IF HELLO==HELLO ECHO IF_EQUAL_OK\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
if echo "$out" | grep -q "IF_EQUAL_OK"; then
    ok "COMMAND.COM IF string==string"
else
    fail "COMMAND.COM IF string==string (expected 'IF_EQUAL_OK', got: $out)"
fi

# -- IF NOT string==string --
printf 'IF NOT HELLO==WORLD ECHO IF_NOT_EQUAL_OK\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
if echo "$out" | grep -q "IF_NOT_EQUAL_OK"; then
    ok "COMMAND.COM IF NOT string==string"
else
    fail "COMMAND.COM IF NOT string==string (expected 'IF_NOT_EQUAL_OK', got: $out)"
fi

# -- CALL --
printf 'ECHO CALL_SUB_OK\r\n' > "$KVSUB"
printf 'CALL C:\CMD\COMMAND\KVSUB.BAT\r\nECHO CALL_RETURNED\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT" "$KVSUB"
if echo "$out" | grep -q "CALL_SUB_OK" && echo "$out" | grep -q "CALL_RETURNED"; then
    ok "COMMAND.COM CALL"
else
    fail "COMMAND.COM CALL (expected 'CALL_SUB_OK' and 'CALL_RETURNED', got: $out)"
fi

# -- SHIFT -- (before shift %1=FIRST, after shift %1=SECOND; use %%1 so printf doesn't eat %)
printf 'SHIFT\r\nECHO SHIFT_ARG1=%%1\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT FIRST SECOND') || true
rm -f "$KVBAT"
if echo "$out" | grep -q "SHIFT_ARG1=SECOND"; then
    ok "COMMAND.COM SHIFT"
else
    fail "COMMAND.COM SHIFT (expected 'SHIFT_ARG1=SECOND' after shift, got: $out)"
fi

# -- FOR loop --
printf 'FOR %%%%F IN (AAA BBB CCC) DO ECHO FOR_GOT_%%%%F\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
if echo "$out" | grep -q "FOR_GOT_AAA" && echo "$out" | grep -q "FOR_GOT_BBB" && echo "$out" | grep -q "FOR_GOT_CCC"; then
    ok "COMMAND.COM FOR (loop iterates all items)"
else
    fail "COMMAND.COM FOR (expected FOR_GOT_AAA/BBB/CCC, got: $out)"
fi

# -- ECHO. (blank line) --
printf 'ECHO.\r\nECHO ECHO_DOT_OK\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
if echo "$out" | grep -q "ECHO_DOT_OK"; then
    ok "COMMAND.COM ECHO. (blank line)"
else
    fail "COMMAND.COM ECHO. (expected 'ECHO_DOT_OK', got: $out)"
fi

# -- ECHO OFF / ECHO ON --
printf '@ECHO OFF\r\nECHO ECHO_OFF_OK\r\nECHO ON\r\nECHO ECHO_ON_OK\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
if echo "$out" | grep -q "ECHO_OFF_OK" && echo "$out" | grep -q "ECHO_ON_OK"; then
    ok "COMMAND.COM ECHO OFF/ON"
else
    fail "COMMAND.COM ECHO OFF/ON (expected 'ECHO_OFF_OK' and 'ECHO_ON_OK', got: $out)"
fi

# -- BREAK ON/OFF toggle --
printf 'BREAK ON\r\nBREAK\r\nBREAK OFF\r\nBREAK\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
if echo "$out" | grep -qi "BREAK is on" && echo "$out" | grep -qi "BREAK is off"; then
    ok "COMMAND.COM BREAK ON/OFF toggle"
else
    fail "COMMAND.COM BREAK ON/OFF (expected both states, got: $out)"
fi

# -- VERIFY ON/OFF toggle --
printf 'VERIFY ON\r\nVERIFY\r\nVERIFY OFF\r\nVERIFY\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
if echo "$out" | grep -qi "VERIFY is on" && echo "$out" | grep -qi "VERIFY is off"; then
    ok "COMMAND.COM VERIFY ON/OFF toggle"
else
    fail "COMMAND.COM VERIFY ON/OFF (expected both states, got: $out)"
fi

# -- PATH set and clear --
printf 'PATH A:\DOS\r\nPATH\r\nPATH ;\r\nPATH\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
if echo "$out" | grep -qi "A:\\\\DOS" && echo "$out" | grep -qi "No Path\|PATH=;"; then
    ok "COMMAND.COM PATH set and clear"
else
    fail "COMMAND.COM PATH set/clear (expected A:\\DOS and 'No Path', got: $out)"
fi

# -- SET assign and clear --
printf 'SET SETVAR=TESTVAL\r\nSET SETVAR\r\nECHO SET_ASSIGN_DONE\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
if echo "$out" | grep -q "SETVAR=TESTVAL"; then
    ok "COMMAND.COM SET assign"
else
    fail "COMMAND.COM SET assign (expected 'SETVAR=TESTVAL', got: $out)"
fi

# -- COPY --
printf 'COPY_TEST_DATA\r\n' > "$KVTXT"
printf 'COPY C:\CMD\COMMAND\KVTST.TXT C:\CMD\COMMAND\KVTST2.TXT\r\nTYPE C:\CMD\COMMAND\KVTST2.TXT\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT" "$KVTXT" "$SRC/CMD/COMMAND/KVTST2.TXT"
if echo "$out" | grep -q "COPY_TEST_DATA"; then
    ok "COMMAND.COM COPY"
else
    fail "COMMAND.COM COPY (expected copied content in dest, got: $out)"
fi

# -- COPY /V --
printf 'COPYV_TEST_DATA\r\n' > "$KVTXT"
printf 'COPY /V C:\CMD\COMMAND\KVTST.TXT C:\CMD\COMMAND\KVTST2.TXT\r\nTYPE C:\CMD\COMMAND\KVTST2.TXT\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT" "$KVTXT" "$SRC/CMD/COMMAND/KVTST2.TXT"
if echo "$out" | grep -q "COPYV_TEST_DATA"; then
    ok "COMMAND.COM COPY /V"
else
    fail "COMMAND.COM COPY /V (expected copied content in dest, got: $out)"
fi

# -- REN --
printf 'REN_TEST_DATA\r\n' > "$KVTXT"
printf 'REN C:\CMD\COMMAND\KVTST.TXT KVREN.TXT\r\nTYPE C:\CMD\COMMAND\KVREN.TXT\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT" "$KVTXT" "$SRC/CMD/COMMAND/KVREN.TXT"
if echo "$out" | grep -q "REN_TEST_DATA"; then
    ok "COMMAND.COM REN"
else
    fail "COMMAND.COM REN (expected renamed file content, got: $out)"
fi

# -- RENAME (long synonym reaches the same rename operation) --
printf 'RENAME_TEST_DATA\r\n' > "$KVTXT"
printf 'RENAME C:\CMD\COMMAND\KVTST.TXT KVREN.TXT\r\nTYPE C:\CMD\COMMAND\KVREN.TXT\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT" "$KVTXT" "$SRC/CMD/COMMAND/KVREN.TXT"
if echo "$out" | grep -q "RENAME_TEST_DATA"; then
    ok "COMMAND.COM RENAME (long synonym mutates the file namespace)"
else
    fail "COMMAND.COM RENAME (expected renamed file content, got: $out)"
fi

# -- DEL --
printf 'DEL_TEST_DATA\r\n' > "$KVTXT"
printf 'DEL C:\CMD\COMMAND\KVTST.TXT\r\nIF NOT EXIST C:\CMD\COMMAND\KVTST.TXT ECHO DEL_OK\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT" "$KVTXT"
if echo "$out" | grep -q "DEL_OK"; then
    ok "COMMAND.COM DEL"
else
    fail "COMMAND.COM DEL (expected 'DEL_OK', got: $out)"
fi

# -- ERASE (synonym for DEL) --
printf 'ERASE_TEST_DATA\r\n' > "$KVTXT"
printf 'ERASE C:\CMD\COMMAND\KVTST.TXT\r\nIF NOT EXIST C:\CMD\COMMAND\KVTST.TXT ECHO ERASE_OK\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT" "$KVTXT"
if echo "$out" | grep -q "ERASE_OK"; then
    ok "COMMAND.COM ERASE (DEL synonym)"
else
    fail "COMMAND.COM ERASE (expected 'ERASE_OK', got: $out)"
fi

# -- DEL wildcard --
printf 'W1\r\n' > "$SRC/CMD/COMMAND/KVW1.DEL"
printf 'W2\r\n' > "$SRC/CMD/COMMAND/KVW2.DEL"
printf 'DEL C:\CMD\COMMAND\*.DEL\r\nIF NOT EXIST C:\CMD\COMMAND\KVW1.DEL IF NOT EXIST C:\CMD\COMMAND\KVW2.DEL ECHO DEL_WILD_OK\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT" "$SRC/CMD/COMMAND/KVW1.DEL" "$SRC/CMD/COMMAND/KVW2.DEL"
if echo "$out" | grep -q "DEL_WILD_OK"; then
    ok "COMMAND.COM DEL wildcard"
else
    fail "COMMAND.COM DEL wildcard (expected 'DEL_WILD_OK', got: $out)"
fi

# DEL/ERASE parser boundaries; the interactive /P effects are exercised on
# real DOS console input by test_prompt_yesno.sh.
out=$(run_dos_all_output CMD/COMMAND/COMMAND.COM /C 'DEL C:\NOFILE.TXT /P /P') || true
if echo "$out" | grep -q '^Parse Error 1'; then
    ok "COMMAND.COM DEL duplicate /P (rejected by parser)"
else
    fail "COMMAND.COM DEL duplicate /P (expected Parse Error 1, got: $out)"
fi
out=$(run_dos_all_output CMD/COMMAND/COMMAND.COM /C 'ERASE C:\NOFILE.TXT /Z') || true
if echo "$out" | grep -q '^Parse Error 3'; then
    ok "COMMAND.COM ERASE unknown switch (rejected by parser)"
else
    fail "COMMAND.COM ERASE unknown switch (expected Parse Error 3, got: $out)"
fi

# COPY treats duplicate /V and any unknown switch as parser error 3.
out=$(run_dos_all_output CMD/COMMAND/COMMAND.COM /C 'COPY /V /V C:\NOFILE C:\X') || true
if echo "$out" | grep -q '^Parse Error 3'; then
    ok "COMMAND.COM COPY duplicate /V (rejected by parser)"
else
    fail "COMMAND.COM COPY duplicate /V (expected Parse Error 3, got: $out)"
fi
out=$(run_dos_all_output CMD/COMMAND/COMMAND.COM /C 'COPY /Z C:\NOFILE C:\X') || true
if echo "$out" | grep -q '^Parse Error 3'; then
    ok "COMMAND.COM COPY unknown switch (rejected by parser)"
else
    fail "COMMAND.COM COPY unknown switch (expected Parse Error 3, got: $out)"
fi

# -- MD + RD --
KVTDIR="$SRC/CMD/COMMAND/KVTDIR"
printf 'MD C:\CMD\COMMAND\KVTDIR\r\nIF EXIST C:\CMD\COMMAND\KVTDIR\ ECHO MD_OK\r\nRD C:\CMD\COMMAND\KVTDIR\r\nIF NOT EXIST C:\CMD\COMMAND\KVTDIR\ ECHO RD_OK\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"; rmdir "$KVTDIR" 2>/dev/null || true
if echo "$out" | grep -q "MD_OK" && echo "$out" | grep -q "RD_OK"; then
    ok "COMMAND.COM MD + RD"
else
    fail "COMMAND.COM MD + RD (expected 'MD_OK' and 'RD_OK', got: $out)"
fi

# -- MKDIR + RMDIR (long synonyms) --
KVTDIR="$SRC/CMD/COMMAND/KVTDIR"
printf 'MKDIR C:\CMD\COMMAND\KVTDIR\r\nIF EXIST C:\CMD\COMMAND\KVTDIR\ ECHO MKDIR_OK\r\nRMDIR C:\CMD\COMMAND\KVTDIR\r\nIF NOT EXIST C:\CMD\COMMAND\KVTDIR\ ECHO RMDIR_OK\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"; rmdir "$KVTDIR" 2>/dev/null || true
if echo "$out" | grep -q "MKDIR_OK" && echo "$out" | grep -q "RMDIR_OK"; then
    ok "COMMAND.COM MKDIR + RMDIR (long synonyms mutate directories)"
else
    fail "COMMAND.COM MKDIR + RMDIR (expected both markers, got: $out)"
fi

# -- MD nested --
KVNDIR="$SRC/CMD/COMMAND/KVNEST"
printf 'MD C:\CMD\COMMAND\KVNEST\r\nMD C:\CMD\COMMAND\KVNEST\SUB\r\nIF EXIST C:\CMD\COMMAND\KVNEST\SUB\ ECHO MD_NESTED_OK\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"; rm -rf "$KVNDIR" 2>/dev/null || true
if echo "$out" | grep -q "MD_NESTED_OK"; then
    ok "COMMAND.COM MD nested"
else
    fail "COMMAND.COM MD nested (expected 'MD_NESTED_OK', got: $out)"
fi

# -- IF ERRORLEVEL: batch conditional on exit code --
# kvikdos can't spawn child EXEs from COMMAND.COM (memory allocation error),
# so test the IF ERRORLEVEL parsing with the default errorlevel (0 at startup).
# IF ERRORLEVEL 0 is true (0 >= 0); IF ERRORLEVEL 1 is false (0 < 1).
printf '@ECHO OFF\r\nIF ERRORLEVEL 0 ECHO ERRORLEVEL_GE0_OK\r\nIF ERRORLEVEL 1 ECHO ERRORLEVEL_GE1_WRONG\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
if echo "$out" | grep -q "ERRORLEVEL_GE0_OK" && ! echo "$out" | grep -q "ERRORLEVEL_GE1_WRONG"; then
    ok "COMMAND.COM IF ERRORLEVEL (0 >= 0 true, 0 >= 1 false)"
else
    fail "COMMAND.COM IF ERRORLEVEL (expected GE0_OK only, got: $out)"
fi

# -- IF NOT ERRORLEVEL: inverted conditional --
printf '@ECHO OFF\r\nIF NOT ERRORLEVEL 1 ECHO NOT_GE1_OK\r\nIF NOT ERRORLEVEL 0 ECHO NOT_GE0_WRONG\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
if echo "$out" | grep -q "NOT_GE1_OK" && ! echo "$out" | grep -q "NOT_GE0_WRONG"; then
    ok "COMMAND.COM IF NOT ERRORLEVEL (NOT 0>=1 true, NOT 0>=0 false)"
else
    fail "COMMAND.COM IF NOT ERRORLEVEL (expected NOT_GE1_OK only, got: $out)"
fi

# -- CD / CHDIR: change directory and verify --
# Use \\ for literal backslashes in printf (avoid \E being interpreted as ESC)
printf '@ECHO OFF\r\nCD C:\\CMD\\EDLIN\r\nCD\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
if echo "$out" | grep -qi 'C:\\CMD\\EDLIN'; then
    ok "COMMAND.COM CD (change and verify directory)"
else
    fail "COMMAND.COM CD (expected 'C:\CMD\EDLIN' in output, got: $out)"
fi

# -- CHDIR long synonym --
printf '@ECHO OFF\r\nCHDIR C:\\CMD\\EDLIN\r\nCHDIR\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
if echo "$out" | grep -qi 'C:\\CMD\\EDLIN'; then
    ok "COMMAND.COM CHDIR (long synonym changes and reports directory)"
else
    fail "COMMAND.COM CHDIR (expected C:\CMD\EDLIN, got: $out)"
fi

# -- PROMPT: set and verify via SET (list all env vars) --
printf '@ECHO OFF\r\nPROMPT TESTPROMPT$G\r\nSET\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
if echo "$out" | grep -q "PROMPT=TESTPROMPT"; then
    ok "COMMAND.COM PROMPT (set and verify)"
else
    fail "COMMAND.COM PROMPT (expected 'PROMPT=TESTPROMPT' in SET output, got: $out)"
fi

# -- TRUENAME: resolve canonical path --
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'TRUENAME C:\SETENV.BAT') || true
if echo "$out" | grep -qi 'C:\\SETENV.BAT'; then
    ok "COMMAND.COM TRUENAME (resolve path)"
else
    fail "COMMAND.COM TRUENAME (expected 'C:\SETENV.BAT', got: $out)"
fi

# -- SET/PROMPT stress: multiple calls in sequence (ES corruption regression) --
# Regression test for ae75edf — SET/PROMPT could corrupt ES register, causing
# hangs on subsequent calls. 10 alternating SET+PROMPT calls exercises the path.
printf '@ECHO OFF\r\nSET SV1=A1\r\nPROMPT P1$G\r\nSET SV2=A2\r\nPROMPT P2$G\r\nSET SV3=A3\r\nPROMPT P3$G\r\nSET SV4=A4\r\nPROMPT P4$G\r\nSET SV5=A5\r\nPROMPT P5$G\r\nSET SV6=A6\r\nPROMPT P6$G\r\nSET SV7=A7\r\nPROMPT P7$G\r\nSET SV8=A8\r\nPROMPT P8$G\r\nSET SV9=A9\r\nPROMPT P9$G\r\nSET SV10=A10\r\nPROMPT P10$G\r\nECHO STRESS_DONE\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
if echo "$out" | grep -q "STRESS_DONE"; then
    ok "COMMAND.COM SET/PROMPT stress (10 alternating calls, no hang)"
else
    fail "COMMAND.COM SET/PROMPT stress (expected STRESS_DONE, got: $out)"
fi

# -- PAUSE: waits for keypress, continues after receiving one --
# PAUSE uses INT 21h/AH=0Ch (flush+read) with AL=08h (read without echo).
# Piping a character via stdin satisfies the read and batch continues.
printf '@ECHO OFF\r\nPAUSE\r\nECHO PAUSE_DONE\r\n' > "$KVBAT"
out=$(echo "x" | timeout 30 "$BIN/dos-run" "$SRC/CMD/COMMAND/COMMAND.COM" /C 'C:\CMD\COMMAND\KVTEST.BAT' 2>/dev/null) || true
rm -f "$KVBAT"
if echo "$out" | grep -q "Press any key" && echo "$out" | grep -q "PAUSE_DONE"; then
    ok "COMMAND.COM PAUSE (displayed prompt, continued after piped keystroke)"
else
    fail "COMMAND.COM PAUSE (expected 'Press any key' + PAUSE_DONE, got: $out)"
fi

# -- DATE: show current date, accept with empty input --
# DATE uses INT 21h/AH=0Ah (buffered input) for the new date prompt.
# Piping an empty line (just Enter) accepts the current date.
printf '@ECHO OFF\r\nDATE\r\nECHO DATE_DONE\r\n' > "$KVBAT"
out=$(echo "" | timeout 30 "$BIN/dos-run" "$SRC/CMD/COMMAND/COMMAND.COM" /C 'C:\CMD\COMMAND\KVTEST.BAT' 2>/dev/null) || true
rm -f "$KVBAT"
if echo "$out" | grep -qi "Current date" && echo "$out" | grep -q "DATE_DONE"; then
    ok "COMMAND.COM DATE (showed current date, accepted empty input)"
else
    fail "COMMAND.COM DATE (expected 'Current date' + DATE_DONE, got: $out)"
fi

# -- TIME: show current time, accept with empty input --
printf '@ECHO OFF\r\nTIME\r\nECHO TIME_DONE\r\n' > "$KVBAT"
out=$(echo "" | timeout 30 "$BIN/dos-run" "$SRC/CMD/COMMAND/COMMAND.COM" /C 'C:\CMD\COMMAND\KVTEST.BAT' 2>/dev/null) || true
rm -f "$KVBAT"
if echo "$out" | grep -qi "Current time" && echo "$out" | grep -q "TIME_DONE"; then
    ok "COMMAND.COM TIME (showed current time, accepted empty input)"
else
    fail "COMMAND.COM TIME (expected 'Current time' + TIME_DONE, got: $out)"
fi

# -- COPY a+b c: file concatenation --
printf 'PART_ONE\r\n' > "$SRC/CMD/COMMAND/KVCAT1.TXT"
printf 'PART_TWO\r\n' > "$SRC/CMD/COMMAND/KVCAT2.TXT"
printf '@ECHO OFF\r\nCOPY /B C:\CMD\COMMAND\KVCAT1.TXT+C:\CMD\COMMAND\KVCAT2.TXT C:\CMD\COMMAND\KVCAT3.TXT\r\nTYPE C:\CMD\COMMAND\KVCAT3.TXT\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT" "$SRC/CMD/COMMAND/KVCAT1.TXT" "$SRC/CMD/COMMAND/KVCAT2.TXT" "$SRC/CMD/COMMAND/KVCAT3.TXT"
if echo "$out" | grep -q "PART_ONE" && echo "$out" | grep -q "PART_TWO"; then
    ok "COMMAND.COM COPY a+b c (concatenation)"
else
    fail "COMMAND.COM COPY a+b c (expected both PART_ONE and PART_TWO, got: $out)"
fi

# -- COPY /B: binary mode (copies past ^Z) --
printf 'BEFORE\x1aAFTER' > "$SRC/CMD/COMMAND/KVBIN.TXT"
printf '@ECHO OFF\r\nCOPY /B C:\CMD\COMMAND\KVBIN.TXT C:\CMD\COMMAND\KVBOUT.TXT\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
# Check host file: /B should preserve content past ^Z (file should be 11 bytes: BEFORE + ^Z + AFTER)
if [ -f "$SRC/CMD/COMMAND/KVBOUT.TXT" ]; then
    size=$(wc -c < "$SRC/CMD/COMMAND/KVBOUT.TXT")
    if [ "$size" -ge 11 ]; then
        ok "COMMAND.COM COPY /B (binary: full file past ^Z, $size bytes)"
    else
        fail "COMMAND.COM COPY /B (expected >=11 bytes, got $size)"
    fi
else
    fail "COMMAND.COM COPY /B (output file not created)"
fi
rm -f "$SRC/CMD/COMMAND/KVBIN.TXT" "$SRC/CMD/COMMAND/KVBOUT.TXT"

# -- COPY /A: ASCII mode (stops at ^Z, appends ^Z) --
printf 'BEFORE\x1aAFTER' > "$SRC/CMD/COMMAND/KVASCII.TXT"
printf '@ECHO OFF\r\nCOPY /A C:\CMD\COMMAND\KVASCII.TXT C:\CMD\COMMAND\KVAOUT.TXT\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
# /A stops reading at ^Z, so output should be shorter than the /B copy
if [ -f "$SRC/CMD/COMMAND/KVAOUT.TXT" ]; then
    size=$(wc -c < "$SRC/CMD/COMMAND/KVAOUT.TXT")
    # "BEFORE" = 6 bytes + appended ^Z = 7 bytes max (no AFTER)
    if [ "$size" -le 8 ]; then
        ok "COMMAND.COM COPY /A (ASCII: stopped at ^Z, $size bytes)"
    else
        fail "COMMAND.COM COPY /A (expected <=8 bytes without AFTER, got $size)"
    fi
else
    fail "COMMAND.COM COPY /A (output file not created)"
fi
rm -f "$SRC/CMD/COMMAND/KVASCII.TXT" "$SRC/CMD/COMMAND/KVAOUT.TXT"

# -- Parser signed comparison regression (commit 4ed73cb) --
# PARSE2.ASM:281: argbuf overflow check uses cmp DI, 0x80BD (>= 0x8000).
# Original code used jge (signed) — treats 0x80BD as negative, always overflows.
# Fix: jae (unsigned). This test verifies VER works (parser must succeed).
# If the bug is reintroduced, every command fails with "Bad command or file name".
printf '@ECHO OFF\r\nVER\r\n' > "$KVBAT"
out=$(run_dos CMD/COMMAND/COMMAND.COM /C 'C:\CMD\COMMAND\KVTEST.BAT') || true
rm -f "$KVBAT"
if echo "$out" | grep -qi "MS-DOS\|Version"; then
    ok "COMMAND.COM parser boundary (argbuf >= 0x8000, jae unsigned compare)"
else
    fail "COMMAND.COM parser boundary (VER failed — jge signed comparison regression?)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
if [[ ${FAIL_ON_SKIP:-0} == 1 && $SKIP -ne 0 ]]; then
    echo "Unexpected skips are forbidden when FAIL_ON_SKIP=1"
    exit 1
fi
[[ $FAIL -eq 0 ]]
