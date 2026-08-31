#!/bin/bash

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT_IMG="$OUT/floppy-smartdrv-flush.img"
HDD_IMG="$OUT/smartdrv-flush-hdd.img"
SERIAL_LOG="$OUT/smartdrv-flush.log"
EXIT_COM="$OUT/smartdrv-flush-exit.com"
IO_COM="$OUT/smartdrv-io.com"

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

for tool in mcopy mformat nasm python3 qemu-system-i386 timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found: $tool"
        exit 1
    fi
done

cp "$FLOPPY" "$BOOT_IMG"
dd if=/dev/zero of="$HDD_IMG" bs=512 count=32256 status=none
python3 -c "
import struct
p = bytearray(512)
p[446:462] = bytes((0, 1, 1, 0, 6, 0, 63, 31)) + struct.pack('<II', 63, 31248)
p[510:512] = b'\\x55\\xaa'
with open('$HDD_IMG', 'r+b') as f:
    f.write(p)
"
mformat -i "$HDD_IMG@@32256" -t 31 -h 16 -n 63 -H 63 -c 4 ::

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
nasm -f bin "$REPO_ROOT/tests/smartdrv_io_probe.asm" -o "$IO_COM"
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM
mcopy -o -i "$BOOT_IMG" "$IO_COM" ::SDIO.COM
printf 'DEVICE=SMARTDRV.EXE 256\r\n' | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'FLUSH13 /S\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_STATUS_FAILED\r\n'
    printf 'FLUSH13 /D /S\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_DISABLE_FAILED\r\n'
    printf 'FLUSH13 /E\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_ENABLE_FAILED\r\n'
    printf 'ECHO SMARTDRV_OFF_POLICIES_BEGIN\r\n'
    printf 'FLUSH13 /C:OFF\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_COFF_FAILED\r\n'
    printf 'FLUSH13 /WT:ON\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_WTON_FAILED\r\n'
    printf 'FLUSH13 /WC:OFF\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_WCOFF_FAILED\r\n'
    printf 'FLUSH13 /R:OFF\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_ROFF_FAILED\r\n'
    printf 'FLUSH13 /T:182\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_TICK_FAILED\r\n'
    printf 'FLUSH13 /S\r\n'
    printf 'ECHO SMARTDRV_OFF_POLICIES_END\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_OFF_POLICIES_FAILED\r\n'
    printf 'ECHO SMARTDRV_ON_POLICIES_BEGIN\r\n'
    printf 'FLUSH13 /C:ON /WT:OFF /WC:ON /R:ON /U /S\r\n'
    printf 'ECHO SMARTDRV_ON_POLICIES_END\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_ON_POLICIES_FAILED\r\n'
    printf 'ECHO SMARTDRV_POPULATED_BEGIN\r\n'
    printf 'SDIO.COM\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_IO_FAILED\r\n'
    printf 'FLUSH13 /L /S\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_LOCK_FAILED\r\n'
    printf 'FLUSH13 /U\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_UNLOCK_FAILED\r\n'
    printf 'FLUSH13 /SX\r\n'
    printf 'ECHO SMARTDRV_POPULATED_END\r\n'
    printf 'FLUSH13 /I\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_INVALIDATE_FAILED\r\n'
    printf 'ECHO SMARTDRV_RESET_BEGIN\r\n'
    printf 'FLUSH13 /SR\r\n'
    printf 'ECHO SMARTDRV_RESET_END\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_RESET_FAILED\r\n'
    printf 'FLUSH13 /D /E\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_CONFLICT_REJECTED\r\n'
    printf 'FLUSH13 /T:\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_MALFORMED_REJECTED\r\n'
    printf 'FLUSH13 /F\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_FLUSH_FAILED\r\n'
    printf 'ECHO SMARTDRV_CLEAN_BEGIN\r\n'
    printf 'FLUSH13 /SX\r\n'
    printf 'ECHO SMARTDRV_CLEAN_END\r\n'
    printf 'ECHO SMARTDRV_FLUSH_DONE\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

