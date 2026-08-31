#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/power-api.img"
LOG="$OUT/power-api.log"
PROBE="$OUT/power-api.com"
QEXIT="$OUT/power-api-exit.com"

for tool in mcopy nasm qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done
[[ -f "$BASE" ]] || { echo "ERROR: run make deploy first" >&2; exit 1; }

cp "$BASE" "$IMAGE"
nasm -f bin "$ROOT/tests/power_api_probe.asm" -o "$PROBE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
mcopy -o -i "$IMAGE" "$ROOT/src/CMD/POWER/POWER.EXE" ::POWER.EXE
mcopy -o -i "$IMAGE" "$PROBE" ::PWRAPI.COM
mcopy -o -i "$IMAGE" "$QEXIT" ::QEXIT.COM
printf 'DEVICE=A:\\POWER.EXE\r\n' | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
printf '@ECHO OFF\r\nCTTY AUX\r\nPWRAPI.COM\r\nQEXIT.COM\r\n' \
    | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

timeout 25 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$LOG" 2>&1 || true

for expected in \
    'INSTALL AX/BX=0100 504D' \
    'SET AX/BX=0000 0300' 'QUERY AX/BX=0000 0000' \
    'SET AX/BX=0000 0001' 'QUERY AX/BX=0000 0101' \
    'SET AX/BX=0000 0102' 'QUERY AX/BX=0000 0202' \
    'SET AX/BX=0000 0203' 'QUERY AX/BX=0000 0303' \
    'LEVEL_QUERY AX/BX=0000 0006' 'STATS AX/BX=0000 0000' \
    'STATS_DATA=0001 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000' \
    'POWER_API_DONE'
do
    grep -Fq "$expected" "$LOG" || {
        echo "FAIL: POWER retail API mismatch: $expected" >&2
        strings -a "$LOG" | sed -n '1,180p' >&2
        exit 1
    }
done

echo '  PASS: POWER matches the DOS 6.22 INT 2Fh 54xx API identity and core calls'
