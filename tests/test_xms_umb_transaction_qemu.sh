#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
FLOPPY="$OUT/floppy.img"
PROBE="$OUT/xms-umb-transaction.com"
LIFECYCLE_PROBE="$OUT/umb-lifecycle.com"
LIFECYCLE_CHILD="$OUT/umbchild.com"
DISABLED_PROBE="$OUT/xms-umb-disabled.com"
REGISTER_PROBE="$OUT/umb-registers.com"

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done

nasm -f bin "$ROOT/tests/xms_umb_transaction_probe.asm" -o "$PROBE"
nasm -f bin "$ROOT/tests/umb_lifecycle_probe.asm" -o "$LIFECYCLE_PROBE"
nasm -f bin "$ROOT/tests/umb_exit_child.asm" -o "$LIFECYCLE_CHILD"
nasm -f bin "$ROOT/tests/xms_umb_disabled_probe.asm" -o "$DISABLED_PROBE"
nasm -f bin "$ROOT/tests/umb_register_reference.asm" -o "$REGISTER_PROBE"

for mode in 0 1 2 3 4 5 6 7 8 9; do
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

provider="$OUT/xms-umb-provider-disabled.sys"
image="$OUT/floppy-xms-umb-disabled.img"
log="$OUT/xms-umb-disabled.log"
nasm -DTEST_MODE=0 -f bin "$ROOT/tests/xms_umb_provider.asm" -o "$provider"
cp "$FLOPPY" "$image"
mcopy -o -i "$image" "$provider" ::XMSPROV.SYS
mcopy -o -i "$image" "$DISABLED_PROBE" ::XMSOFF.COM
{
    printf 'DEVICE=A:\\XMSPROV.SYS\r\n'
    printf 'DOS=UMB\r\n'
    printf 'DOS=NOUMB\r\n'
} | mcopy -o -i "$image" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'XMSOFF.COM\r\n'
} | mcopy -o -i "$image" - ::AUTOEXEC.BAT
timeout 20 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$log" 2>&1 || true
if ! grep -q '^XMS_UMB_DISABLED_PASS' "$log"; then
    echo "FAIL: DOS=NOUMB acquisition suppression" >&2
    sed -n '1,120p' "$log" >&2
    exit 1
fi

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
    printf 'DOS=NOUMB\r\n'
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

provider="$OUT/xms-umb-provider-registers.sys"
image="$OUT/floppy-umb-registers.img"
log="$OUT/umb-registers.log"
nasm -DTEST_MODE=0 -f bin "$ROOT/tests/xms_umb_provider.asm" -o "$provider"
cp "$FLOPPY" "$image"
mcopy -o -i "$image" "$provider" ::XMSPROV.SYS
mcopy -o -i "$image" "$REGISTER_PROBE" ::UMBREG.COM
{
    printf 'DEVICE=A:\\XMSPROV.SYS\r\n'
    printf 'DOS=UMB\r\n'
} | mcopy -o -i "$image" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'UMBREG.COM\r\n'
} | mcopy -o -i "$image" - ::AUTOEXEC.BAT
timeout 20 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
    -boot a -serial stdio -no-reboot >"$log" 2>&1 || true
for expected in \
    'CASE=0 CF=0 AX=0000 BX=2222 CX=3333 DX=4444 SI=5555 DI=6666 BP=7777' \
    'CASE=1 CF=0 AX=5801 BX=0000 CX=3333 DX=4444 SI=5555 DI=6666 BP=7777' \
    'CASE=I CF=1 AX=0001 BX=0100 CX=3333 DX=4444 SI=5555 DI=6666 BP=7777' \
    'CASE=2 CF=0 AX=5800 BX=2222 CX=3333 DX=4444 SI=5555 DI=6666 BP=7777' \
    'CASE=3 CF=0 AX=5803 BX=0000 CX=3333 DX=4444 SI=5555 DI=6666 BP=7777' \
    'CASE=L CF=1 AX=0001 BX=0100 CX=3333 DX=4444 SI=5555 DI=6666 BP=7777' \
    'CASE=4 CF=1 AX=0001 BX=2222 CX=3333 DX=4444 SI=5555 DI=6666 BP=7777'
do
    if ! grep -Fq "$expected" "$log"; then
        echo "FAIL: UMB register contract: $expected" >&2
        sed -n '1,120p' "$log" >&2
        exit 1
    fi
done
if [[ $(grep -Ec '^CASE=[01I234L].* DS=[0-9A-F]{4} ES=8888' "$log") -ne 7 ]]; then
    echo "FAIL: UMB segment-register preservation" >&2
    sed -n '1,120p' "$log" >&2
    exit 1
fi

echo "  PASS: XMS transactions, UMB allocator lifecycle, and register contract"