rm -f "$SERIAL_LOG"
timeout 25 qemu-system-i386 \
    -display none \
    -monitor none \
    -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=ide,index=0,format=raw,file="$HDD_IMG",cache=writethrough \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -boot a -serial stdio -no-reboot \
    >"$SERIAL_LOG" 2>&1 || true

enabled_count="$(grep -c 'Caching is ENABLED' "$SERIAL_LOG" || true)"
populated_status="$(sed -n '/SMARTDRV_POPULATED_BEGIN/,/SMARTDRV_POPULATED_END/p' "$SERIAL_LOG")"
clean_status="$(sed -n '/SMARTDRV_CLEAN_BEGIN/,/SMARTDRV_CLEAN_END/p' "$SERIAL_LOG")"
off_policies="$(sed -n '/SMARTDRV_OFF_POLICIES_BEGIN/,/SMARTDRV_OFF_POLICIES_END/p' "$SERIAL_LOG")"
on_policies="$(sed -n '/SMARTDRV_ON_POLICIES_BEGIN/,/SMARTDRV_ON_POLICIES_END/p' "$SERIAL_LOG")"
reset_status="$(sed -n '/SMARTDRV_RESET_BEGIN/,/SMARTDRV_RESET_END/p' "$SERIAL_LOG")"
sector_matches="$(python3 - "$HDD_IMG" <<'PY'
import sys

offset = (63 + 1000) * 512
with open(sys.argv[1], "rb") as image:
    image.seek(offset)
    actual = image.read(512)
expected = b"SMARTDRV_SECTOR_OK" + bytes([0xA5]) * (512 - len(b"SMARTDRV_SECTOR_OK"))
print("yes" if actual == expected else "no")
PY
)"
if (( enabled_count >= 2 )) \
    && grep -q 'Caching is DISABLED' "$SERIAL_LOG" \
    && grep -q 'Write Caching is OFF' <<<"$off_policies" \
    && grep -q 'Reboot flush is OFF' <<<"$off_policies" \
    && grep -q 'Caching of full track reads is OFF' <<<"$off_policies" \
    && grep -q 'Write Through is ON' <<<"$off_policies" \
    && grep -q '(182 ticks)' <<<"$off_policies" \
    && grep -q 'Cache is UNLOCKED' <<<"$on_policies" \
    && grep -q 'Write Caching is ON' <<<"$on_policies" \
    && grep -q 'Reboot flush is ON' <<<"$on_policies" \
    && grep -q 'Caching of full track reads is ON' <<<"$on_policies" \
    && grep -q 'Write Through is OFF' <<<"$on_policies" \
    && grep -q 'Cache is LOCKED' <<<"$populated_status" \
    && grep -q 'Cache is UNLOCKED' <<<"$populated_status" \
    && grep -Eq '[1-9][0-9]* are used' <<<"$populated_status" \
    && grep -q '  0 are dirty' <<<"$populated_status" \
    && grep -Eq '0 +Total operations' <<<"$reset_status" \
    && grep -q '  0 are dirty' <<<"$clean_status" \
    && [[ "$sector_matches" == 'yes' ]] \
    && grep -q 'SMARTDRV_FLUSH_DONE' "$SERIAL_LOG" \
    && grep -q 'SMARTDRV_CONFLICT_REJECTED' "$SERIAL_LOG" \
    && grep -q 'SMARTDRV_MALFORMED_REJECTED' "$SERIAL_LOG" \
    && ! grep -q 'SMARTDRV_.*_FAILED\|device not found\|device function failed' "$SERIAL_LOG"; then
    echo "  PASS: SMARTDRV cached real C: I/O and preserved the exact write-through payload"
    exit 0
fi

echo "  FAIL: SMARTDRV/FLUSH13 behavioral contract did not complete"
sed -n '1,220p' "$SERIAL_LOG"
exit 1
