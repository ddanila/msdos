#!/bin/bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"

BOOT_IMG="$OUT/asj-boot.img"
B_IMG="$OUT/asj-b.img"
SERIAL_LOG="$OUT/asj-serial.log"
EXIT_COM="$OUT/qemu-exit.com"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

trap 'rm -f "$B_IMG" 2>/dev/null; true' EXIT

echo "=== ASSIGN / SUBST / JOIN E2E tests (QEMU) ==="

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

echo "Building test images..."
cp "$FLOPPY" "$BOOT_IMG"
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM

printf 'LASTDRIVE=Z\r\n' | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS

dd if=/dev/zero bs=512 count=2880 of="$B_IMG" status=none
mformat -i "$B_IMG" -f 1440 ::
printf 'JOIN_B_FILE_CONTENT\r\n' | mcopy -o -i "$B_IMG" - ::BJOIN.TXT

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'

    printf 'ECHO ---ASSIGN---\r\n'
    printf 'ASSIGN B=A\r\n'
    printf 'ECHO ASSIGN_DONE\r\n'

    printf 'ASSIGN /STATUS\r\n'
    printf 'ECHO ---ASSIGN-STA---\r\n'
    printf 'ASSIGN /STA\r\n'
    printf 'ECHO ASSIGN_STA_DONE\r\n'
    printf 'ASSIGN /STATUS /STA\r\n'
    printf 'IF ERRORLEVEL 1 ECHO ASSIGN_DUP_STATUS_REJECTED\r\n'
    printf 'ASSIGN /Z\r\n'
    printf 'IF ERRORLEVEL 1 ECHO ASSIGN_UNKNOWN_REJECTED\r\n'
    printf 'ASSIGN B\r\n'
    printf 'IF ERRORLEVEL 1 ECHO ASSIGN_UNPAIRED_REJECTED\r\n'

    printf 'ECHO ---ASSIGN-DIR---\r\n'
    printf 'DIR B:\COMMAND.COM\r\n'
    printf 'IF EXIST B:\COMMAND.COM ECHO ASSIGN_STATE_PRESERVED\r\n'
    printf 'ECHO ASSIGN_DIR_DONE\r\n'

    printf 'ECHO ---ASSIGN-CLEAR---\r\n'
    printf 'ASSIGN\r\n'
    printf 'IF EXIST B:\BJOIN.TXT ECHO ASSIGN_CLEAR_RESTORED_B\r\n'
    printf 'ECHO ASSIGN_CLEAR_DONE\r\n'

    printf 'ECHO ---SUBST---\r\n'
    printf 'MD SUBSTDIR\r\n'
    printf 'SUBST E: A:\NO-SUCH-DIR\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SUBST_MISSING_PATH_REJECTED\r\n'
    printf 'SUBST E: A:\\\r\n'
    printf 'IF EXIST E:\COMMAND.COM ECHO SUBST_ROOT_ACCEPTED\r\n'
    printf 'SUBST E: /D\r\n'
    printf 'SUBST D: A:\SUBSTDIR\r\n'
    printf 'ECHO SUBST_CREATE_DONE\r\n'
    printf 'ECHO SUBST_STATE_PAYLOAD>D:\STATE.TXT\r\n'

    printf 'SUBST D: A:\SUBSTDIR\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SUBST_DUP_CREATE_REJECTED\r\n'
    printf 'SUBST D: /D /D\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SUBST_DUP_DELETE_REJECTED\r\n'
    printf 'SUBST /D\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SUBST_DELETE_NO_DRIVE_REJECTED\r\n'
    printf 'SUBST D:\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SUBST_DRIVE_ONLY_REJECTED\r\n'
    printf 'SUBST D: A:\SUBSTDIR /D\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SUBST_CREATE_DELETE_REJECTED\r\n'
    printf 'SUBST D: A:\SUBSTDIR EXTRA\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SUBST_EXCESS_REJECTED\r\n'
    printf 'SUBST D: /Z\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SUBST_UNKNOWN_REJECTED\r\n'
    printf 'IF EXIST D:\STATE.TXT ECHO SUBST_STATE_PRESERVED\r\n'

    printf 'ECHO ---SUBST-LIST---\r\n'
    printf 'SUBST\r\n'
    printf 'ECHO SUBST_LIST_DONE\r\n'

    printf 'ECHO ---SUBST-IO---\r\n'
    printf 'COPY A:\\COMMAND.COM D:\\TEST.COM\r\n'
    printf 'DIR D:\\\r\n'
    printf 'TYPE D:\\TEST.COM > NUL\r\n'
    printf 'IF EXIST D:\\TEST.COM ECHO SUBST_FILE_EXISTS\r\n'
    printf 'IF EXIST A:\\SUBSTDIR\\TEST.COM ECHO SUBST_PASSTHRU_OK\r\n'
    printf 'ECHO SUBST_IO_DONE\r\n'

    printf 'ECHO ---SUBST-DEL---\r\n'
    printf 'SUBST D: /D\r\n'
    printf 'ECHO SUBST_DEL_DONE\r\n'
    printf 'SUBST D: /D\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SUBST_INACTIVE_DELETE_REJECTED\r\n'

    printf 'ECHO ---JOIN---\r\n'
    printf 'MD JOINDIR\r\n'
    printf 'ECHO OCCUPIED>JOINDIR\OCCUPIED.TXT\r\n'
    printf 'JOIN B: A:\JOINDIR\r\n'
    printf 'IF ERRORLEVEL 1 ECHO JOIN_NONEMPTY_REJECTED\r\n'
    printf 'DEL JOINDIR\OCCUPIED.TXT\r\n'
    printf 'JOIN B: B:\SAME\r\n'
    printf 'IF ERRORLEVEL 1 ECHO JOIN_SAME_DRIVE_REJECTED\r\n'
    printf 'JOIN A: B:\CURDRV\r\n'
    printf 'IF ERRORLEVEL 1 ECHO JOIN_CURRENT_DRIVE_REJECTED\r\n'
    printf 'JOIN B: A:\JOINDIR\r\n'
    printf 'ECHO JOIN_CREATE_DONE\r\n'

    printf 'JOIN B: A:\JOINDIR\r\n'
    printf 'IF ERRORLEVEL 1 ECHO JOIN_DUP_CREATE_REJECTED\r\n'
    printf 'JOIN B: /D /D\r\n'
    printf 'IF ERRORLEVEL 1 ECHO JOIN_DUP_DELETE_REJECTED\r\n'
    printf 'JOIN /D\r\n'
    printf 'IF ERRORLEVEL 1 ECHO JOIN_DELETE_NO_DRIVE_REJECTED\r\n'
    printf 'JOIN B:\r\n'
    printf 'IF ERRORLEVEL 1 ECHO JOIN_DRIVE_ONLY_REJECTED\r\n'
    printf 'JOIN B: A:\JOINDIR /D\r\n'
    printf 'IF ERRORLEVEL 1 ECHO JOIN_CREATE_DELETE_REJECTED\r\n'
    printf 'JOIN B: A:\JOINDIR EXTRA\r\n'
    printf 'IF ERRORLEVEL 1 ECHO JOIN_EXCESS_REJECTED\r\n'
    printf 'JOIN B: /Z\r\n'
    printf 'IF ERRORLEVEL 1 ECHO JOIN_UNKNOWN_REJECTED\r\n'
    printf 'IF EXIST A:\JOINDIR\BJOIN.TXT ECHO JOIN_STATE_PRESERVED\r\n'

    printf 'ECHO ---JOIN-LIST---\r\n'
    printf 'JOIN\r\n'
    printf 'ECHO JOIN_LIST_DONE\r\n'

    printf 'ECHO ---JOIN-DIR---\r\n'
    printf 'DIR A:\JOINDIR\r\n'
    printf 'TYPE A:\JOINDIR\BJOIN.TXT\r\n'
    printf 'COPY A:\JOINDIR\BJOIN.TXT A:\BJOIN_COPY.TXT\r\n'
    printf 'IF EXIST A:\BJOIN_COPY.TXT ECHO JOIN_COPY_OK\r\n'
    printf 'ECHO JOIN_DIR_DONE\r\n'

    printf 'ECHO ---JOIN-DEL---\r\n'
    printf 'JOIN B: /D\r\n'
    printf 'ECHO JOIN_DEL_DONE\r\n'
    printf 'JOIN B: /D\r\n'
    printf 'IF ERRORLEVEL 1 ECHO JOIN_INACTIVE_DELETE_REJECTED\r\n'

    printf 'ECHO ===DONE===\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

