#!/bin/bash
# Exercise SMARTDRV.SYS control state through the shipped FLUSH13.EXE utility.

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
SRC="$REPO_ROOT/MS-DOS/v4.0/src"
FLOPPY="$OUT/floppy.img"
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
mcopy -o -i "$BOOT_IMG" "$SRC/DEV/SMARTDRV/FLUSH13.EXE" ::FLUSH13.EXE
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM
mcopy -o -i "$BOOT_IMG" "$IO_COM" ::SDIO.COM
printf 'DEVICE=SMARTDRV.SYS 256\r\n' | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'FLUSH13 /S\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_STATUS_FAILED\r\n'
    printf 'FLUSH13 /D /S\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_DISABLE_FAILED\r\n'
    printf 'FLUSH13 /E /C:ON /WT:OFF /WC:ON /SX\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_ENABLE_FAILED\r\n'
    printf 'ECHO SMARTDRV_POPULATED_BEGIN\r\n'
    printf 'SDIO.COM\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_IO_FAILED\r\n'
    printf 'FLUSH13 /SX\r\n'
    printf 'ECHO SMARTDRV_POPULATED_END\r\n'
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
    && grep -q 'Caching of full track reads is ON' "$SERIAL_LOG" \
    && grep -q 'Write Through is OFF' "$SERIAL_LOG" \
    && grep -q 'Write Caching is ON' "$SERIAL_LOG" \
    && grep -Eq '[1-9][0-9]* are used' <<<"$populated_status" \
    && grep -q '  0 are dirty' <<<"$populated_status" \
    && grep -q '  0 are dirty' <<<"$clean_status" \
    && [[ "$sector_matches" == 'yes' ]] \
    && grep -q 'SMARTDRV_FLUSH_DONE' "$SERIAL_LOG" \
    && ! grep -q 'SMARTDRV_.*_FAILED\|device not found\|device function failed' "$SERIAL_LOG"; then
    echo "  PASS: SMARTDRV cached real C: I/O and preserved the exact write-through payload"
    exit 0
fi

echo "  FAIL: SMARTDRV/FLUSH13 behavioral contract did not complete"
sed -n '1,220p' "$SERIAL_LOG"
exit 1
