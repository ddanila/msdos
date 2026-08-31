#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT="$OUT/defrag-interactive-boot.img"
TARGET="$OUT/defrag-interactive-target.img"
QEXIT="$OUT/defrag-interactive-qexit.com"
MOUSE="$OUT/defrag-mouse.com"
SERIAL_BASE="$OUT/defrag-interactive-serial"
SERIAL_IN="$SERIAL_BASE.in"
SERIAL_OUT="$SERIAL_BASE.out"
LOG="$OUT/defrag-interactive.log"

cp "$BASE" "$BOOT"
dd if=/dev/zero of="$TARGET" bs=512 count=2880 status=none
mformat -i "$TARGET" -f 1440 ::
printf 'interactive defragmenter payload\r\n' |
    mcopy -o -i "$TARGET" - ::CONTROL.TXT
python3 - "$TARGET" <<'PY'
from pathlib import Path
import struct
import sys

path = Path(sys.argv[1])
disk = bytearray(path.read_bytes())
reserved = struct.unpack_from('<H', disk, 14)[0]
fat_count = disk[16]
root_entries = struct.unpack_from('<H', disk, 17)[0]
sectors_per_fat = struct.unpack_from('<H', disk, 22)[0]
root_sector = reserved + fat_count * sectors_per_fat
root = root_sector * 512
data_sector = root_sector + (root_entries * 32 + 511) // 512
entry = next(root + off for off in range(0, root_entries * 32, 32)
             if disk[root + off:root + off + 11] == b'CONTROL TXT')
old = struct.unpack_from('<H', disk, entry + 26)[0]
target = 100

def set_fat12(base, cluster, value):
    off = base + cluster * 3 // 2
    word = struct.unpack_from('<H', disk, off)[0]
    word = ((word & 0x000f) | ((value & 0xfff) << 4)) if cluster & 1 \
        else ((word & 0xf000) | (value & 0xfff))
    struct.pack_into('<H', disk, off, word)

source_off = (data_sector + old - 2) * 512
target_off = (data_sector + target - 2) * 512
disk[target_off:target_off + 512] = disk[source_off:source_off + 512]
for copy in range(fat_count):
    base = (reserved + copy * sectors_per_fat) * 512
    set_fat12(base, old, 0)
    set_fat12(base, target, 0xfff)
struct.pack_into('<H', disk, entry + 26, target)
path.write_bytes(disk)
PY
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
nasm -f bin "$ROOT/tests/defrag_mouse_tsr.asm" -o "$MOUSE"
mcopy -o -i "$BOOT" "$ROOT/src/CMD/DEFRAG/DEFRAG.EXE" ::DEFRAG.EXE
mcopy -o -i "$BOOT" "$QEXIT" ::QEXIT.COM
mcopy -o -i "$BOOT" "$MOUSE" ::MOUSE.COM
printf '@ECHO OFF\r\nCTTY AUX\r\nMOUSE.COM\r\nDEFRAG\r\nECHO DEFRAG_INTERACTIVE_RETURNED\r\nQEXIT.COM\r\n' |
    mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT

rm -f "$SERIAL_IN" "$SERIAL_OUT" "$LOG"
mkfifo "$SERIAL_IN" "$SERIAL_OUT"
exec 3<>"$SERIAL_IN"
timeout 30 qemu-system-i386 -display none -boot a -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET",cache=writethrough \
    -serial pipe:"$SERIAL_BASE" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 2>/dev/null &
QEMU_PID=$!
python3 "$ROOT/tests/serial_expect.py" \
    "$SERIAL_IN" "$SERIAL_OUT" "$LOG" \
    'Selected drive B:' '\r' \
    'Press ENTER to begin' '\r'
wait "$QEMU_PID" || true
exec 3>&-

for marker in \
    'Microsoft Defragmenter' 'Selected drive B:' \
    'Mouse navigation: available.' \
    'Recommended optimization: unfragment files.' \
    'Analyzing drive B:' 'Disk map before optimization:' \
    'Legend: # used  + mixed  . free' 'Analysis:' \
    'Optimizing drive B:' 'Disk map after optimization:' \
    'DEFRAG_INTERACTIVE_RETURNED'; do
    grep -Fq "$marker" "$LOG"
done
payload="$(mcopy -i "$TARGET" ::CONTROL.TXT - 2>/dev/null | tr -d '\r\n')"
[[ "$payload" == 'interactive defragmenter payload' ]]

CONFIG_SERIAL_BASE="$OUT/defrag-configure-serial"
CONFIG_SERIAL_IN="$CONFIG_SERIAL_BASE.in"
CONFIG_SERIAL_OUT="$CONFIG_SERIAL_BASE.out"
CONFIG_LOG="$OUT/defrag-configure.log"
printf '@ECHO OFF\r\nCTTY AUX\r\nDEFRAG\r\nECHO DEFRAG_CONFIGURE_RETURNED\r\nQEXIT.COM\r\n' |
    mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT
rm -f "$CONFIG_SERIAL_IN" "$CONFIG_SERIAL_OUT" "$CONFIG_LOG"
mkfifo "$CONFIG_SERIAL_IN" "$CONFIG_SERIAL_OUT"
exec 3<>"$CONFIG_SERIAL_IN"
timeout 30 qemu-system-i386 -display none -boot a -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET",cache=writethrough \
    -serial pipe:"$CONFIG_SERIAL_BASE" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 2>/dev/null &
QEMU_PID=$!
python3 "$ROOT/tests/serial_expect.py" \
    "$CONFIG_SERIAL_IN" "$CONFIG_SERIAL_OUT" "$CONFIG_LOG" \
    'Select a drive to optimize:' 'b' \
    'Selected drive B:' '\r' \
    'Press ENTER to begin' 'c' \
    'Optimize configuration' 'f' \
    'Current method: full compaction' '\r'
wait "$QEMU_PID" || true
exec 3>&-
grep -Fq 'Optimizing drive B: (full compaction' "$CONFIG_LOG"
grep -Fq 'Disk map progress: 1 move(s) completed.' "$CONFIG_LOG"
grep -Fq 'DEFRAG_CONFIGURE_RETURNED' "$CONFIG_LOG"
payload="$(mcopy -i "$TARGET" ::CONTROL.TXT - 2>/dev/null | tr -d '\r\n')"
[[ "$payload" == 'interactive defragmenter payload' ]]

echo '  PASS: Defrag mouse/keyboard selection, configuration, maps, and progress'