echo "Booting QEMU (may take ~90s)..."
rm -f "$SERIAL_LOG"
(while true; do sleep 0.5; printf '\r\n'; done) | \
timeout 120 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$B_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null | tee "$SERIAL_LOG" > /dev/null; true

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi

echo ""
echo "--- ASSIGN tests ---"

if grep -q '^ASSIGN_DONE' "$SERIAL_LOG"; then
    ok "ASSIGN B=A (installed silently, batch continued)"
else
    fail "ASSIGN B=A (batch hung or crashed)"
fi

for marker in ASSIGN_DUP_STATUS_REJECTED ASSIGN_UNKNOWN_REJECTED \
              ASSIGN_UNPAIRED_REJECTED ASSIGN_STATE_PRESERVED; do
    if grep -q "^${marker}" "$SERIAL_LOG"; then
        ok "${marker//_/ }"
    else
        fail "${marker//_/ }"
    fi
done

if grep -qi '^Original B: set to A:' "$SERIAL_LOG"; then
    ok "ASSIGN /STATUS reports B: redirected to A:"
else
    fail "ASSIGN /STATUS did not report the active B:=A: mapping"
fi

assign_sta_section=$(sed -n '/---ASSIGN-STA---/,/ASSIGN_STA_DONE/p' "$SERIAL_LOG")
if echo "$assign_sta_section" | grep -qi '^Original B: set to A:'; then
    ok "ASSIGN /STA short synonym reports B: redirected to A:"
