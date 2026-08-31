#!/bin/bash

set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/smartdrv-runtime.img"
HDD="$OUT/smartdrv-runtime-hdd.img"
LOG="$OUT/smartdrv-runtime.log"
EXIT_COM="$OUT/smartdrv-runtime-exit.com"

[[ -f "$BASE" ]] || { echo "ERROR: run 'make deploy' first"; exit 1; }
for tool in dd mcopy nasm qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: missing $tool"; exit 1; }
done

cp "$BASE" "$IMAGE"
dd if=/dev/zero of="$HDD" bs=1M count=16 status=none
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
mcopy -o -i "$IMAGE" "$ROOT/src/DEV/SMARTDRV/SMARTDRV.EXE" ::SMARTDRV.EXE
mcopy -o -i "$IMAGE" "$EXIT_COM" ::QEXIT.COM
printf '\r\n' | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'SMARTDRV /Q\r\nIF ERRORLEVEL 1 ECHO SMARTDRV_RUNTIME_INSTALL_FAILED\r\n'
    printf 'ECHO SMARTDRV_RUNTIME_STATUS_BEGIN\r\nSMARTDRV /S\r\nECHO SMARTDRV_RUNTIME_STATUS_END\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_RUNTIME_CONTROL_FAILED\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

timeout 25 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -drive if=ide,index=0,format=raw,file="$HDD",cache=writethrough \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 -boot a -serial stdio -no-reboot \
    >"$LOG" 2>&1 || true

status="$(sed -n '/SMARTDRV_RUNTIME_STATUS_BEGIN/,/SMARTDRV_RUNTIME_STATUS_END/p' "$LOG")"
if grep -Fq 'Microsoft SMARTDrive Disk Cache v2.10' "$LOG" \
    && grep -Fq 'Cache size: 256K current, 256K maximum, 128K minimum' <<<"$status" \
    && grep -Eq 'Tracks: [1-9][0-9]* total' <<<"$status" \
    && ! grep -Eq 'SMARTDRV_RUNTIME_(INSTALL|CONTROL)_FAILED|SMARTDRV: ' "$LOG"; then
    echo '  PASS: SMARTDRV.EXE runtime self-installation and resident control'
    exit 0
fi

echo '  FAIL: SMARTDRV.EXE runtime installation contract did not complete'
sed -n '1,180p' "$LOG"
exit 1
