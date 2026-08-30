#!/bin/bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
SERVER_IMAGE="$OUT/intersvr.img"
SERVER_IMAGE_TWO="$OUT/intersvr-two.img"
CLIENT_IMAGE="$OUT/interlnk.img"
DISCONNECTED_IMAGE="$OUT/interlnk-disconnected.img"
AUTO_IMAGE="$OUT/interlnk-auto.img"
SHUTDOWN_IMAGE="$OUT/intersvr-shutdown.img"
LOG="$OUT/interlnk-debug.log"
SERVER_LOG="$OUT/intersvr-qemu.log"
CLIENT_LOG="$OUT/interlnk-qemu.log"
DISCONNECTED_LOG="$OUT/interlnk-disconnected.log"
AUTO_LOG="$OUT/interlnk-auto.log"
PROBE="$OUT/ILPROBE.COM"
QEXIT="$OUT/interlnk-qexit.com"
ALT_F4="$OUT/alt-f4.com"
OFFLINE_PROBE="$OUT/interlnk-offline.com"
OFFLINE_CONTINUE="$OUT/interlnk-offline-continue.com"
AUTO_PROBE="$OUT/interlnk-auto.com"
PORT=18666
PROXY_PORT=18667
PRINTER_OUT="$OUT/intersvr-printer.out"

for tool in nasm mcopy python3 qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || { echo "missing required tool: $tool" >&2; exit 1; }
done
[[ -f "$BASE" ]] || { echo 'run make deploy first' >&2; exit 1; }

nasm -f bin "$ROOT/tests/interlnk_file_probe.asm" -o "$PROBE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
nasm -f bin "$ROOT/tests/alt_f4_inject.asm" -o "$ALT_F4"
nasm -DEXPECT_INSTALLED -DEXPECT_PRINTER_OFF -f bin \
    "$ROOT/tests/interlnk_offline_probe.asm" -o "$OFFLINE_PROBE"
nasm -DEXPECT_INSTALLED -DDO_RECONNECT -DNO_QEMU_EXIT -f bin "$ROOT/tests/interlnk_offline_probe.asm" -o "$OFFLINE_CONTINUE"
nasm -f bin "$ROOT/tests/interlnk_offline_probe.asm" -o "$AUTO_PROBE"
cp "$BASE" "$SERVER_IMAGE"
cp "$BASE" "$CLIENT_IMAGE"
mformat -C -i "$SERVER_IMAGE_TWO" -f 1440 ::
printf 'Byte-exact Interlnk transport\r\n' | mcopy -o -i "$SERVER_IMAGE" - ::REMOTE.TXT
printf 'Second Interlnk volume\r\n' | mcopy -o -i "$SERVER_IMAGE_TWO" - ::REMOTE2.TXT
mcopy -o -i "$SERVER_IMAGE" "$ROOT/src/CMD/INTERSVR/INTERSVR.EXE" ::INTERSVR.EXE
printf '@ECHO OFF\r\nINTERSVR /X=C: /B /V /BAUD:57600 /COM:2\r\n' | mcopy -o -i "$SERVER_IMAGE" - ::AUTOEXEC.BAT
printf '\r\n' | mcopy -o -i "$SERVER_IMAGE" - ::CONFIG.SYS

mcopy -o -i "$CLIENT_IMAGE" "$ROOT/src/CMD/INTERLNK/INTERLNK.EXE" ::INTERLNK.EXE
mcopy -o -i "$CLIENT_IMAGE" "$PROBE" ::ILPROBE.COM
mcopy -o -i "$CLIENT_IMAGE" "$OFFLINE_CONTINUE" ::OFFLINE.COM
mcopy -o -i "$CLIENT_IMAGE" "$QEXIT" ::QEXIT.COM
printf 'LASTDRIVE=Z\r\nDEVICE=A:\\INTERLNK.EXE /DRIVES:2 /NOSCAN /BAUD:57600\r\n' | mcopy -o -i "$CLIENT_IMAGE" - ::CONFIG.SYS
printf '@ECHO OFF\r\nOFFLINE.COM\r\nIF ERRORLEVEL 1 ECHO failed>RECONERR.TAG\r\nINTERLNK /RECONNECT\r\nIF ERRORLEVEL 1 ECHO failed>RECONERR.TAG\r\nILPROBE.COM\r\nQEXIT.COM\r\n' | mcopy -o -i "$CLIENT_IMAGE" - ::AUTOEXEC.BAT

