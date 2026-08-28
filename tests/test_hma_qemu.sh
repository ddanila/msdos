#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
FLOPPY="$OUT/floppy.img"
HIMEM="$OUT/HIMEM.SYS"
PROBE="$OUT/hma-reference.com"
A20_DRIVER="$OUT/hma-a20.sys"
SYSTEM_PROBE="$OUT/hma-i21system.com"
FILE_MEMORY_PROBE="$OUT/hma-i21fmem.com"

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done

[[ -f "$FLOPPY" ]] || {
    echo "ERROR: missing build artifact: $FLOPPY" >&2
    exit 1
}

"$ROOT/bin/jwasm-bin" -Fo"$HIMEM" \
    "$ROOT/MS-DOS/v4.0/src/DEV/HIMEM/HIMEM.ASM"
nasm -f bin "$ROOT/tests/hma_reference_probe.asm" -o "$PROBE"
nasm -f bin "$ROOT/tests/hma_a20_driver.asm" -o "$A20_DRIVER"
nasm -f bin "$ROOT/tests/int21_system_probe.asm" -o "$SYSTEM_PROBE"
nasm -f bin "$ROOT/tests/int21_file_memory_probe.asm" -o "$FILE_MEMORY_PROBE"

run_case() {
    local mode=$1
    local mode_lc
    mode_lc=$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')
    local image="$OUT/floppy-hma-$mode_lc.img"
    local log="$OUT/hma-$mode_lc.log"

    cp "$FLOPPY" "$image"
    mcopy -o -i "$image" "$HIMEM" ::HIMEM.SYS
    mcopy -o -i "$image" "$A20_DRIVER" ::A20OFF.SYS
    mcopy -o -i "$image" "$PROBE" ::HMAREF.COM
    mcopy -o -i "$image" "$SYSTEM_PROBE" ::I21SYS.COM
    mcopy -o -i "$image" "$FILE_MEMORY_PROBE" ::I21FMEM.COM
    {
        printf 'DEVICE=A:\\HIMEM.SYS\r\n'
        if [[ "$mode" == HIGH ]]; then
            printf 'DEVICE=A:\\A20OFF.SYS\r\n'
        fi
        printf 'DOS=%s\r\n' "$mode"
        printf 'FILES=12\r\n'
    } | mcopy -o -i "$image" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\n'
        printf 'CTTY AUX\r\n'
        if [[ "$mode" == HIGH ]]; then
            printf 'ECHO A20_BOUNDARY>A20OFF$\r\n'
            printf 'ECHO A20_DRIVER_RETURNED\r\n'
            printf 'ECHO HMA_PROBE_BEFORE_STRESS\r\n'
            printf 'A:\\HMAREF.COM\r\n'
            printf 'I21FMEM.COM\r\n'
            printf 'I21SYS.COM\r\n'
            printf 'ECHO HMA_PROBE_AFTER_STRESS\r\n'
        fi
        printf 'DIR A:\\HMAREF.COM\r\n'
        printf 'A:\\HMAREF.COM\r\n'
    } | mcopy -o -i "$image" - ::AUTOEXEC.BAT

    timeout 25 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 16 \
        -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
        -boot a -serial stdio -no-reboot >"$log" 2>&1 || true

    grep -Fq 'HMAREF   COM' "$log" || {
        echo "FAIL: DOS=$mode could not enumerate HMAREF.COM" >&2
        sed -n '1,160p' "$log" >&2
        exit 1
    }
    grep -Fq 'HMA_REFERENCE_END' "$log" || {
        echo "FAIL: DOS=$mode could not execute HMAREF.COM" >&2
        sed -n '1,160p' "$log" >&2
        exit 1
    }
}

run_case HIGH
run_case LOW

grep -Eq '^A20 AX=0001 ' "$OUT/hma-high.log" || {
    echo 'FAIL: DOS=HIGH did not leave A20 enabled' >&2
    exit 1
}
grep -Eq '^HMA_REQUEST AX=0000 BL=..91' "$OUT/hma-high.log" || {
    echo 'FAIL: DOS=HIGH did not retain HMA ownership' >&2
    exit 1
}
grep -Eq '^HMA_REQUEST AX=0001 ' "$OUT/hma-low.log" || {
    echo 'FAIL: DOS=LOW unexpectedly owns the HMA' >&2
    exit 1
}
grep -Fq 'INT2F_CHAIN_RETURNED' "$OUT/hma-high.log" || {
    echo 'FAIL: a pre-HMA INT 2Fh chain could not enter relocated DOS' >&2
    exit 1
}
if grep -Fq 'HMA_REFERENCE_NO_XMS' "$OUT/hma-high.log"; then
    echo 'FAIL: DOS=HIGH lost the XMS provider during runtime stress' >&2
    exit 1
fi
if [[ $(grep -Fc 'HMA_REFERENCE_END' "$OUT/hma-high.log") -lt 2 ]]; then
    echo 'FAIL: DOS=HIGH did not preserve HMA state across child cleanup' >&2
    exit 1
fi
grep -Fq 'A20_DRIVER_RETURNED' "$OUT/hma-high.log" || {
    echo 'FAIL: DOS=HIGH did not recover from a driver disabling A20' >&2
    exit 1
}
for contract in INT21_SYSTEM_PASS INT21_FILE_MEMORY_PASS; do
    grep -Fq "$contract" "$OUT/hma-high.log" || {
        echo "FAIL: DOS=HIGH runtime contract did not pass: $contract" >&2
        sed -n '1,220p' "$OUT/hma-high.log" >&2
        exit 1
    }
done

result_word() {
    local label=$1
    local log=$2
    grep "^$label=" "$log" | tail -n 1 | cut -d= -f2 | tr -d '\r'
}

high_first=$(result_word FIRST_MCB "$OUT/hma-high.log")
low_first=$(result_word FIRST_MCB "$OUT/hma-low.log")
high_free=$(result_word TOTAL_FREE "$OUT/hma-high.log")
low_free=$(result_word TOTAL_FREE "$OUT/hma-low.log")
high_first_dec=$(printf '%d' "0x$high_first")
low_first_dec=$(printf '%d' "0x$low_first")
high_free_dec=$(printf '%d' "0x$high_free")
low_free_dec=$(printf '%d' "0x$low_free")

if (( high_first_dec >= low_first_dec )); then
    echo 'FAIL: DOS=HIGH did not move the conventional arena head downward' >&2
    exit 1
fi
if (( high_free_dec - low_free_dec < 0x700 )); then
    echo 'FAIL: DOS=HIGH did not reclaim the relocated kernel code tail' >&2
    exit 1
fi

echo '  PASS: DOS=HIGH ownership, code-tail reclaim, A20 recovery, and EXEC'
