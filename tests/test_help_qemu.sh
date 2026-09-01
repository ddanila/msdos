#!/bin/bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"

TEST_IMG="$OUT/floppy-help-qemu.img"
SERIAL_LOG="$OUT/help-qemu-serial.log"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== command help and EXEPACK integrity test (QEMU) ==="


echo "Building test floppy..."
cp "$FLOPPY" "$TEST_IMG"
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$OUT/help-qexit.com"
mcopy -o -i "$TEST_IMG" "$OUT/help-qexit.com" ::QEXIT.COM

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'HELP > HELP.OUT\r\n'
    printf 'TYPE HELP.OUT\r\n'
    printf 'ECHO ---AFTER_HELP_INDEX---\r\n'
    printf 'HELP format\r\n'
    printf 'ECHO ---AFTER_HELP_TOPIC---\r\n'
    printf 'HELP DOESNOTEXIST\r\n'
    printf 'IF ERRORLEVEL 1 ECHO ---HELP_NOT_FOUND_STATUS---\r\n'
    printf 'HELP FORMAT EXTRA\r\n'
    printf 'IF ERRORLEVEL 1 ECHO ---HELP_BAD_ARGS_STATUS---\r\n'
    printf 'HELP /?\r\n'
    printf 'ECHO ---AFTER_HELP_USAGE---\r\n'
    printf 'FASTHELP format\r\n'
    printf 'ECHO ---AFTER_FASTHELP---\r\n'
    printf 'MEM /?\r\n'
    printf 'ATTRIB /?\r\n'
    printf 'XCOPY /?\r\n'
    printf 'FORMAT /?\r\n'
    printf 'FC /?\r\n'
    printf 'JOIN /?\r\n'
    printf 'SUBST /?\r\n'
    printf 'REPLACE /?\r\n'
    printf 'FIND /?\r\n'
    printf 'ECHO ---AFTER_FIND---\r\n'
    printf 'TREE /?\r\n'
    printf 'BACKUP /?\r\n'
    printf 'RESTORE /?\r\n'
    printf 'DISKCOMP /?\r\n'
    printf 'DISKCOPY /?\r\n'
    printf 'GRAFTABL /?\r\n'
    printf 'LABEL /?\r\n'
    printf 'COMP /?\r\n'
    printf 'ASSIGN /?\r\n'
    printf 'SYS /?\r\n'
    printf 'EXE2BIN /?\r\n'
    printf 'ECHO ---AFTER_EXE2BIN---\r\n'
    printf 'KEYB /?\r\n'
    printf 'MODE /?\r\n'
    printf 'RECOVER /?\r\n'
    printf 'CHKDSK /?\r\n'
    printf 'FILESYS /?\r\n'
    printf 'FDISK /?\r\n'
    printf 'ECHO ---AFTER_FDISK---\r\n'
    printf 'IFSFUNC /?\r\n'
    printf 'ECHO ---AFTER_IFSFUNC---\r\n'
    printf 'ECHO ---DONE---\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$TEST_IMG" - ::AUTOEXEC.BAT

echo "Booting QEMU (headless, up to 120s)..."
rm -f "$SERIAL_LOG"
timeout 120 qemu-system-i386 \
    -display none \
    -fda "$TEST_IMG" \
    -boot a -m 4 \
    -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null 2>/dev/null | tee "$SERIAL_LOG" > /dev/null; true

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty or missing — QEMU may have failed to boot"
    exit 1
fi

if grep -qi "Packed file is corrupt" "$SERIAL_LOG"; then
    fail "EXEPACK corruption detected in one or more tools"
else
    ok "EXEPACK: no corruption in any tool"
fi

if grep -q "MS-DOS command help" "$SERIAL_LOG" && grep -q -- "---AFTER_HELP_INDEX---" "$SERIAL_LOG"; then
    ok "HELP lists the command index"
else
    fail "HELP did not render its command index"
fi

if grep -q "Formats a disk for use with MS-DOS" "$SERIAL_LOG" && grep -q "Syntax: FORMAT drive:" "$SERIAL_LOG" && grep -q -- "---AFTER_HELP_TOPIC---" "$SERIAL_LOG"; then
    ok "HELP resolves a lowercase topic and prints its syntax"
else
    fail "HELP did not render the FORMAT topic"
fi

if grep -q "No help is available for that command" "$SERIAL_LOG" && grep -q -- "---HELP_NOT_FOUND_STATUS---" "$SERIAL_LOG"; then
    ok "HELP rejects an unknown topic with errorlevel 1"
else
    fail "HELP unknown-topic contract failed"
fi

if grep -q -- "---HELP_BAD_ARGS_STATUS---" "$SERIAL_LOG"; then
    ok "HELP rejects excess operands with errorlevel 1"
else
    fail "HELP excess-operand contract failed"
fi

if grep -q "HELP \[command\]" "$SERIAL_LOG" && grep -q -- "---AFTER_HELP_USAGE---" "$SERIAL_LOG"; then
    ok "HELP /? prints usage and returns"
else
    fail "HELP /? contract failed"
fi

if grep -q -- "---AFTER_FASTHELP---" "$SERIAL_LOG"; then
    ok "FASTHELP uses the lean text-help interface"
else
    fail "FASTHELP did not return from a topic lookup"
fi

for tool in FIND EXE2BIN FDISK IFSFUNC; do
    if grep -q -- "---AFTER_${tool}---" "$SERIAL_LOG"; then
        ok "$tool /? returned to the command interpreter"
    else
        fail "$tool /? did not return to the command interpreter"
    fi
done

if grep -q "DONE" "$SERIAL_LOG"; then
    ok "QEMU boot ran to completion"
else
    fail "QEMU boot did not reach ---DONE--- marker (crash or hang?)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Serial log saved to: $SERIAL_LOG"
fi
[[ $FAIL -eq 0 ]]
