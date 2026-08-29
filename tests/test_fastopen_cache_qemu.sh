#!/bin/bash

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT_IMG="$OUT/floppy-fastopen-cache.img"
HDD_IMG="$OUT/fastopen-cache-hdd.img"
SERIAL_LOG="$OUT/fastopen-cache.log"
PROBE_COM="$OUT/fastopen-cache-probe.com"
EXIT_COM="$OUT/fastopen-cache-exit.com"

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
python3 - "$HDD_IMG" <<'PY'
import struct
import sys

p = bytearray(512)
p[446:462] = bytes((0, 1, 1, 0, 6, 0, 63, 31)) + struct.pack('<II', 63, 31248)
p[510:512] = b'\x55\xaa'
with open(sys.argv[1], 'r+b') as image:
    image.write(p)
PY
mformat -i "$HDD_IMG@@32256" -t 31 -h 16 -n 63 -H 63 -c 4 ::
nasm -f bin "$REPO_ROOT/tests/fastopen_cache_probe.asm" -o "$PROBE_COM"
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
export MTOOLS_NO_VFAT=1
mcopy -o -i "$BOOT_IMG" "$PROBE_COM" ::FOPROBE.COM
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM
printf 'DEVICE=A:\\EMM386.EXE M5\r\n' | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'FOPROBE.COM B\r\n'
    printf 'IF ERRORLEVEL 1 ECHO FASTOPEN_PRECHECK_FAILED\r\n'
    printf 'FASTOPEN C:=50 /X\r\n'
    printf 'IF ERRORLEVEL 1 ECHO FASTOPEN_INSTALL_FAILED\r\n'
    printf 'FOPROBE.COM P\r\n'
    printf 'IF ERRORLEVEL 1 ECHO FASTOPEN_CACHE_FAILED\r\n'
    printf 'ECHO FASTOPEN_CACHE_DONE\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

rm -f "$SERIAL_LOG"
timeout 20 qemu-system-i386 \
    -display none \
    -monitor none \
    -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=none,id=fastdisk,format=raw,file="$HDD_IMG",cache=writethrough \
    -device ide-hd,drive=fastdisk,bus=ide.0,unit=0,cyls=32,heads=16,secs=63 \
    -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -boot a -no-reboot \
    >"$SERIAL_LOG" 2>&1 || true

if grep -q 'FASTOPEN_CACHE_DONE' "$SERIAL_LOG" \
    && ! grep -q 'FASTOPEN_.*_FAILED' "$SERIAL_LOG"; then
    echo "  PASS: FASTOPEN installed its /X EMS cache and invalidated a renamed pathname"
    exit 0
fi

echo "  FAIL: FASTOPEN pathname-cache contract did not complete"
sed -n '1,180p' "$SERIAL_LOG"
exit 1
