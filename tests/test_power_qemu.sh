#!/bin/bash
set -euo pipefail
export LC_ALL=C MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/power.img"
MISSING_IMAGE="$OUT/power-missing.img"
APM_IMAGE="$OUT/power-apm.img"
LOG="$OUT/power.log"
MISSING_LOG="$OUT/power-missing.log"
APM_LOG="$OUT/power-apm.log"
PROBE="$OUT/power-probe.com"
APM_DRIVER="$OUT/apm-test.sys"
APM_PROBE="$OUT/power-apm-probe.com"
QEXIT="$OUT/power-qexit.com"

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null || { echo "ERROR: missing $tool" >&2; exit 1; }
done
cp "$BASE" "$IMAGE"
nasm -f bin "$ROOT/tests/power_probe.asm" -o "$PROBE"
nasm -f bin "$ROOT/tests/apm_test_driver.asm" -o "$APM_DRIVER"
nasm -f bin "$ROOT/tests/power_apm_probe.asm" -o "$APM_PROBE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
mcopy -o -i "$IMAGE" "$ROOT/src/CMD/POWER/POWER.EXE" ::POWER.EXE
mdel -i "$IMAGE" ::POWER.COM >/dev/null 2>&1 || true
mcopy -o -i "$IMAGE" "$PROBE" ::PWRPROBE.COM
mcopy -o -i "$IMAGE" "$QEXIT" ::QEXIT.COM
printf 'DEVICE=A:\\POWER.EXE\r\n' | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'POWER\r\nPOWER OFF\r\nPOWER\r\nPOWER STD\r\nPOWER\r\n'
    printf 'POWER ADV:MIN\r\nPOWER ADV:REG\r\nPOWER ADV:MAX\r\nPOWER\r\n'
    printf 'PWRPROBE.COM\r\n'
    printf 'POWER ADV:FAST\r\nIF ERRORLEVEL 1 ECHO POWER_REJECT_PASS\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

timeout 35 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$LOG" 2>&1 || true

grep -Fq 'Power Management Status' "$LOG"
grep -Fq 'Setting =  ADV: REG' "$LOG"
grep -Fq 'Setting =  OFF' "$LOG"
grep -Fq 'Setting =  STD' "$LOG"
grep -Fq 'Setting =  ADV: MAX' "$LOG"
grep -Eq 'CPU: idle [0-9]+% of time\.' "$LOG"
grep -Fq 'AC Line Status : ONLINE' "$LOG"
grep -Fq POWER_IDLE_PASS "$LOG"
grep -Fq 'Invalid parameter - adv:fast' "$LOG"
! grep -Fq POWER_REJECT_PASS "$LOG"
! grep -Fq POWER_IDLE_FAIL "$LOG"
echo '  PASS: POWER device, retail status, controller modes, and idle action'

cp "$BASE" "$MISSING_IMAGE"
mcopy -o -i "$MISSING_IMAGE" "$ROOT/src/CMD/POWER/POWER.EXE" ::POWER.EXE
mcopy -o -i "$MISSING_IMAGE" "$QEXIT" ::QEXIT.COM
printf '' | mcopy -o -i "$MISSING_IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\nCTTY AUX\r\nPOWER\r\n'
    printf 'IF ERRORLEVEL 2 ECHO POWER_MISSING_BAD_LEVEL\r\n'
    printf 'IF ERRORLEVEL 1 ECHO POWER_MISSING_LEVEL1\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$MISSING_IMAGE" - ::AUTOEXEC.BAT
timeout 25 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$MISSING_IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$MISSING_LOG" 2>&1 || true
grep -Fq 'Power Manager (POWER.EXE) not installed.' "$MISSING_LOG"
grep -Fq POWER_MISSING_LEVEL1 "$MISSING_LOG"
! grep -Fq POWER_MISSING_BAD_LEVEL "$MISSING_LOG"
echo '  PASS: POWER matches the retail missing-driver diagnostic and errorlevel'

cp "$BASE" "$APM_IMAGE"
mcopy -o -i "$APM_IMAGE" "$ROOT/src/CMD/POWER/POWER.EXE" ::POWER.EXE
mcopy -o -i "$APM_IMAGE" "$APM_DRIVER" ::APMTEST.SYS
mcopy -o -i "$APM_IMAGE" "$APM_PROBE" ::PWRAPM.COM
mcopy -o -i "$APM_IMAGE" "$QEXIT" ::QEXIT.COM
{
    printf 'DEVICE=A:\\APMTEST.SYS\r\n'
    printf 'DEVICE=A:\\POWER.EXE\r\n'
} | mcopy -o -i "$APM_IMAGE" - ::CONFIG.SYS
printf '@ECHO OFF\r\nCTTY AUX\r\nPWRAPM.COM\r\nQEXIT.COM\r\n' \
    | mcopy -o -i "$APM_IMAGE" - ::AUTOEXEC.BAT
timeout 25 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$APM_IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$APM_LOG" 2>&1 || true
grep -Fq POWER_APM_PASS "$APM_LOG"
! grep -Fq POWER_APM_FAIL "$APM_LOG"
echo '  PASS: POWER connects, enables, disables, re-enables, and idles through APM'
