#!/bin/bash

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT_IMG="$OUT/floppy-ifsfunc-filesys.img"
IFS_SYS="$OUT/ifsfunc-filesys-testifs.sys"
PROBE_COM="$OUT/ifsfunc-filesys-probe.com"
EXIT_COM="$OUT/ifsfunc-filesys-exit.com"
SERIAL_LOG="$OUT/ifsfunc-filesys.log"

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

for tool in mcopy nasm qemu-system-i386 timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found: $tool"
        exit 1
    fi
done

cp "$FLOPPY" "$BOOT_IMG"
nasm -f bin "$REPO_ROOT/tests/config_ifs_driver.asm" -o "$IFS_SYS"
nasm -f bin "$REPO_ROOT/tests/ifsfunc_filesys_probe.asm" -o "$PROBE_COM"
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$BOOT_IMG" "$IFS_SYS" ::TESTIFS.SYS
mcopy -o -i "$BOOT_IMG" "$PROBE_COM" ::IFSPROBE.COM
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM
printf 'IFS=TESTIFS.SYS\r\n' | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'IFSFUNC NAMES=256\r\n'
    printf 'IF ERRORLEVEL 1 ECHO IFSFUNC_NAMES_RANGE_REJECTED\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO IFSFUNC_NAMES_RANGE_FAILED\r\n'
    printf 'IFSFUNC NAMES=1 NAMES=2\r\n'
    printf 'IF ERRORLEVEL 1 ECHO IFSFUNC_NAMES_REPEAT_REJECTED\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO IFSFUNC_NAMES_REPEAT_FAILED\r\n'
    printf 'IFSFUNC NAMES=7\r\n'
    printf 'IF ERRORLEVEL 1 ECHO IFSFUNC_INSTALL_FAILED\r\n'
    printf 'FILESYS C: TESTIFS\r\n'
    printf 'IF ERRORLEVEL 1 ECHO FILESYS_ATTACH_FAILED\r\n'
    printf 'FILESYS C: TESTIFS\r\n'
    printf 'IF ERRORLEVEL 1 ECHO FILESYS_DUPLICATE_REJECTED\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO FILESYS_DUPLICATE_FAILED\r\n'
    printf 'FILESYS D: NOIFS\r\n'
    printf 'IF ERRORLEVEL 1 ECHO FILESYS_UNKNOWN_IFS_REJECTED\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO FILESYS_UNKNOWN_IFS_FAILED\r\n'
    printf 'FILESYS C:\r\n'
    printf 'IF ERRORLEVEL 1 ECHO FILESYS_STATUS_FAILED\r\n'
    printf 'ECHO IFSFUNC_FILESYS_BEFORE_DETACH\r\n'
    printf 'FILESYS C: /D\r\n'
    printf 'ECHO IFSFUNC_FILESYS_AFTER_DETACH\r\n'
    printf 'IF ERRORLEVEL 1 ECHO FILESYS_DETACH_FAILED\r\n'
    printf 'FILESYS C: /D\r\n'
    printf 'IF ERRORLEVEL 1 ECHO FILESYS_REPEAT_DETACH_REJECTED\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO FILESYS_REPEAT_DETACH_FAILED\r\n'
    printf 'FILESYS C:\r\n'
    printf 'IF ERRORLEVEL 1 ECHO FILESYS_EMPTY_STATUS_FAILED\r\n'
    printf 'IFSPROBE.COM\r\n'
    printf 'IF ERRORLEVEL 1 ECHO IFSFUNC_FILESYS_PROBE_FAILED\r\n'
    printf 'ECHO IFSFUNC_FILESYS_DONE\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

rm -f "$SERIAL_LOG"
timeout 20 qemu-system-i386 \
    -display none \
    -monitor none \
    -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$SERIAL_LOG" 2>&1 || true

if grep -q 'IFSFUNC_FILESYS_DONE' "$SERIAL_LOG" \
    && grep -Eq 'C:[[:space:]]+TESTIFS([[:space:]]|$)' "$SERIAL_LOG" \
    && grep -q 'FILESYS_DUPLICATE_REJECTED' "$SERIAL_LOG" \
    && grep -q 'IFSFUNC_NAMES_RANGE_REJECTED' "$SERIAL_LOG" \
    && grep -q 'IFSFUNC_NAMES_REPEAT_REJECTED' "$SERIAL_LOG" \
    && grep -q 'FILESYS_UNKNOWN_IFS_REJECTED' "$SERIAL_LOG" \
    && grep -q 'FILESYS_REPEAT_DETACH_REJECTED' "$SERIAL_LOG" \
    && grep -q 'No entries found' "$SERIAL_LOG" \
    && ! grep -q 'IFSFUNC_.*_FAILED\|FILESYS_.*_FAILED' "$SERIAL_LOG"; then
    echo "  PASS: FILESYS attach/status/detach traversed resident IFSFUNC and TESTIFS"
    exit 0
fi

echo "  FAIL: IFSFUNC/FILESYS behavioral contract did not complete"
sed -n '1,200p' "$SERIAL_LOG"
exit 1
