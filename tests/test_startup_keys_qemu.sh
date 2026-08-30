#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
PROBE="$OUT/startup-key-numlock.com"

trap 'kill ${QEMU_PID:-} 2>/dev/null || true; rm -f "${QMP:-}"' EXIT
nasm -f bin "$ROOT/tests/config_numlock_probe.asm" -o "$PROBE"

boot_with_key() {
    local image=$1 key=$2 screen=$3
    shift 3
    QMP="$OUT/startup-$key-qmp.sock"
    rm -f "$QMP" "$screen"
    timeout 70 qemu-system-i386 -display none \
        -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
        -boot a -m 4 -qmp unix:"$QMP",server,nowait -no-reboot \
        >/dev/null 2>&1 &
    QEMU_PID=$!
    for _ in $(seq 1 30); do
        [[ -S "$QMP" ]] && break
        sleep 0.1
    done
    [[ -S "$QMP" ]]
    python3 "$ROOT/tests/send_qmp_key.py" "$QMP" "$key" 0.45
    python3 "$ROOT/tests/screen_expect.py" "$QMP" "$screen" "$@"
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
    QEMU_PID=
    rm -f "$QMP"
}

F5_IMAGE="$OUT/startup-f5.img"
F5_SCREEN="$OUT/startup-f5-screen.log"
cp "$BASE" "$F5_IMAGE"
printf 'NUMLOCK=ON\r\n' | mcopy -o -i "$F5_IMAGE" - ::CONFIG.SYS
printf '@ECHO OFF\r\nECHO RAN>AUTOEXEC.RAN\r\n' | \
    mcopy -o -i "$F5_IMAGE" - ::AUTOEXEC.BAT
mcopy -o -i "$F5_IMAGE" "$PROBE" ::NLPROBE.COM
boot_with_key "$F5_IMAGE" f5 "$F5_SCREEN" \
    'A>' 'n+l+p+r+o+b+e+dot+c+o+m+ret' \
    'NUMLOCK=OFF' ''
! mdir -i "$F5_IMAGE" ::AUTOEXEC.RAN >/dev/null 2>&1

SHIFT_IMAGE="$OUT/startup-shift.img"
SHIFT_SCREEN="$OUT/startup-shift-screen.log"
cp "$BASE" "$SHIFT_IMAGE"
printf 'NUMLOCK=ON\r\n' | mcopy -o -i "$SHIFT_IMAGE" - ::CONFIG.SYS
printf '@ECHO OFF\r\nECHO RAN>AUTOEXEC.RAN\r\n' | \
    mcopy -o -i "$SHIFT_IMAGE" - ::AUTOEXEC.BAT
mcopy -o -i "$SHIFT_IMAGE" "$PROBE" ::NLPROBE.COM
boot_with_key "$SHIFT_IMAGE" shift "$SHIFT_SCREEN" \
    'A>' 'n+l+p+r+o+b+e+dot+c+o+m+ret' \
    'NUMLOCK=OFF' ''
! mdir -i "$SHIFT_IMAGE" ::AUTOEXEC.RAN >/dev/null 2>&1

F8_IMAGE="$OUT/startup-f8.img"
F8_SCREEN="$OUT/startup-f8-screen.log"
cp "$BASE" "$F8_IMAGE"
{
    printf 'NUMLOCK=ON\r\n'
    printf 'SET CFGSTEP=YES\r\n'
} | mcopy -o -i "$F8_IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'ECHO %%CFGSTEP%%>CFGSTEP.TXT\r\n'
    printf 'ECHO FIRST>FIRST.TXT\r\n'
    printf 'ECHO SECOND>SECOND.TXT\r\n'
} | mcopy -o -i "$F8_IMAGE" - ::AUTOEXEC.BAT
mcopy -o -i "$F8_IMAGE" "$PROBE" ::NLPROBE.COM
boot_with_key "$F8_IMAGE" f8 "$F8_SCREEN" \
    'Process next CONFIG.SYS line? [Y,N]' 'n' \
    'Process next CONFIG.SYS line? [Y,N]' 'y' \
    'Process line? [Y,N]' 'y+y+y+n' \
    'A>' 'n+l+p+r+o+b+e+dot+c+o+m+ret' \
    'NUMLOCK=OFF' ''
mtype -i "$F8_IMAGE" ::CFGSTEP.TXT | grep -Fq YES
mtype -i "$F8_IMAGE" ::FIRST.TXT | grep -Fq FIRST
! mdir -i "$F8_IMAGE" ::SECOND.TXT >/dev/null 2>&1

echo '  PASS: F5/Shift bypass startup files and F8 confirms CONFIG/AUTOEXEC lines'
