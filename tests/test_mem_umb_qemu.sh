#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
FLOPPY="$OUT/floppy.img"
HIMEM="$OUT/mem-umb-himem.sys"
STATE="$OUT/mem-umb-state.com"
QEXIT="$OUT/mem-umb-exit.com"

for tool in mcopy nasm qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done

"$ROOT/bin/jwasm-bin" -Fo"$HIMEM" \
    "$ROOT/MS-DOS/v4.0/src/DEV/HIMEM/HIMEM.ASM"
nasm -f bin "$ROOT/tests/loadhigh_state.asm" -o "$STATE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"

run_image() {
    local image=$1
    local log=$2

    timeout 35 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 16 \
        -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        >"$log" 2>&1 || true
}

IMAGE="$OUT/mem-umb.img"
LOG="$OUT/mem-umb.log"
cp "$FLOPPY" "$IMAGE"
mcopy -o -i "$IMAGE" "$HIMEM" ::HIMEM.SYS
mcopy -o -i "$IMAGE" "$ROOT/MS-DOS/v4.0/src/MEMM/MEMM/EMM386.SYS" ::EMM386.SYS
mcopy -o -i "$IMAGE" "$STATE" ::STATE.COM
mcopy -o -i "$IMAGE" "$QEXIT" ::QEXIT.COM
{
    printf 'DEVICE=HIMEM.SYS\r\n'
    printf 'DEVICE=EMM386.SYS NOEMS X=D000-D7FF\r\n'
    printf 'DOS=HIGH,UMB\r\n'
} | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'ECHO MEM_SUMMARY_BEGIN\r\nMEM\r\n'
    printf 'ECHO MEM_CLASSIFY_BEGIN\r\nMEM /c\r\n'
    printf 'ECHO MEM_DEBUG_BEGIN\r\nMEM /D\r\n'
    printf 'ECHO MEM_FREE_BEGIN\r\nMEM /F\r\n'
    printf 'ECHO MEM_MODULE_BEGIN\r\nMEM /M COMMAND\r\n'
    printf 'ECHO MEM_DRIVER_MODULE_BEGIN\r\nMEM /M HIMEM\r\n'
    printf 'MEM /CLASSIFY > NUL\r\nIF ERRORLEVEL 1 ECHO MEM_SYNONYM_FAIL\r\n'
    printf 'MEM /FREE > NUL\r\nIF ERRORLEVEL 1 ECHO MEM_SYNONYM_FAIL\r\n'
    printf 'MEM /MODULE COMMAND > NUL\r\nIF ERRORLEVEL 1 ECHO MEM_SYNONYM_FAIL\r\n'
    printf 'MEM /M:COMMAND > NUL\r\nIF ERRORLEVEL 1 ECHO MEM_SYNONYM_FAIL\r\n'
    printf 'MEM /MODULE:COMMAND > NUL\r\nIF ERRORLEVEL 1 ECHO MEM_SYNONYM_FAIL\r\n'
    printf 'MEM /M MISSING\r\n'
    printf 'IF ERRORLEVEL 1 ECHO MEM_MISSING_PASS\r\n'
    printf 'STATE.COM\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT
run_image "$IMAGE" "$LOG"

for expected in \
    MEM_SUMMARY_BEGIN MEM_CLASSIFY_BEGIN MEM_DEBUG_BEGIN MEM_FREE_BEGIN \
    MEM_MODULE_BEGIN MEM_DRIVER_MODULE_BEGIN 'Modules using memory below 1 MB:' \
    'Memory Summary:' 'Largest free upper memory block' \
    'MS-DOS is resident in the high memory area.' \
    'Free Conventional Memory:' 'Free Upper Memory:' \
    'COMMAND is using the following memory:' \
    'HIMEM is using the following memory:' 'MEM_MISSING_PASS' 'LINK=0000'
do
    if ! grep -Fq "$expected" "$LOG"; then
        echo "FAIL: MEM UMB output missing: $expected" >&2
        strings -a "$LOG" | sed -n '1,260p' >&2
        exit 1
    fi
done

if grep -Fq 'MEM_SYNONYM_FAIL' "$LOG"; then
    echo 'FAIL: a MEM long or compact switch synonym failed' >&2
    strings -a "$LOG" | sed -n '1,260p' >&2
    exit 1
fi

if ! grep -Eq '^  Upper +81920 +' "$LOG" \
    || ! grep -Eq '^  HIMEM +[1-9][0-9]* +[1-9][0-9]* +0' "$LOG" \
    || ! grep -Eq '^  EMM386 +[1-9][0-9]* +[1-9][0-9]* +0' "$LOG" \
    || ! grep -Eq '^  Free +[1-9][0-9]* +[1-9][0-9]* +[1-9][0-9]*' "$LOG" \
    || ! grep -Eq '^ +1 +16352 +16352 +16384' "$LOG" \
    || ! grep -Eq '^ +2 +65520 +65520 +65536' "$LOG" \
    || ! grep -Eq '^  CC00:0000 +FREE +16352 +Free +1' "$LOG" \
    || ! grep -Eq '^  CFFF:0000 +SYSTEM +32768 +System +1' "$LOG" \
    || ! grep -Eq '^  D800:0000 +FREE +65520 +Free +2' "$LOG"
then
    echo 'FAIL: MEM did not preserve exact split UMB region accounting' >&2
    strings -a "$LOG" | sed -n '1,260p' >&2
    exit 1
fi

IMAGE="$OUT/mem-no-umb.img"
LOG="$OUT/mem-no-umb.log"
cp "$FLOPPY" "$IMAGE"
mcopy -o -i "$IMAGE" "$STATE" ::STATE.COM
mcopy -o -i "$IMAGE" "$QEXIT" ::QEXIT.COM
printf 'DOS=UMB\r\n' | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\nCTTY AUX\r\nMEM\r\nSTATE.COM\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT
run_image "$IMAGE" "$LOG"

if ! grep -Eq '^  Upper +0 +0 +0' "$LOG" \
    || ! grep -Fq 'The high memory area is available.' "$LOG" \
    || ! grep -Fq 'LINK=0000' "$LOG"
then
    echo 'FAIL: MEM no-provider diagnostics or link restoration' >&2
    strings -a "$LOG" | sed -n '1,180p' >&2
    exit 1
fi

echo '  PASS: MEM UMB summary, /C, /D, /F, /M, regions, HMA, and state restoration'
