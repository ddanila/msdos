#!/bin/bash

set -uo pipefail
export LC_ALL=C MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="$OUT/floppy.img"
TEMPLATE="$OUT/format-hdd-template.img"
EXIT_COM="$OUT/format-hdd-qexit.com"
PART_OFFSET=32256

for tool in nasm mcopy mformat mdir python3 qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null || { echo "ERROR: missing $tool"; exit 1; }
done
[[ -f "$BASE" ]] || { echo "ERROR: run make deploy first"; exit 1; }

nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
dd if=/dev/zero of="$TEMPLATE" bs=512 count=32256 status=none
python3 - "$TEMPLATE" <<'PY'
import struct, sys
p = bytearray(512)
p[446:462] = bytes((0x80, 1, 1, 0, 6, 0, 63, 31)) + struct.pack('<II', 63, 31248)
p[510:512] = b'\x55\xaa'
with open(sys.argv[1], 'r+b') as f:
    f.write(p)
PY
mformat -i "$TEMPLATE@@$PART_OFFSET" -t 31 -h 16 -n 63 -H 63 -c 4 ::
# SAFE and /Q store UNFORMAT recovery metadata at the start of the data area.
# Put the preservation marker beyond that reserved working space.
dd if=/dev/zero of="$OUT/format-hdd-pad.bin" bs=512 count=512 status=none
mcopy -i "$TEMPLATE@@$PART_OFFSET" "$OUT/format-hdd-pad.bin" ::PAD.BIN
printf 'fixed-disk-payload\r\n' | mcopy -i "$TEMPLATE@@$PART_OFFSET" - ::MARKER.TXT

PASS=0
FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

run_case() {
    local name="$1" args="$2"
    local boot="$OUT/format-hdd-$name-boot.img"
    local disk="$OUT/format-hdd-$name.img"
    local log="$OUT/format-hdd-$name.log"
    cp "$BASE" "$boot"
    cp "$TEMPLATE" "$disk"
    mcopy -o -i "$boot" "$EXIT_COM" ::QEXIT.COM
    {
        printf '@ECHO OFF\r\n'
        printf 'CTTY AUX\r\n'
        printf 'FORMAT C: /AUTOTEST %s\r\n' "$args"
        printf 'IF ERRORLEVEL 1 ECHO FORMAT_HDD_%s_ERROR\r\n' "$name"
        printf 'ECHO FORMAT_HDD_%s_DONE\r\n' "$name"
        printf 'QEXIT.COM\r\n'
    } | mcopy -o -i "$boot" - ::AUTOEXEC.BAT
    timeout 20 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 4 \
        -drive if=floppy,index=0,format=raw,file="$boot",cache=writethrough \
        -drive if=ide,index=0,format=raw,file="$disk",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$log" 2>&1 || true
    if grep -q "FORMAT_HDD_${name}_DONE" "$log" \
        && ! grep -q "FORMAT_HDD_${name}_ERROR" "$log"; then
        ok "fixed-disk $name mode completes with errorlevel 0"
    else
        fail "fixed-disk $name mode runtime"; sed -n '1,100p' "$log"
    fi
    if ! mdir -i "$disk@@$PART_OFFSET" ::MARKER.TXT >/dev/null 2>&1; then
        ok "fixed-disk $name clears prior directory metadata"
    else
        fail "fixed-disk $name left MARKER.TXT visible"
    fi
    if [[ "$name" != "U" ]] && grep -a -q 'fixed-disk-payload' "$disk"; then
        ok "fixed-disk $name preserves payload sectors"
    elif [[ "$name" != "U" ]]; then
        fail "fixed-disk $name overwrote payload sectors"
    fi
}

run_cancel_case() {
    local boot="$OUT/format-hdd-CANCEL-boot.img"
    local disk="$OUT/format-hdd-CANCEL.img"
    local log="$OUT/format-hdd-CANCEL.log"
    cp "$BASE" "$boot"
    cp "$TEMPLATE" "$disk"
    mcopy -o -i "$boot" "$EXIT_COM" ::QEXIT.COM
    {
        printf '@ECHO OFF\r\n'
        printf 'CTTY AUX\r\n'
        printf 'FORMAT C: /Q\r\n'
        printf 'IF ERRORLEVEL 5 ECHO FORMAT_HDD_CANCEL_LEVEL5\r\n'
        printf 'ECHO FORMAT_HDD_CANCEL_DONE\r\n'
        printf 'QEXIT.COM\r\n'
    } | mcopy -o -i "$boot" - ::AUTOEXEC.BAT
    local before
    before="$(shasum -a 256 "$disk" | cut -d' ' -f1)"
    printf 'N\r' | timeout 20 qemu-system-i386 -display none -monitor none \
        -machine pc -cpu 486 -m 4 \
        -drive if=floppy,index=0,format=raw,file="$boot",cache=writethrough \
        -drive if=ide,index=0,format=raw,file="$disk",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$log" 2>&1 || true
    if grep -q 'FORMAT_HDD_CANCEL_LEVEL5' "$log"; then
        ok "hard-disk warning cancellation returns DOS 5 errorlevel 5"
    else
        fail "hard-disk warning cancellation status"; sed -n '1,100p' "$log"
    fi
    local after
    after="$(shasum -a 256 "$disk" | cut -d' ' -f1)"
    if [[ "$before" == "$after" ]]; then
        ok "declining the hard-disk warning leaves every disk byte unchanged"
    else
        fail "declining the hard-disk warning modified the disk"
    fi
}

echo "=== FORMAT fixed-disk tests ==="
run_case SAFE ""
run_case Q "/Q"
run_case U "/U"
run_cancel_case

echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
