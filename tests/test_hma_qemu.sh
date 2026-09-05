#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
FLOPPY="$OUT/floppy.img"
HIMEM="$OUT/hma-himem.sys"
PROBE="$OUT/hma-reference.com"
A20_DRIVER="$OUT/hma-a20.sys"
SYSTEM_PROBE="$OUT/hma-i21system.com"
FILE_MEMORY_PROBE="$OUT/hma-i21fmem.com"
TAIL_PROBE="$OUT/hma-tail.com"
COMMAND_CRITICAL_PROBE="$OUT/command-critical-hma.com"

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
    "$ROOT/src/DEV/HIMEM/HIMEM.ASM"
nasm -f bin "$ROOT/tests/hma_reference_probe.asm" -o "$PROBE"
nasm -f bin "$ROOT/tests/hma_a20_driver.asm" -o "$A20_DRIVER"
nasm -f bin "$ROOT/tests/int21_system_probe.asm" -o "$SYSTEM_PROBE"
nasm -DNO_DEBUG_EXIT -f bin "$ROOT/tests/int21_file_memory_probe.asm" \
    -o "$FILE_MEMORY_PROBE"
sysbuf_hex=$(awk '$2 == "SYSBUF" { split($1, address, ":"); print address[2]; exit }' \
    "$ROOT/src/DOS/MSDOS.MAP")