else
    fail "ASSIGN /STA did not report the active B:=A: mapping"
fi

if grep -q '^Invalid switch - /STA' "$SERIAL_LOG" \
    && grep -q '^Invalid switch -  /Z' "$SERIAL_LOG" \
    && grep -q '^Invalid parameter -  B' "$SERIAL_LOG"; then
    ok "ASSIGN parser diagnostics identify the rejected token"
else
    fail "ASSIGN parser diagnostics did not match the rejected tokens"
fi

if grep -qi "COMMAND" "$SERIAL_LOG" && grep -q "ASSIGN_DIR_DONE" "$SERIAL_LOG"; then
    ok "ASSIGN B=A verify (DIR B:\\COMMAND.COM shows A: contents)"
else
    fail "ASSIGN B=A verify (expected 'COMMAND' in DIR B:\\COMMAND.COM output)"
fi

if grep -q '^ASSIGN_CLEAR_DONE' "$SERIAL_LOG"; then
    ok "ASSIGN clear (no-arg call continued)"
else
    fail "ASSIGN clear (batch hung or crashed)"
fi

if grep -q '^ASSIGN_CLEAR_RESTORED_B' "$SERIAL_LOG"; then
    ok "ASSIGN clear restores access to physical B:"
else
    fail "ASSIGN clear did not restore the physical B: drive"
fi

echo ""
echo "--- SUBST tests ---"

for marker in SUBST_MISSING_PATH_REJECTED SUBST_ROOT_ACCEPTED \
              SUBST_DUP_CREATE_REJECTED SUBST_DUP_DELETE_REJECTED \
              SUBST_DELETE_NO_DRIVE_REJECTED SUBST_DRIVE_ONLY_REJECTED \
              SUBST_CREATE_DELETE_REJECTED SUBST_EXCESS_REJECTED \
              SUBST_UNKNOWN_REJECTED SUBST_STATE_PRESERVED \
              SUBST_INACTIVE_DELETE_REJECTED; do
    if grep -q "^${marker}" "$SERIAL_LOG"; then
        ok "${marker//_/ }"
    else
        fail "${marker//_/ }"
    fi
done


if grep -q '^Invalid switch - /D ' "$SERIAL_LOG" \
    && grep -q '^Invalid switch - /Z ' "$SERIAL_LOG" \
    && grep -q '^Incorrect number of parameters - /D ' "$SERIAL_LOG" \
    && grep -q '^Incorrect number of parameters - EXTRA ' "$SERIAL_LOG"; then
    ok "SUBST parser diagnostics distinguish switches and excess parameters"
else
    fail "SUBST parser diagnostics did not match the rejected forms"
fi

if grep -q "SUBST_CREATE_DONE" "$SERIAL_LOG"; then
    ok "SUBST D: A:\\SUBSTDIR (created silently, batch continued)"
else
    fail "SUBST D: A:\\SUBSTDIR (batch hung or crashed)"
fi

if grep -q "D: => " "$SERIAL_LOG" && grep -q "SUBST_LIST_DONE" "$SERIAL_LOG"; then
    ok "SUBST list (shows 'D: => ...' for active substitution)"
else
    fail "SUBST list (expected 'D: => ' in SUBST output)"
fi

