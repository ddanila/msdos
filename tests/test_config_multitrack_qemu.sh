#!/bin/bash

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"
HDD_TEMPLATE="$OUT/config-multitrack-template.img"
PROBE_COM="$OUT/config-multitrack.com"

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

for tool in nasm mcopy mformat python3 qemu-system-i386 timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found: $tool"
        exit 1
    fi
done

nasm -f bin "$REPO_ROOT/tests/config_multitrack_probe.asm" -o "$PROBE_COM"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

dd if=/dev/zero of="$HDD_TEMPLATE" bs=512 count=32256 status=none
python3 -c "
import struct
p = bytearray(512)
p[446:462] = bytes((0, 1, 1, 0, 6, 0, 63, 31)) + struct.pack('<II', 63, 31248)
p[510:512] = b'\\x55\\xaa'
with open('$HDD_TEMPLATE', 'r+b') as f:
    f.write(p)
"
mformat -i "$HDD_TEMPLATE@@32256" -t 31 -h 16 -n 63 -H 63 -c 4 ::

run_case() {
    local name="$1"
    local setting="$2"
    local boot_img="$OUT/floppy-config-multitrack-$name.img"
    local hdd_img="$OUT/config-multitrack-$name.img"
    local serial_log="$OUT/config-multitrack-$name.log"

    cp "$FLOPPY" "$boot_img"
    cp "$HDD_TEMPLATE" "$hdd_img"
    mcopy -o -i "$boot_img" "$PROBE_COM" ::CFGMT.COM
    printf 'MULTITRACK=%s\r\n' "$setting" | mcopy -o -i "$boot_img" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\n'
        printf 'CFGMT.COM\r\n'
    } | mcopy -o -i "$boot_img" - ::AUTOEXEC.BAT

    rm -f "$serial_log"
    timeout 35 qemu-system-i386 \
        -display none \
        -monitor none \
        -machine pc -cpu 486 -m 4 \
        -drive if=floppy,index=0,format=raw,file="$boot_img",cache=writethrough \
        -drive if=ide,index=0,format=raw,file="$hdd_img",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        >"$serial_log" 2>&1 || true
}

run_case on ON &
on_pid=$!
run_case off OFF &
off_pid=$!
wait "$on_pid"
wait "$off_pid"

read_result() {
    sed -n 's/.*CONFIG_MULTITRACK_IO=\([0-9A-F][0-9A-F]*\),\([0-9A-F][0-9A-F]*\).*/\1 \2/p' "$1" | tail -1
}

read -r on_calls_hex on_max_hex <<<"$(read_result "$OUT/config-multitrack-on.log")"
read -r off_calls_hex off_max_hex <<<"$(read_result "$OUT/config-multitrack-off.log")"
if [[ -z "${on_calls_hex:-}" || -z "${off_calls_hex:-}" ]]; then
    echo "  FAIL: MULTITRACK probes did not report BIOS I/O"
    sed -n '1,100p' "$OUT/config-multitrack-on.log"
    sed -n '1,100p' "$OUT/config-multitrack-off.log"
    exit 1
fi

on_calls=$((16#$on_calls_hex))
on_max=$((16#$on_max_hex))
off_calls=$((16#$off_calls_hex))
off_max=$((16#$off_max_hex))

if (( on_max <= off_max || on_calls >= off_calls )); then
    echo "  FAIL: ON calls/max=$on_calls/$on_max, OFF calls/max=$off_calls/$off_max"
    exit 1
fi

echo "  PASS: MULTITRACK=ON coalesced BIOS reads ($on_calls/$on_max vs OFF $off_calls/$off_max calls/max sectors)"
