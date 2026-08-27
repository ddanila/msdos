#!/bin/bash
# Prove that CONFIG.SYS SWITCHES=/K selects conventional BIOS keyboard calls.

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

for tool in nasm mcopy qemu-system-i386 timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found: $tool"
        exit 1
    fi
done

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

run_case() {
    local name="$1"
    local expected="$2"
    local config_line="$3"
    local boot_img="$OUT/floppy-config-switches-$name.img"
    local probe_com="$OUT/config-switches-$name.com"
    local serial_log="$OUT/config-switches-$name.log"

    cp "$FLOPPY" "$boot_img"
    nasm -f bin -DEXPECTED_KEY_FN="$expected" \
        "$REPO_ROOT/tests/config_switches_probe.asm" -o "$probe_com"
    mcopy -o -i "$boot_img" "$probe_com" ::CFGKEY.COM
    if [[ -n "$config_line" ]]; then
        printf '%s\r\n' "$config_line" | mcopy -o -i "$boot_img" - ::CONFIG.SYS
    else
        printf 'FILES=20\r\n' | mcopy -o -i "$boot_img" - ::CONFIG.SYS
    fi
    {
        printf '@ECHO OFF\r\n'
        printf 'CFGKEY.COM\r\n'
    } | mcopy -o -i "$boot_img" - ::AUTOEXEC.BAT

    rm -f "$serial_log"
    timeout 35 qemu-system-i386 \
        -display none \
        -monitor none \
        -machine pc -cpu 486 -m 4 \
        -drive if=floppy,index=0,format=raw,file="$boot_img",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        >"$serial_log" 2>&1 || true

    grep -q 'CONFIG_SWITCHES_PASS' "$serial_log"
}

# Run independent images concurrently: the control proves QEMU advertises an
# extended keyboard, while /K must force DOS back to INT 16h/AH=00h.
run_case default 0x10 '' &
default_pid=$!
run_case conventional 0x00 'SWITCHES=/K' &
conventional_pid=$!

failures=0
if wait "$default_pid"; then
    echo "  PASS: default CON input uses extended INT 16h/AH=10h"
else
    echo "  FAIL: default keyboard-function control"
    sed -n '1,120p' "$OUT/config-switches-default.log"
    failures=$((failures + 1))
fi
if wait "$conventional_pid"; then
    echo "  PASS: SWITCHES=/K selects conventional INT 16h/AH=00h"
else
    echo "  FAIL: SWITCHES=/K keyboard-function contract"
    sed -n '1,120p' "$OUT/config-switches-conventional.log"
    failures=$((failures + 1))
fi

exit "$failures"
