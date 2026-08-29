#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/floppy-setver.img"
LOG="$OUT/setver.log"
PROBE="$OUT/SETPROBE.COM"

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done

[[ -f "$BASE" ]] || {
    echo "ERROR: missing build artifact: $BASE" >&2
    exit 1
}

nasm -f bin "$ROOT/tests/setver_probe.asm" -o "$PROBE"
cp "$BASE" "$IMAGE"
mcopy -o -i "$IMAGE" "$PROBE" ::SETPROBE.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'SETPROBE.COM\r\n'
    printf 'SETVER SETPROBE.COM 3.30\r\n'
    printf 'SETPROBE.COM\r\n'
    printf 'SETVER\r\n'
    printf 'SETVER SETPROBE.COM 6.22\r\n'
    printf 'SETPROBE.COM\r\n'
    printf 'SETVER SETPROBE.COM /DELETE\r\n'
    printf 'SETPROBE.COM\r\n'
    printf 'SETVER A:\\ SETPROBE.COM 4.01\r\n'
    printf 'SETPROBE.COM\r\n'
    printf 'SETVER A:\\ SETPROBE.COM /delete\r\n'
    printf 'SETPROBE.COM\r\n'
    printf 'SETVER SETPROBE.COM 10.00\r\n'
    printf 'SETPROBE.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

timeout 30 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot >"$LOG" 2>&1 || true

versions=$(grep -o 'SETVER_PROBE_VERSION=[0-9][0-9]*\.[0-9][0-9]' "$LOG" || true)
expected=$(printf '%s\n' \
    SETVER_PROBE_VERSION=5.00 \
    SETVER_PROBE_VERSION=3.30 \
    SETVER_PROBE_VERSION=6.22 \
    SETVER_PROBE_VERSION=5.00 \
    SETVER_PROBE_VERSION=4.01 \
    SETVER_PROBE_VERSION=5.00 \
    SETVER_PROBE_VERSION=5.00)
if [[ "$versions" != "$expected" ]]; then
    echo 'FAIL: SETVER version transitions differ' >&2
    printf 'Expected:\n%s\nActual:\n%s\n' "$expected" "$versions" >&2
    sed -n '1,200p' "$LOG" >&2
    exit 1
fi
grep -Fq 'SETPROBE.COM 3.30' "$LOG" || {
    echo 'FAIL: SETVER listing omitted the added entry' >&2
    sed -n '1,200p' "$LOG" >&2
    exit 1
}
grep -Fq 'Entry added.' "$LOG"
grep -Fq 'Entry updated.' "$LOG"
grep -Fq 'Entry deleted.' "$LOG"
grep -Fq 'Invalid version. Use major.minor.' "$LOG"

echo '  PASS: SETVER list/add/update/delete and per-program DOS version reporting'
