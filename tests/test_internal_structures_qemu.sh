#!/bin/bash

set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="$OUT/floppy.img"
IMAGE="$OUT/floppy-internal-structures.img"
PROBE="$OUT/internal-structures.com"
LOG="$OUT/internal-structures.log"
HIGH_IMAGE="$OUT/floppy-internal-structures-high.img"
HIGH_PROBE="$OUT/internal-structures-high.com"
HIGH_LOG="$OUT/internal-structures-high.log"
HDD_TEMPLATE="$OUT/internal-structures-hdd-template.img"
HDD0="$OUT/internal-structures-hdd0.img"
HDD1="$OUT/internal-structures-hdd1.img"

if [[ ! -f "$BASE" ]]; then
    echo "ERROR: $BASE not found — run 'make deploy' first"
    exit 1
fi

for tool in nasm mcopy mformat python3 qemu-system-i386 timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found: $tool"
        exit 1
    fi
done

nasm -f bin "$ROOT/tests/internal_structures_probe.asm" -o "$PROBE"
nasm -f bin -DDPB_SPLIT_ONLY "$ROOT/tests/internal_structures_probe.asm" -o "$HIGH_PROBE"
cp "$BASE" "$IMAGE"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$IMAGE" "$PROBE" ::INTERNAL.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'INTERNAL.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

rm -f "$LOG"
timeout 35 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$LOG" 2>&1 || true

if ! grep -q 'INTERNAL_STRUCTURES_PASS' "$LOG"; then
    echo "  FAIL: internal-structure probe did not complete"
    sed -n '1,180p' "$LOG"
    exit 1
fi

dd if=/dev/zero of="$HDD_TEMPLATE" bs=512 count=32256 status=none
python3 -c "
import struct
p = bytearray(512)
p[446:462] = bytes((0, 1, 1, 0, 6, 0, 63, 31)) + struct.pack('<II', 63, 31248)
p[510:512] = b'\\x55\\xaa'
with open('$HDD_TEMPLATE', 'r+b') as f:
    f.write(p)
"
mformat -i "$HDD_TEMPLATE@@32256" -t 31 -h 16 -n 63 -H 63 -c 4 ::
cp "$HDD_TEMPLATE" "$HDD0"
cp "$HDD_TEMPLATE" "$HDD1"
cp "$BASE" "$HIGH_IMAGE"
mcopy -o -i "$HIGH_IMAGE" "$HIGH_PROBE" ::INTERNAL.COM
mcopy -o -i "$HIGH_IMAGE" "$ROOT/src/DEV/HIMEM/HIMEM.SYS" ::HIMEM.SYS
{
    printf 'DEVICE=HIMEM.SYS /NUMHANDLES=32\r\n'
    printf 'DOS=HIGH\r\n'
} | mcopy -o -i "$HIGH_IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'INTERNAL.COM\r\n'
} | mcopy -o -i "$HIGH_IMAGE" - ::AUTOEXEC.BAT

rm -f "$HIGH_LOG"
timeout 35 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$HIGH_IMAGE",cache=writethrough \
    -drive if=ide,index=0,format=raw,file="$HDD0",cache=writethrough \
    -drive if=ide,index=1,format=raw,file="$HDD1",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$HIGH_LOG" 2>&1 || true

if grep -q 'INTERNAL_STRUCTURES_PASS' "$HIGH_LOG"; then
    echo "  PASS: observable PSP, MCB, LoL, DPB, CDS, SFT, SDA, device-chain, and split high-DOS DPB layouts"
    exit 0
fi

echo "  FAIL: high-DOS split-DPB probe did not complete"
sed -n '1,180p' "$HIGH_LOG"
exit 1