rm -f "$LOG" "$SERVER_LOG" "$CLIENT_LOG" "$PRINTER_OUT"
timeout 60 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=floppy,index=0,format=raw,file="$SERVER_IMAGE",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$SERVER_IMAGE_TWO",cache=writethrough \
    -boot a -serial null -serial tcp:127.0.0.1:$PORT,server=on,wait=off \
    -parallel file:"$PRINTER_OUT" -no-reboot \
    >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
PROXY_PID=
trap 'kill "$PROXY_PID" "$SERVER_PID" 2>/dev/null || true; wait "$PROXY_PID" "$SERVER_PID" 2>/dev/null || true' EXIT
sleep 2
python3 "$ROOT/tests/serial_fault_proxy.py" \
    --listen "$PROXY_PORT" --upstream "$PORT" --inject a5 --corrupt-request 4 \
    --truncate-sector 2 --corrupt-sector 4 --truncate-write 1 --corrupt-write 4 \
    >"$OUT/interlnk-proxy.log" 2>&1 &
PROXY_PID=$!
sleep 1

timeout 90 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=floppy,index=0,format=raw,file="$CLIENT_IMAGE",cache=writethrough \
    -boot a -serial null -serial tcp:127.0.0.1:$PROXY_PORT -debugcon file:"$LOG" -global isa-debugcon.iobase=0xe9 \
    -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$CLIENT_LOG" 2>&1 || true

grep -Fq 'INTERLNK_TRANSPORT_PASS' "$LOG" || {
    echo 'Interlnk remote filesystem probe failed' >&2
    cat "$LOG" >&2
    cat "$SERVER_LOG" >&2
    cat "$CLIENT_LOG" >&2
    exit 1
}
grep -Fq 'truncated sector response 2' "$OUT/interlnk-proxy.log"
grep -Fq 'corrupted sector response 4' "$OUT/interlnk-proxy.log"
[[ $(grep -Fc 'retried read sector' "$OUT/interlnk-proxy.log") -eq 2 ]]
grep -Fq 'corrupted request header 4' "$OUT/interlnk-proxy.log"
grep -Fq 'truncated write payload 1' "$OUT/interlnk-proxy.log"
grep -Fq 'corrupted write payload 4' "$OUT/interlnk-proxy.log"
! mdir -b -i "$CLIENT_IMAGE" :: 2>/dev/null | grep -Fq 'RECONERR.TAG'
mcopy -i "$SERVER_IMAGE" ::WRITTEN.BIN - 2>/dev/null | od -An -tx1 | tr -d ' \n' | grep -qx '001122334455aaff'
mcopy -i "$SERVER_IMAGE_TWO" ::WRITTN2.BIN - 2>/dev/null | od -An -tx1 | tr -d ' \n' | grep -qx 'fedcba9876543210'
od -An -tx1 "$PRINTER_OUT" | tr -d ' \n' | grep -qx '50'
echo '  PASS: Interlnk redirects two FAT volumes and LPT1 while recovering truncated/corrupt serial transfers'

