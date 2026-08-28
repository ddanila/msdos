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
LIFECYCLE_PROBE="$OUT/umb-lifecycle-reference.com"
EMM_PROBE="$OUT/emm386-with-umb.com"
ISOLATION_PROBE="$OUT/umb-ems-isolation.com"
COMBINED_IMAGE="$OUT/floppy-himem-emm386.img"
COMBINED_LOG="$OUT/himem-emm386.log"

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
nasm -f bin "$ROOT/tests/umb_lifecycle_reference.asm" -o "$LIFECYCLE_PROBE"
nasm -f bin "$ROOT/tests/emm386_probe.asm" -o "$EMM_PROBE"
nasm -f bin "$ROOT/tests/umb_ems_isolation_probe.asm" -o "$ISOLATION_PROBE"

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

for expected_re in \
    '^BAD_HANDLE_FREE CF=0 AX=0000 BX=..A2 ' \
    '^ALLOCATE_ZERO CF=0 AX=0001 ' \
    '^LOCKED_FREE CF=0 AX=0000 BX=..AB ' \
    '^LOCKED_REALLOC CF=0 AX=0000 BX=..AB ' \
    '^UNLOCK_UNDERFLOW CF=0 AX=0000 BX=..AA ' \
    '^MOVE_ODD_LENGTH CF=0 AX=0000 BX=..A7 ' \
    '^MOVE_BAD_SOURCE CF=0 AX=0000 BX=..A3 ' \
    '^MOVE_BAD_DEST CF=0 AX=0000 BX=..A5 ' \
    '^MOVE_BAD_SOURCE_OFFSET CF=0 AX=0000 BX=..A7 ' \
    '^MOVE_OVERLAP CF=0 AX=0001 ' \
    '^MOVE_REVERSE_OVERLAP CF=0 AX=0001 ' \
    '^ALLOCATE_HUGE CF=0 AX=0000 BX=..A0 ' \
    '^HMA_SECOND_REQUEST CF=0 AX=0000 BX=..91 ' \
    '^HMA_SECOND_RELEASE CF=0 AX=0000 BX=..93 ' \
    '^A20_LOCAL_UNDERFLOW CF=0 AX=0000 BX=..82 '
do
    if ! grep -Eq "$expected_re" "$LOG"; then
        echo "FAIL: repository HIMEM error contract: $expected_re" >&2
        sed -n '1,220p' "$LOG" >&2
        exit 1
    fi
done

cp "$FLOPPY" "$COMBINED_IMAGE"
mcopy -o -i "$COMBINED_IMAGE" "$HIMEM" ::HIMEM.SYS
mcopy -o -i "$COMBINED_IMAGE" "$LIFECYCLE_PROBE" ::UMBLREF.COM
mcopy -o -i "$COMBINED_IMAGE" "$EMM_PROBE" ::EMMPROBE.COM
mcopy -o -i "$COMBINED_IMAGE" "$ISOLATION_PROBE" ::UMBEMS.COM
{
    printf 'DEVICE=A:\\HIMEM.SYS\r\n'
    printf 'DEVICE=A:\\EMM386.SYS M5\r\n'
    printf 'DOS=UMB\r\n'
} | mcopy -o -i "$COMBINED_IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'UMBLREF.COM\r\n'
    printf 'UMBEMS.COM\r\n'
    printf 'EMMPROBE.COM\r\n'
} | mcopy -o -i "$COMBINED_IMAGE" - ::AUTOEXEC.BAT
timeout 35 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$COMBINED_IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$COMBINED_LOG" 2>&1 || true

if ! grep -Fq 'UMB_LIFECYCLE_END' "$COMBINED_LOG" \
    || ! grep -Eq '^ALLOC_0010 C=0 AX=[A-F][0-9A-F]{3}' "$COMBINED_LOG" \
    || ! grep -Eq '^ALLOC_AFTER_LARGEST C=0 AX=[A-F][0-9A-F]{3}' "$COMBINED_LOG" \
    || ! grep -Fq 'EMM386_API_PASS' "$COMBINED_LOG" \
    || ! grep -Fq 'UMB_EMS_ISOLATION_PASS' "$COMBINED_LOG"
then
    echo "FAIL: combined HIMEM/EMM386 UMB and EMS contract" >&2
    sed -n '1,220p' "$COMBINED_LOG" >&2
    exit 1
fi

echo "  PASS: repository XMS core and concurrent paging-backed UMB/EMS provider"
