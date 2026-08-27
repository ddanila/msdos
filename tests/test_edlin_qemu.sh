#!/bin/bash
# EDLIN open/list/quit regression under a real DOS/QEMU environment.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"
BOOT_IMG="$OUT/edlin-qemu-boot.img"
SERIAL_LOG="$OUT/edlin-qemu-serial.log"
PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

[[ -f "$FLOPPY" ]] || { echo "ERROR: $FLOPPY not found — run 'make deploy' first"; exit 1; }

echo "=== EDLIN open/list/quit E2E test (QEMU) ==="
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
cp "$FLOPPY" "$BOOT_IMG"

printf 'ALPHA\r\nBETA\r\nGAMMA\r\n' | mcopy -o -i "$BOOT_IMG" - ::EDLTEST.TXT
{
    printf '1,3L\r\n'
    printf 'Q\r\n'
    printf 'Y\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::EDLIN.IN
{
    printf 'CTTY AUX\r\n'
    printf 'EDLIN EDLTEST.TXT < EDLIN.IN\r\n'
    printf 'ECHO EDLIN_DONE\r\n'
    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

echo "Booting QEMU (may take ~90s)..."
rm -f "$SERIAL_LOG"
(while true; do sleep 0.5; printf '\r\n'; done) | \
timeout 120 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -m 4 -serial stdio 2>/dev/null | tee "$SERIAL_LOG" >/dev/null; true

grep -q 'ALPHA' "$SERIAL_LOG" && grep -q 'GAMMA' "$SERIAL_LOG" \
    && ok "EDLIN listed the requested file range" \
    || fail "EDLIN did not list ALPHA through GAMMA"
grep -q 'EDLIN_DONE' "$SERIAL_LOG" \
    && ok "EDLIN quit and returned to COMMAND.COM" \
    || fail "EDLIN hung or crashed before returning"
grep -q '===DONE===' "$SERIAL_LOG" \
    && ok "Batch reached ===DONE===" \
    || fail "Batch did not reach ===DONE==="

echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