# Without /AUTO, a missing server leaves an offline resident driver and must
# continue boot instead of waiting forever in the serial receive loop.
cp "$BASE" "$DISCONNECTED_IMAGE"
mcopy -o -i "$DISCONNECTED_IMAGE" "$ROOT/src/CMD/INTERLNK/INTERLNK.EXE" ::INTERLNK.EXE
mcopy -o -i "$DISCONNECTED_IMAGE" "$OFFLINE_PROBE" ::OFFLINE.COM
printf 'LASTDRIVE=Z\r\nDEVICE=A:\\INTERLNK.EXE /DRIVES:2 /COM:1 /NOPRINTER /V\r\n' | mcopy -o -i "$DISCONNECTED_IMAGE" - ::CONFIG.SYS
printf '@ECHO OFF\r\nOFFLINE.COM\r\n' | mcopy -o -i "$DISCONNECTED_IMAGE" - ::AUTOEXEC.BAT
rm -f "$DISCONNECTED_LOG"
set +e
timeout 15 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=floppy,index=0,format=raw,file="$DISCONNECTED_IMAGE",cache=writethrough \
    -boot a -serial null -debugcon file:"$DISCONNECTED_LOG" -global isa-debugcon.iobase=0xe9 \
    -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >/dev/null 2>&1
DISCONNECTED_RC=$?
set -e
[[ $DISCONNECTED_RC -ne 124 ]]
grep -Fq 'INTERLNK_OFFLINE_PASS' "$DISCONNECTED_LOG"
echo '  PASS: Interlnk remains installed offline and /NOPRINTER suppresses its printer hook'

# /AUTO retains the historical opt-in behavior of declining installation when
# no server can be found during CONFIG.SYS processing.
cp "$BASE" "$AUTO_IMAGE"
mcopy -o -i "$AUTO_IMAGE" "$ROOT/src/CMD/INTERLNK/INTERLNK.EXE" ::INTERLNK.EXE
mcopy -o -i "$AUTO_IMAGE" "$AUTO_PROBE" ::AUTOPRB.COM
printf 'LASTDRIVE=Z\r\nDEVICE=A:\\INTERLNK.EXE /DRIVES:2 /COM:1 /AUTO\r\n' | mcopy -o -i "$AUTO_IMAGE" - ::CONFIG.SYS
printf '@ECHO OFF\r\nAUTOPRB.COM\r\n' | mcopy -o -i "$AUTO_IMAGE" - ::AUTOEXEC.BAT
rm -f "$AUTO_LOG"
timeout 15 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=floppy,index=0,format=raw,file="$AUTO_IMAGE",cache=writethrough \
    -boot a -serial null -debugcon file:"$AUTO_LOG" -global isa-debugcon.iobase=0xe9 \
    -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >/dev/null 2>&1 || true
grep -Fq 'INTERLNK_OFFLINE_PASS' "$AUTO_LOG"
echo '  PASS: Interlnk /AUTO declines installation without a server'

# The interactive server must consume Alt+F4 and return to its caller.
cp "$BASE" "$SHUTDOWN_IMAGE"
mcopy -o -i "$SHUTDOWN_IMAGE" "$ROOT/src/CMD/INTERSVR/INTERSVR.EXE" ::INTERSVR.EXE
mcopy -o -i "$SHUTDOWN_IMAGE" "$ALT_F4" ::ALTF4.COM
mcopy -o -i "$SHUTDOWN_IMAGE" "$QEXIT" ::QEXIT.COM
printf '\r\n' | mcopy -o -i "$SHUTDOWN_IMAGE" - ::CONFIG.SYS
printf '@ECHO OFF\r\nALTF4.COM\r\nINTERSVR A: /COM:2\r\nECHO PASS>ALTF4.TAG\r\nQEXIT.COM\r\n' \
    | mcopy -o -i "$SHUTDOWN_IMAGE" - ::AUTOEXEC.BAT
timeout 15 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=floppy,index=0,format=raw,file="$SHUTDOWN_IMAGE",cache=writethrough \
    -boot a -serial null -serial null -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >/dev/null 2>&1 || true
mcopy -i "$SHUTDOWN_IMAGE" ::ALTF4.TAG - 2>/dev/null | grep -Fq PASS
echo '  PASS: Interserver Alt+F4 shutdown returns control to DOS'