[[ "$sysbuf_hex" =~ ^[0-9A-Fa-f]{4}$ ]] || {
    echo 'ERROR: could not read SYSBUF from MSDOS.MAP' >&2
    exit 1
}
hma_tail=$((16#$sysbuf_hex + 15 * (512 + 20) + 8))
catalog_start_hex=$(awk 'toupper($2) == "RESIDENT_CATALOG_START" { split($1, address, ":"); print address[2]; exit }' \
    "$ROOT/src/CMD/COMMAND/COMMAND.MAP")
dataresend_hex=$(awk 'toupper($2) == "DATARESEND" { split($1, address, ":"); print address[2]; exit }' \
    "$ROOT/src/CMD/COMMAND/COMMAND.MAP")
class_ptrs_hex=$(awk 'toupper($2) == "RESIDENT_CLASS_PTRS" { split($1, address, ":"); print address[2]; exit }' \
    "$ROOT/src/CMD/COMMAND/COMMAND.MAP")
hma_code_start_hex=$(awk 'toupper($2) == "HMA_CODE_START" { split($1, address, ":"); print address[2]; exit }' \
    "$ROOT/src/CMD/COMMAND/COMMAND.MAP")
hma_code_end_hex=$(awk 'toupper($2) == "HMA_CODE_END" { split($1, address, ":"); print address[2]; exit }' \
    "$ROOT/src/CMD/COMMAND/COMMAND.MAP")
[[ "$catalog_start_hex" =~ ^[0-9A-Fa-f]{4}$ && "$dataresend_hex" =~ ^[0-9A-Fa-f]{4}$ \
    && "$class_ptrs_hex" =~ ^[0-9A-Fa-f]{4}$ && "$hma_code_start_hex" =~ ^[0-9A-Fa-f]{4}$ \
    && "$hma_code_end_hex" =~ ^[0-9A-Fa-f]{4}$ ]] || {
    echo 'ERROR: could not read COMMAND HMA payload ranges' >&2
    exit 1
}
command_hma_bytes=$((16#$dataresend_hex - 16#$catalog_start_hex \
    + 16#$hma_code_end_hex - 16#$hma_code_start_hex))
hma_tail_after_command=$((hma_tail + command_hma_bytes))
nasm -DEXPECTED_CLASS_PTRS="0x$class_ptrs_hex" \
    -DEXPECTED_CATALOG_BASE="$hma_tail" -DEXPECTED_CATALOG_END="$hma_tail_after_command" \
    -DEXPECTED_HMA_CLASSES=2 \
    -f bin "$ROOT/tests/command_critical_hma_probe.asm" -o "$COMMAND_CRITICAL_PROBE"
tail_floor_hex=$(awk 'toupper($2) == "HMA_TAIL_FLOOR" { split($1, address, ":"); sub(/\*$/, "", address[2]); print address[2]; exit }' \
    "$ROOT/src/DOS/MSDOS.MAP")
tail_next_hex=$(awk 'toupper($2) == "HMA_TAIL_NEXT" { split($1, address, ":"); sub(/\*$/, "", address[2]); print address[2]; exit }' \
    "$ROOT/src/DOS/MSDOS.MAP")
[[ "$tail_floor_hex" =~ ^[0-9A-Fa-f]{4}$ && "$tail_next_hex" =~ ^[0-9A-Fa-f]{4}$ ]] || exit 1
nasm -DEXPECTED_TAIL="$hma_tail_after_command" \
    -DTAIL_FLOOR="0x$tail_floor_hex" -DTAIL_NEXT="0x$tail_next_hex" -f bin \
    "$ROOT/tests/hma_tail_probe.asm" -o "$TAIL_PROBE"

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
    mcopy -o -i "$image" "$COMMAND_CRITICAL_PROBE" ::CMDCRIT.COM
    mcopy -o -i "$image" "$TAIL_PROBE" ::HMATAIL.COM
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
        if [[ "$mode" == HIGH ]]; then
            printf 'CMDCRIT.COM\r\n'
        fi
        printf 'HMATAIL.COM\r\n'
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
    if [[ "$mode" == HIGH ]]; then
        grep -Fq 'COMMAND_CATALOG_HMA_PASS' "$log" || {
            echo 'FAIL: COMMAND did not publish all copied HMA catalogs' >&2
            sed -n '1,180p' "$log" >&2
            exit 1
        }
        grep -Fq 'HMA_TAIL_AVAILABLE' "$log" || {
            echo 'FAIL: DOS=HIGH did not publish bounded HMA tail storage' >&2
            sed -n '1,180p' "$log" >&2
            exit 1
        }
    else
        grep -Fq 'HMA_TAIL_UNAVAILABLE' "$log" || {
            echo 'FAIL: DOS=LOW exposed HMA tail storage' >&2
            sed -n '1,180p' "$log" >&2
            exit 1
        }
    fi
    if grep -Fq 'HMA_TAIL_FAILURE' "$log"; then
        echo "FAIL: DOS=$mode HMA tail allocator corrupted its bounds" >&2
        sed -n '1,180p' "$log" >&2
        exit 1
    fi
    if ! python3 -c \
        'import sys; raise SystemExit(b"\0" in open(sys.argv[1], "rb").read())' \
        "$log"; then
        echo "FAIL: DOS=$mode emitted NUL data through a wrapped HMA pointer" >&2
        exit 1
    fi
}

run_case HIGH
run_case LOW

NO_XMS_IMAGE="$OUT/floppy-hma-no-xms.img"
NO_XMS_LOG="$OUT/hma-no-xms.log"
NO_XMS_SCREEN_LOG="$OUT/hma-no-xms-screen.log"
NO_XMS_QMP="$OUT/hma-no-xms-qmp.sock"
cp "$FLOPPY" "$NO_XMS_IMAGE"
mcopy -o -i "$NO_XMS_IMAGE" "$PROBE" ::HMAREF.COM
printf 'DOS=HIGH\r\n' | mcopy -o -i "$NO_XMS_IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'HMAREF.COM\r\n'
} | mcopy -o -i "$NO_XMS_IMAGE" - ::AUTOEXEC.BAT
rm -f "$NO_XMS_QMP" "$NO_XMS_SCREEN_LOG"
qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$NO_XMS_IMAGE",cache=writethrough \
    -boot a -serial file:"$NO_XMS_LOG" \
    -qmp unix:"$NO_XMS_QMP",server,nowait -no-reboot >/dev/null 2>&1 &
no_xms_pid=$!
cleanup_no_xms() {
    kill "$no_xms_pid" 2>/dev/null || true
    wait "$no_xms_pid" 2>/dev/null || true
    rm -f "$NO_XMS_QMP"
}
trap cleanup_no_xms EXIT
for _ in $(seq 1 50); do
    [[ -S "$NO_XMS_QMP" ]] && break
    kill -0 "$no_xms_pid" 2>/dev/null || break
    sleep 0.1
done
[[ -S "$NO_XMS_QMP" ]] || {
    echo 'FAIL: DOS=HIGH fallback QMP socket did not appear' >&2
    exit 1
}
timeout 30 python3 "$ROOT/tests/screen_expect.py" \
    "$NO_XMS_QMP" "$NO_XMS_SCREEN_LOG" \
    'HMA not available: Loading DOS low' ''
cleanup_no_xms
trap - EXIT

grep -Fq 'HMA_REFERENCE_NO_XMS' "$NO_XMS_LOG" || {
    echo 'FAIL: DOS=HIGH without XMS did not complete through the low kernel' >&2
    sed -n '1,160p' "$NO_XMS_LOG" >&2
    exit 1
}
grep -Fq 'HMA not available: Loading DOS low' "$NO_XMS_SCREEN_LOG" || {
    echo 'FAIL: DOS=HIGH runtime fallback diagnostic differs from MS-DOS 6.22' >&2
    sed -n '1,180p' "$NO_XMS_SCREEN_LOG" >&2
    exit 1
}

for log in "$OUT/hma-high.log" "$OUT/hma-low.log"; do
    grep -Fq 'DOS_VERSION_AX=1606' "$log" || {
        echo "FAIL: runtime did not report DOS 6.22 in $log" >&2
        exit 1
    }
done

python3 - "$OUT/hma-high.log" <<'PY' || {
import sys

data = open(sys.argv[1], "rb").read()
expected = b"\r\nA20_DRIVER_RETURNED\r\n"
raise SystemExit(0 if data.startswith(expected) else 1)
PY
    echo 'FAIL: DOS=HIGH emitted data before the post-driver marker' >&2
    exit 1
}

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

echo '  PASS: DOS=HIGH ownership, fallback, code-tail reclaim, A20 recovery, and EXEC'
