#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/command-step.img"
QMP="$OUT/command-step-qmp.sock"
SCREEN="$OUT/command-step-screen.log"

trap 'kill ${QEMU_PID:-} 2>/dev/null || true; rm -f "$QMP"' EXIT
cp "$BASE" "$IMAGE"
printf 'ECHO ONE>ONE.TXT\r\nECHO SKIP>SKIP.TXT\r\nECHO THREE>THREE.TXT\r\n' | \
    mcopy -o -i "$IMAGE" - ::STEP.BAT
printf '@ECHO OFF\r\nCOMMAND /Y /C STEP.BAT\r\nECHO STEP_DONE\r\n' | \
    mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

rm -f "$QMP" "$SCREEN"
timeout 60 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -m 4 -qmp unix:"$QMP",server,nowait -no-reboot \
    >/dev/null 2>&1 &
QEMU_PID=$!
for _ in $(seq 1 20); do
    [[ -S "$QMP" ]] && break
    sleep 0.2
done
[[ -S "$QMP" ]]

python3 "$ROOT/tests/screen_expect.py" "$QMP" "$SCREEN" \
    'Process line? [Y,N]' 'y+n+y' \
    'STEP_DONE' ''

kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=

mtype -i "$IMAGE" ::ONE.TXT | grep -Fq ONE
! mdir -i "$IMAGE" ::SKIP.TXT >/dev/null 2>&1
mtype -i "$IMAGE" ::THREE.TXT | grep -Fq THREE
echo '  PASS: COMMAND /Y selectively executes /C batch lines'
