#!/bin/bash

set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="$OUT/floppy.img"

if [[ ! -f "$BASE" ]]; then
    echo "ERROR: $BASE not found — run 'make deploy' first"
    exit 1
fi

for tool in mcopy qemu-system-i386 timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found: $tool"
        exit 1
    fi
done

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

run_case() {
    local name="$1" config="$2" commands="$3"
    local image="$OUT/supplemental-locale-$name.img"
    local log="$OUT/supplemental-locale-$name.log"
    cp "$BASE" "$image"
    printf '%s\r\n' "$config" | mcopy -o -i "$image" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\n'
        printf 'CTTY AUX\r\n'
        printf '%s\r\n' "$commands"
        printf 'ECHO SUPPLEMENTAL_%s_PASS\r\n' "$name"
    } | mcopy -o -i "$image" - ::AUTOEXEC.BAT
    timeout 35 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 4 \
        -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
        -boot a -serial stdio -no-reboot >"$log" 2>&1 || true
    if ! grep -q 'MODE prepare code page function completed' "$log" \
        || ! grep -q 'MODE select code page function completed' "$log" \
        || ! grep -q "SUPPLEMENTAL_${name}_PASS" "$log"; then
        echo "  FAIL: $name code-page contract"
        sed -n '1,160p' "$log"
        return 1
    fi
    echo "  PASS: $name code-page preparation and selection"
}

run_case LCD \
    'DEVICE=DISPLAY.SYS CON=(LCD,,1)' \
    $'MODE CON CP PREPARE=((850) A:\\LCD.CPI)\r\nMODE CON CP SELECT=850\r\nMODE CON CP /STATUS'

run_case 4208 \
    'DEVICE=PRINTER.SYS LPT1=(4208,,1)' \
    $'MODE LPT1 CP PREPARE=((850) A:\\4208.CPI)\r\nMODE LPT1 CP SELECT=850\r\nMODE LPT1 CP /STATUS'

run_case 5202 \
    'DEVICE=PRINTER.SYS LPT1=(5202,,1)' \
    $'MODE LPT1 CP PREPARE=((850) A:\\5202.CPI)\r\nMODE LPT1 CP SELECT=850\r\nMODE LPT1 CP /STATUS'
