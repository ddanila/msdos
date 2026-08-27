#!/bin/bash
# Verify GRAFTABL's resident code-page table and replacement behavior.

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
SRC="$REPO_ROOT/MS-DOS/v4.0/src"
FLOPPY="$OUT/floppy.img"
BOOT_IMG="$OUT/floppy-graftabl.img"
PROBE_COM="$OUT/graftabl-probe.com"
EXIT_COM="$OUT/graftabl-exit.com"
SERIAL_LOG="$OUT/graftabl.log"

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

for tool in mcopy nasm python3 qemu-system-i386 timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found: $tool"
        exit 1
    fi
done

python3 "$REPO_ROOT/tests/extract_graftabl_font.py" \
    "$SRC/CMD/GRAFTABL/GRTABUS.ASM" "$OUT/graftabl-437.bin"
python3 "$REPO_ROOT/tests/extract_graftabl_font.py" \
    "$SRC/CMD/GRAFTABL/GRTABML.ASM" "$OUT/graftabl-850.bin"
nasm -f bin "$REPO_ROOT/tests/graftabl_probe.asm" -o "$PROBE_COM"
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"

cp "$FLOPPY" "$BOOT_IMG"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$BOOT_IMG" "$PROBE_COM" ::GRTPROBE.COM
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'GRAFTABL 437\r\n'
    printf 'IF ERRORLEVEL 1 ECHO GRAFTABL_437_LOAD_FAILED\r\n'
    printf 'GRTPROBE 437\r\n'
    printf 'IF ERRORLEVEL 1 ECHO GRAFTABL_437_TABLE_FAILED\r\n'
    printf 'ECHO GRAFTABL_437_VERIFIED\r\n'
    printf 'GRAFTABL 850\r\n'
    printf 'IF ERRORLEVEL 2 ECHO GRAFTABL_850_LOAD_FAILED\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO GRAFTABL_850_STATUS_FAILED\r\n'
    printf 'GRTPROBE 850\r\n'
    printf 'IF ERRORLEVEL 1 ECHO GRAFTABL_850_TABLE_FAILED\r\n'
    printf 'ECHO GRAFTABL_850_VERIFIED\r\n'
    printf 'GRAFTABL 437\r\n'
    printf 'IF ERRORLEVEL 2 ECHO GRAFTABL_RELOAD_STATUS_FAILED\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO GRAFTABL_RELOAD_STATUS_FAILED\r\n'
    printf 'GRTPROBE 437\r\n'
    printf 'IF ERRORLEVEL 1 ECHO GRAFTABL_RELOAD_FAILED\r\n'
    printf 'GRAFTABL /STATUS\r\n'
    printf 'ECHO GRAFTABL_DONE\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

rm -f "$SERIAL_LOG"
timeout 20 qemu-system-i386 \
    -display none -monitor none \
    -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$SERIAL_LOG" 2>&1 || true

if grep -q 'GRAFTABL_437_VERIFIED' "$SERIAL_LOG" \
    && grep -q 'GRAFTABL_850_VERIFIED' "$SERIAL_LOG" \
    && grep -q 'GRAFTABL_DONE' "$SERIAL_LOG" \
    && grep -q 'Active Code Page: 437' "$SERIAL_LOG" \
    && ! grep -q 'GRAFTABL_.*_FAILED' "$SERIAL_LOG"; then
    echo "  PASS: GRAFTABL installed and replaced exact resident code-page tables"
    exit 0
fi

echo "  FAIL: GRAFTABL resident table contract did not complete"
sed -n '1,200p' "$SERIAL_LOG"
exit 1
