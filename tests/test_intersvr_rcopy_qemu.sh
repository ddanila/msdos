#!/bin/bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
REMOTE_IMAGE="$OUT/intersvr-rcopy-remote.img"
SERVER_IMAGE="$OUT/intersvr-rcopy-server.img"
REMOTE_LOG="$OUT/intersvr-rcopy-remote.log"
SERVER_LOG="$OUT/intersvr-rcopy-server.log"
QEXIT="$OUT/intersvr-rcopy-qexit.com"
PORT=18668

for tool in cmp mcopy mdel nasm qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || { echo "missing required tool: $tool" >&2; exit 1; }
done
[[ -f "$BASE" ]] || { echo 'run make deploy first' >&2; exit 1; }

nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
cp "$BASE" "$REMOTE_IMAGE"
cp "$BASE" "$SERVER_IMAGE"
mdel -i "$REMOTE_IMAGE" ::INTERLNK.EXE ::INTERSVR.EXE
printf '\r\n' | mcopy -o -i "$REMOTE_IMAGE" - ::CONFIG.SYS
printf '@ECHO OFF\r\nMODE COM1:9600,N,8,1,P\r\nCTTY COM1\r\n' \
    | mcopy -o -i "$REMOTE_IMAGE" - ::AUTOEXEC.BAT

mcopy -o -i "$SERVER_IMAGE" "$ROOT/src/CMD/INTERLNK/INTERLNK.EXE" ::INTERLNK.EXE
mcopy -o -i "$SERVER_IMAGE" "$ROOT/src/CMD/INTERSVR/INTERSVR.EXE" ::INTERSVR.EXE
mcopy -o -i "$SERVER_IMAGE" "$QEXIT" ::QEXIT.COM
printf '\r\n' | mcopy -o -i "$SERVER_IMAGE" - ::CONFIG.SYS
printf '@ECHO OFF\r\nINTERSVR /RCOPY /COM:1 /BAUD:9600 >RCOPY.TXT\r\nECHO PASS>RCOPY.TAG\r\nQEXIT.COM\r\n' \
    | mcopy -o -i "$SERVER_IMAGE" - ::AUTOEXEC.BAT

rm -f "$REMOTE_LOG" "$SERVER_LOG"
timeout 150 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=floppy,index=0,format=raw,file="$REMOTE_IMAGE",cache=writethrough \
    -boot a -serial tcp:127.0.0.1:$PORT,server=on,wait=off -no-reboot \
    >"$REMOTE_LOG" 2>&1 &
REMOTE_PID=$!
trap 'kill "$REMOTE_PID" 2>/dev/null || true; wait "$REMOTE_PID" 2>/dev/null || true' EXIT
# Let the remote system finish floppy boot, MODE, and CTTY before the server
# emits the first bootstrap command; the serial protocol has no pre-FXB ACK.
sleep 8

timeout 150 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=floppy,index=0,format=raw,file="$SERVER_IMAGE",cache=writethrough \
    -boot a -serial tcp:127.0.0.1:$PORT -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$SERVER_LOG" 2>&1 || true
sleep 2
kill "$REMOTE_PID" 2>/dev/null || true
wait "$REMOTE_PID" 2>/dev/null || true
trap - EXIT

mcopy -i "$SERVER_IMAGE" ::RCOPY.TAG - 2>/dev/null | grep -Fq PASS
mcopy -i "$REMOTE_IMAGE" ::INTERLNK.EXE "$OUT/rcopy-interlnk.exe"
mcopy -i "$REMOTE_IMAGE" ::INTERSVR.EXE "$OUT/rcopy-intersvr.exe"
cmp "$ROOT/src/CMD/INTERLNK/INTERLNK.EXE" "$OUT/rcopy-interlnk.exe"
cmp "$ROOT/src/CMD/INTERSVR/INTERSVR.EXE" "$OUT/rcopy-intersvr.exe"
if mdir -i "$REMOTE_IMAGE" ::FXB.COM >/dev/null 2>&1; then
    echo 'temporary FXB.COM was not removed' >&2
    exit 1
fi
echo '  PASS: Interserver /RCOPY bootstraps byte-exact Interlnk files'
