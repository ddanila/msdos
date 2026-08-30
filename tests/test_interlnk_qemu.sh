#!/bin/bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
SERVER_IMAGE="$OUT/intersvr.img"
SERVER_IMAGE_TWO="$OUT/intersvr-two.img"
CLIENT_IMAGE="$OUT/interlnk.img"
LOG="$OUT/interlnk-debug.log"
SERVER_LOG="$OUT/intersvr-qemu.log"
CLIENT_LOG="$OUT/interlnk-qemu.log"
PROBE="$OUT/ILPROBE.COM"
QEXIT="$OUT/interlnk-qexit.com"
PORT=18666

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || { echo "missing required tool: $tool" >&2; exit 1; }
done
[[ -f "$BASE" ]] || { echo 'run make deploy first' >&2; exit 1; }

nasm -f bin "$ROOT/tests/interlnk_file_probe.asm" -o "$PROBE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
cp "$BASE" "$SERVER_IMAGE"
cp "$BASE" "$CLIENT_IMAGE"
mformat -C -i "$SERVER_IMAGE_TWO" -f 1440 ::
printf 'Byte-exact Interlnk transport\r\n' | mcopy -o -i "$SERVER_IMAGE" - ::REMOTE.TXT
printf 'Second Interlnk volume\r\n' | mcopy -o -i "$SERVER_IMAGE_TWO" - ::REMOTE2.TXT
mcopy -o -i "$SERVER_IMAGE" "$ROOT/src/CMD/INTERSVR/INTERSVR.EXE" ::INTERSVR.EXE
printf '@ECHO OFF\r\nINTERSVR A: B: /COM:1\r\n' | mcopy -o -i "$SERVER_IMAGE" - ::AUTOEXEC.BAT
printf '\r\n' | mcopy -o -i "$SERVER_IMAGE" - ::CONFIG.SYS

mcopy -o -i "$CLIENT_IMAGE" "$ROOT/src/CMD/INTERLNK/INTERLNK.EXE" ::INTERLNK.EXE
mcopy -o -i "$CLIENT_IMAGE" "$PROBE" ::ILPROBE.COM
mcopy -o -i "$CLIENT_IMAGE" "$QEXIT" ::QEXIT.COM
printf 'LASTDRIVE=Z\r\nDEVICE=A:\\INTERLNK.EXE\r\n' | mcopy -o -i "$CLIENT_IMAGE" - ::CONFIG.SYS
printf '@ECHO OFF\r\nILPROBE.COM\r\nQEXIT.COM\r\n' | mcopy -o -i "$CLIENT_IMAGE" - ::AUTOEXEC.BAT

rm -f "$LOG" "$SERVER_LOG" "$CLIENT_LOG"
timeout 60 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=floppy,index=0,format=raw,file="$SERVER_IMAGE",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$SERVER_IMAGE_TWO",cache=writethrough \
    -boot a -serial tcp:127.0.0.1:$PORT,server=on,wait=off -no-reboot \
    >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true' EXIT
sleep 2

timeout 45 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=floppy,index=0,format=raw,file="$CLIENT_IMAGE",cache=writethrough \
    -boot a -serial tcp:127.0.0.1:$PORT -debugcon file:"$LOG" -global isa-debugcon.iobase=0xe9 \
    -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$CLIENT_LOG" 2>&1 || true

grep -Fq 'INTERLNK_TRANSPORT_PASS' "$LOG" || {
    echo 'Interlnk remote filesystem probe failed' >&2
    cat "$LOG" >&2
    cat "$SERVER_LOG" >&2
    cat "$CLIENT_LOG" >&2
    exit 1
}
mcopy -i "$SERVER_IMAGE" ::WRITTEN.BIN - 2>/dev/null | od -An -tx1 | tr -d ' \n' | grep -qx '001122334455aaff'
mcopy -i "$SERVER_IMAGE_TWO" ::WRITTN2.BIN - 2>/dev/null | od -An -tx1 | tr -d ' \n' | grep -qx 'fedcba9876543210'
echo '  PASS: Interlnk redirects two FAT volumes with byte-exact reads and writes over COM1'
