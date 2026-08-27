#!/bin/bash
# Assert that CONFIG.SYS STACKS allocates the requested internal stack pool.

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"
PROBE_COM="$OUT/config-stacks.com"

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

nasm -f bin "$REPO_ROOT/tests/config_stacks_probe.asm" -o "$PROBE_COM"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

run_case() {
    local name="$1"
    local stacks="$2"
    local boot_img="$OUT/floppy-config-stacks-$name.img"
    local serial_log="$OUT/config-stacks-$name.log"

    cp "$FLOPPY" "$boot_img"
    mcopy -o -i "$boot_img" "$PROBE_COM" ::CFGSTK.COM
    printf 'STACKS=%s\r\n' "$stacks" | mcopy -o -i "$boot_img" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\n'
        printf 'CFGSTK.COM\r\n'
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
}

run_case disabled 0,0 &
disabled_pid=$!
run_case allocated 9,256 &
allocated_pid=$!
wait "$disabled_pid"
wait "$allocated_pid"

disabled_hex="$(sed -n 's/.*CONFIG_STACKS_FREE=\([0-9A-F][0-9A-F]*\).*/\1/p' "$OUT/config-stacks-disabled.log" | tail -1)"
allocated_hex="$(sed -n 's/.*CONFIG_STACKS_FREE=\([0-9A-F][0-9A-F]*\).*/\1/p' "$OUT/config-stacks-allocated.log" | tail -1)"

if [[ -z "$disabled_hex" || -z "$allocated_hex" ]]; then
    echo "  FAIL: STACKS probes did not report free memory"
    sed -n '1,80p' "$OUT/config-stacks-disabled.log"
    sed -n '1,80p' "$OUT/config-stacks-allocated.log"
    exit 1
fi

disabled=$((16#$disabled_hex))
allocated=$((16#$allocated_hex))
delta=$((disabled - allocated))

# Nine 256-byte stacks plus their eight-byte entries alone require 149 DOS
# paragraphs. The relocated stack handler adds more; use the strict lower bound
# so the contract is independent of harmless code-size changes.
if (( delta < 149 )); then
    echo "  FAIL: STACKS=9,256 reserved only $delta paragraphs (expected >=149)"
    exit 1
fi

echo "  PASS: STACKS=9,256 reserved $delta paragraphs versus STACKS=0,0"
