#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
FLOPPY="$OUT/floppy.img"
HIMEM="$OUT/HIMEM.SYS"
XMS_PROBE="$OUT/xms-reference.com"
PROVIDER_PROBE="$OUT/himem-provider.com"
IMAGE="$OUT/floppy-himem.img"
LOG="$OUT/himem.log"

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done

"$ROOT/bin/jwasm-bin" -Fo"$HIMEM" \
    "$ROOT/MS-DOS/v4.0/src/DEV/HIMEM/HIMEM.ASM"
nasm -f bin "$ROOT/tests/xms_reference_probe.asm" -o "$XMS_PROBE"
nasm -f bin "$ROOT/tests/himem_provider_probe.asm" -o "$PROVIDER_PROBE"

cp "$FLOPPY" "$IMAGE"
mcopy -o -i "$IMAGE" "$HIMEM" ::HIMEM.SYS
mcopy -o -i "$IMAGE" "$XMS_PROBE" ::XMSREF.COM
mcopy -o -i "$IMAGE" "$PROVIDER_PROBE" ::HIMPROV.COM
{
    printf 'DEVICE=A:\\HIMEM.SYS\r\n'
    printf 'DOS=UMB\r\n'
} | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'XMSREF.COM\r\n'
    printf 'HIMPROV.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

timeout 25 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$LOG" 2>&1 || true

for expected in \
    'VERSION CF=0 AX=0200 BX=0100 DX=0001' \
    'MOVE_TO_XMS CF=0 AX=0001' \
    'MOVE_FROM_XMS CF=0 AX=0001' \
    'MOVE_VERIFY CF=0 AX=0001' \
    'SHRUNK_INFO CF=0 AX=0001 BX=001F DX=0020' \
    'A20_FINAL CF=0 AX=0000' \
    'HIMEM_PROVIDER_PASS'
do
    if ! grep -Fq "$expected" "$LOG"; then
        echo "FAIL: repository HIMEM contract: $expected" >&2
        sed -n '1,180p' "$LOG" >&2
        exit 1
    fi
done

echo "  PASS: repository XMS core and transactional UMB provider"
