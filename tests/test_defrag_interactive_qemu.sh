#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT="$OUT/defrag-interactive-boot.img"
TARGET="$OUT/defrag-interactive-target.img"
QEXIT="$OUT/defrag-interactive-qexit.com"
SERIAL_BASE="$OUT/defrag-interactive-serial"
SERIAL_IN="$SERIAL_BASE.in"
SERIAL_OUT="$SERIAL_BASE.out"
LOG="$OUT/defrag-interactive.log"

cp "$BASE" "$BOOT"
dd if=/dev/zero of="$TARGET" bs=512 count=2880 status=none
mformat -i "$TARGET" -f 1440 ::
printf 'interactive defragmenter payload\r\n' |
    mcopy -o -i "$TARGET" - ::CONTROL.TXT
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
mcopy -o -i "$BOOT" "$ROOT/src/CMD/DEFRAG/DEFRAG.EXE" ::DEFRAG.EXE
mcopy -o -i "$BOOT" "$QEXIT" ::QEXIT.COM
printf '@ECHO OFF\r\nCTTY AUX\r\nDEFRAG\r\nECHO DEFRAG_INTERACTIVE_RETURNED\r\nQEXIT.COM\r\n' |
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
    'Select a drive to optimize:' 'b' \
    'Selected drive B:' '\r' \
    'Press ENTER to begin' '\r'
wait "$QEMU_PID" || true
exec 3>&-

for marker in \
    'Microsoft Defragmenter' 'Selected drive B:' \
    'Recommended optimization: unfragment files.' \
    'Analyzing drive B:' 'Optimizing drive B:' 'DEFRAG_INTERACTIVE_RETURNED'; do
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
grep -Fq 'DEFRAG_CONFIGURE_RETURNED' "$CONFIG_LOG"
payload="$(mcopy -i "$TARGET" ::CONTROL.TXT - 2>/dev/null | tr -d '\r\n')"
[[ "$payload" == 'interactive defragmenter payload' ]]

echo '  PASS: Defrag full-screen selection, recommendation, confirmation, and configuration'
