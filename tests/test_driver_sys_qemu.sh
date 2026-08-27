#!/bin/bash
# Exercise DRIVER.SYS with a second physical floppy and QMP media prompt input.

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"
BOOT_IMG="$OUT/floppy-driver-sys.img"
TARGET_IMG="$OUT/driver-sys-target.img"
PROBE_COM="$OUT/driver-sys.com"
SERIAL_LOG="$OUT/driver-sys.log"
SCREEN_LOG="$OUT/driver-sys-screen.log"
QMP_SOCK="$OUT/driver-sys-qmp.sock"

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

for tool in nasm mcopy python3 qemu-system-i386 timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found: $tool"
        exit 1
    fi
done

trap 'kill ${QEMU_PID:-} 2>/dev/null; rm -f "$QMP_SOCK" 2>/dev/null; true' EXIT
cp "$FLOPPY" "$BOOT_IMG"
cp "$FLOPPY" "$TARGET_IMG"
nasm -f bin "$REPO_ROOT/tests/driver_sys_probe.asm" -o "$PROBE_COM"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$BOOT_IMG" "$PROBE_COM" ::DRVPROBE.COM
printf 'DRIVER_OK' | mcopy -o -i "$TARGET_IMG" - ::DRVTEST.TXT
{
    printf 'DEVICE=DRIVER.SYS /D:1\r\n'
    printf 'LASTDRIVE=Z\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'DRVPROBE.COM\r\n'
    printf 'ECHO DRIVER_SCREEN_DONE\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

rm -f "$QMP_SOCK" "$SERIAL_LOG" "$SCREEN_LOG"
timeout 45 qemu-system-i386 \
    -display none \
    -monitor none \
    -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET_IMG",cache=writethrough \
    -boot a -serial file:"$SERIAL_LOG" -no-reboot \
    -qmp unix:"$QMP_SOCK",server,nowait \
    2>/dev/null &
QEMU_PID=$!

for _ in $(seq 1 25); do
    [[ -S "$QMP_SOCK" ]] && break
    sleep 0.2
done
if [[ ! -S "$QMP_SOCK" ]]; then
    echo "ERROR: DRIVER.SYS QMP socket did not appear"
    exit 1
fi

python3 "$REPO_ROOT/tests/screen_expect.py" \
    "$QMP_SOCK" "$SCREEN_LOG" \
    'Insert diskette for drive C:' 'ret' \
    'DRIVER_SCREEN_DONE' ''

kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true

written_payload="$(mtype -i "$TARGET_IMG" ::DRVWRITE.TXT 2>/dev/null || true)"
source_payload="$(mtype -i "$TARGET_IMG" ::DRVTEST.TXT 2>/dev/null || true)"
if grep -q 'DRIVER_SYS_PASS' "$SERIAL_LOG" \
    && [[ "$written_payload" == 'DRIVER_WRITE_OK' ]] \
    && [[ "$source_payload" == 'DRIVER_OK' ]]; then
    echo "  PASS: DRIVER.SYS forwarded exact reads and writes to physical B:"
    exit 0
fi

echo "  FAIL: DRIVER.SYS behavioral contract did not complete"
sed -n '1,120p' "$SERIAL_LOG"
sed -n '1,160p' "$SCREEN_LOG"
exit 1