if grep -q "SUBST_IO_DONE" "$SERIAL_LOG"; then
    ok "SUBST file I/O (batch continued)"
else
    fail "SUBST file I/O (batch hung or crashed)"
fi

if grep -q "SUBST_FILE_EXISTS" "$SERIAL_LOG"; then
    ok "SUBST COPY (file written to D: via COPY)"
else
    fail "SUBST COPY (COPY to D:\\TEST.COM failed)"
fi

if grep -q "SUBST_PASSTHRU_OK" "$SERIAL_LOG"; then
    ok "SUBST pass-through (D:\\TEST.COM visible at A:\\SUBSTDIR\\TEST.COM)"
else
    fail "SUBST pass-through (file on D: not found at real path A:\\SUBSTDIR)"
fi

if grep -q "SUBST_DEL_DONE" "$SERIAL_LOG"; then
    ok "SUBST D: /D (removed silently, batch continued)"
else
    fail "SUBST D: /D (batch hung or crashed)"
fi

echo ""
echo "--- JOIN tests ---"

for marker in JOIN_NONEMPTY_REJECTED JOIN_SAME_DRIVE_REJECTED \
              JOIN_CURRENT_DRIVE_REJECTED JOIN_DUP_CREATE_REJECTED \
              JOIN_DUP_DELETE_REJECTED \
              JOIN_DELETE_NO_DRIVE_REJECTED JOIN_DRIVE_ONLY_REJECTED \
              JOIN_CREATE_DELETE_REJECTED JOIN_EXCESS_REJECTED \
              JOIN_UNKNOWN_REJECTED JOIN_STATE_PRESERVED \
              JOIN_INACTIVE_DELETE_REJECTED; do
    if grep -q "^${marker}" "$SERIAL_LOG"; then
        ok "${marker//_/ }"
    else
        fail "${marker//_/ }"
    fi
done


if grep -q '^Invalid switch - /D ' "$SERIAL_LOG" \
    && grep -q '^Invalid switch - /Z ' "$SERIAL_LOG" \
    && grep -q '^Too many parameters - /D ' "$SERIAL_LOG" \
    && grep -q '^Too many parameters - EXTRA ' "$SERIAL_LOG" \
    && grep -q '^Directory not empty - A:\\JOINDIR' "$SERIAL_LOG"; then
    ok "JOIN parser diagnostics distinguish switches and excess parameters"
else
    fail "JOIN parser diagnostics did not match the rejected forms"
fi

if grep -q "JOIN_CREATE_DONE" "$SERIAL_LOG"; then
    ok "JOIN B: A:\\JOINDIR (joined silently, batch continued)"
else
    fail "JOIN B: A:\\JOINDIR (batch hung or crashed)"
fi

if grep -q "B: => " "$SERIAL_LOG" && grep -q "JOIN_LIST_DONE" "$SERIAL_LOG"; then
    ok "JOIN list (shows 'B: => ...' for active join)"
else
    fail "JOIN list (expected 'B: => ' in JOIN output)"
fi

if grep -qi "BJOIN" "$SERIAL_LOG" && grep -q "JOIN_DIR_DONE" "$SERIAL_LOG"; then
    ok "JOIN DIR (B:'s BJOIN.TXT visible at A:\\JOINDIR)"
else
    fail "JOIN DIR (expected BJOIN.TXT from B: to appear under A:\\JOINDIR)"
fi

if grep -qi "JOIN_B_FILE_CONTENT" "$SERIAL_LOG"; then
    ok "JOIN TYPE (file content read through joined path)"
else
    fail "JOIN TYPE (expected 'JOIN_B_FILE_CONTENT' from TYPE A:\\JOINDIR\\BJOIN.TXT)"
fi

if grep -q "JOIN_COPY_OK" "$SERIAL_LOG"; then
    ok "JOIN COPY (file copied from joined path to A:)"
else
    fail "JOIN COPY (COPY from A:\\JOINDIR\\BJOIN.TXT to A: failed)"
fi

if grep -q "JOIN_DEL_DONE" "$SERIAL_LOG"; then
    ok "JOIN B: /D (unjoined, batch continued)"
else
    fail "JOIN B: /D (batch hung or crashed)"
fi

echo ""
if grep -q '^===DONE===' "$SERIAL_LOG"; then
    ok "Batch reached ===DONE==="
else
    fail "Batch did NOT reach ===DONE=== (hung or crashed early)"
    echo "--- last 30 lines of serial log ---"
    tail -30 "$SERIAL_LOG"
    echo "---"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
