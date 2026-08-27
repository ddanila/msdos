#!/bin/bash
# Exhaust a FAT12 root directory, assert the failure, then recover one slot.

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"
BOOT_IMG="$OUT/floppy-root-exhaustion.img"
PROBE_COM="$OUT/root-exhaustion.com"
SERIAL_LOG="$OUT/root-exhaustion.log"

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

cp "$FLOPPY" "$BOOT_IMG"
nasm -f bin "$REPO_ROOT/tests/root_exhaustion_probe.asm" -o "$PROBE_COM"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$BOOT_IMG" "$PROBE_COM" ::ROOTPROB.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'ROOTPROB.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

# Add the entry the DOS probe will release. Then replace every unused or VFAT
# long-name slot with a valid, unique zero-length DOS entry. DOS 4 predates
# VFAT and may otherwise treat those host-created 0Fh entries as reusable.
printf '' | mcopy -o -i "$BOOT_IMG" - ::RF00000.TMP
created=$(python3 - "$BOOT_IMG" <<'PYEOF'
import struct
import sys

path = sys.argv[1]
with open(path, 'r+b') as image:
    boot = image.read(512)
    bps = struct.unpack_from('<H', boot, 11)[0]
    reserved = struct.unpack_from('<H', boot, 14)[0]
    fats = boot[16]
    root_entries = struct.unpack_from('<H', boot, 17)[0]
    sectors_per_fat = struct.unpack_from('<H', boot, 22)[0]
    root_offset = (reserved + fats * sectors_per_fat) * bps
    image.seek(root_offset)
    directory = bytearray(image.read(root_entries * 32))
    filled = 0
    for index in range(root_entries):
        offset = index * 32
        entry = directory[offset:offset + 32]
        if entry[0] in (0x00, 0xE5) or entry[11] == 0x0F:
            name = f'ZX{index:06d}TMP'.encode('ascii')
            directory[offset:offset + 32] = name + bytes((0x20,)) + bytes(20)
            filled += 1
    image.seek(root_offset)
    image.write(directory)
print(filled)
PYEOF
)
if [[ $created -eq 0 ]]; then
    echo "ERROR: failed to establish an exactly full FAT12 root directory"
    exit 1
fi

rm -f "$SERIAL_LOG"
timeout 35 qemu-system-i386 \
    -display none \
    -monitor none \
    -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$SERIAL_LOG" 2>&1 || true

if grep -q 'ROOT_EXHAUSTION_PASS' "$SERIAL_LOG"; then
    echo "  PASS: full FAT12 root rejected creation, then recovered after one entry was released ($created normalized slots)"
    exit 0
fi

echo "  FAIL: FAT12 root-directory exhaustion contract did not complete"
sed -n '1,160p' "$SERIAL_LOG"
exit 1
