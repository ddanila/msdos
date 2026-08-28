#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
FLOPPY="$OUT/floppy.img"
PROBE="$OUT/xms-umb-transaction.com"
LIFECYCLE_PROBE="$OUT/umb-lifecycle.com"
LIFECYCLE_CHILD="$OUT/umbchild.com"

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done

nasm -f bin "$ROOT/tests/xms_umb_transaction_probe.asm" -o "$PROBE"
nasm -f bin "$ROOT/tests/umb_lifecycle_probe.asm" -o "$LIFECYCLE_PROBE"
nasm -f bin "$ROOT/tests/umb_exit_child.asm" -o "$LIFECYCLE_CHILD"

for mode in 0 1 2 3 4; do
    provider="$OUT/xms-umb-provider-$mode.sys"
    image="$OUT/floppy-xms-umb-$mode.img"
    log="$OUT/xms-umb-$mode.log"
    nasm -DTEST_MODE="$mode" -f bin "$ROOT/tests/xms_umb_provider.asm" -o "$provider"
    cp "$FLOPPY" "$image"
    mcopy -o -i "$image" "$provider" ::XMSPROV.SYS
    mcopy -o -i "$image" "$PROBE" ::XMSPROBE.COM
    {
        printf 'DEVICE=A:\\XMSPROV.SYS\r\n'
        printf 'DOS=UMB\r\n'
    } | mcopy -o -i "$image" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\n'
        printf 'CTTY AUX\r\n'
        printf 'XMSPROBE.COM\r\n'
    } | mcopy -o -i "$image" - ::AUTOEXEC.BAT
    timeout 20 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 4 \
        -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$log" 2>&1 || true
    if ! grep -q '^XMS_UMB_TRANSACTION_PASS' "$log"; then
        echo "FAIL: XMS UMB transaction mode $mode" >&2
        sed -n '1,120p' "$log" >&2
        exit 1
    fi
done

provider="$OUT/xms-umb-provider-lifecycle.sys"
image="$OUT/floppy-umb-lifecycle.img"
log="$OUT/umb-lifecycle.log"
nasm -DTEST_MODE=0 -f bin "$ROOT/tests/xms_umb_provider.asm" -o "$provider"
cp "$FLOPPY" "$image"
mcopy -o -i "$image" "$provider" ::XMSPROV.SYS
mcopy -o -i "$image" "$LIFECYCLE_PROBE" ::UMBLIFE.COM
mcopy -o -i "$image" "$LIFECYCLE_CHILD" ::UMBCHILD.COM
{
    printf 'DEVICE=A:\\XMSPROV.SYS\r\n'
    printf 'DOS=UMB\r\n'
} | mcopy -o -i "$image" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'UMBLIFE.COM\r\n'
} | mcopy -o -i "$image" - ::AUTOEXEC.BAT
timeout 20 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$log" 2>&1 || true
if ! grep -q '^UMB_LIFECYCLE_PASS' "$log"; then
    echo "FAIL: UMB allocator lifecycle" >&2
    sed -n '1,120p' "$log" >&2
    exit 1
fi

echo "  PASS: XMS transactions and UMB allocator lifecycle"
