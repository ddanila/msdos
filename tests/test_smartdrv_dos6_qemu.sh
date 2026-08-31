#!/bin/bash

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT_IMG="$OUT/floppy-smartdrv-dos6.img"
HDD_IMG="$OUT/smartdrv-dos6-hdd.img"
SERIAL_LOG="$OUT/smartdrv-dos6.log"
EXIT_COM="$OUT/smartdrv-dos6-exit.com"
IO_COM="$OUT/smartdrv-dos6-io.com"
READ_COM="$OUT/smartdrv-dos6-read.com"
EVICT_COM="$OUT/smartdrv-dos6-evict.com"

[[ -f "$FLOPPY" ]] || { echo "ERROR: run 'make deploy' first"; exit 1; }
for tool in mcopy mformat nasm python3 qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: missing $tool"; exit 1; }
done

cp "$FLOPPY" "$BOOT_IMG"
dd if=/dev/zero of="$HDD_IMG" bs=512 count=32256 status=none
python3 -c "
import struct
p=bytearray(512); p[446:462]=bytes((0,1,1,0,6,0,63,31))+struct.pack('<II',63,31248); p[510:512]=b'\x55\xaa'
with open('$HDD_IMG','r+b') as f: f.write(p)
"
mformat -i "$HDD_IMG@@32256" -t 31 -h 16 -n 63 -H 63 -c 4 ::
python3 - "$HDD_IMG" <<'PY'
import sys
marker = b'SMARTDRV_SECTOR_OK'
with open(sys.argv[1], 'r+b') as f:
    f.seek((63 + 1000) * 512)
    f.write(marker + bytes([0xA5]) * (512 - len(marker)))
PY
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
nasm -f bin "$REPO_ROOT/tests/smartdrv_io_probe.asm" -o "$IO_COM"
nasm -f bin "$REPO_ROOT/tests/smartdrv_read_probe.asm" -o "$READ_COM"
nasm -f bin "$REPO_ROOT/tests/smartdrv_eviction_probe.asm" -o "$EVICT_COM"
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM
mcopy -o -i "$BOOT_IMG" "$IO_COM" ::SDIO.COM
mcopy -o -i "$BOOT_IMG" "$READ_COM" ::SDREAD.COM
mcopy -o -i "$BOOT_IMG" "$EVICT_COM" ::SDEVICT.COM
mcopy -o -i "$BOOT_IMG" "$REPO_ROOT/src/DEV/SMARTDRV/SMARTDRV.EXE" ::SMARTDRV.EXE
printf 'DEVICE=SMARTDRV.EXE 256\r\n' | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'SMARTDRV /?\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_HELP_FAILED\r\n'
    printf 'ECHO SMARTDRV_SIZE_256_BEGIN\r\nSMARTDRV /S\r\nECHO SMARTDRV_SIZE_256_END\r\n'
    printf 'ECHO SMARTDRV_QUIET_BEGIN\r\nSMARTDRV /B:16384 /E:4096 /L /U /Q 128 64\r\nECHO SMARTDRV_QUIET_END\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_INSTALL_OPTIONS_FAILED\r\n'
    printf 'ECHO SMARTDRV_SIZE_128_BEGIN\r\nSMARTDRV /S\r\nECHO SMARTDRV_SIZE_128_END\r\n'
    printf 'SMARTDRV 256 /Q\r\n'
    printf 'ECHO SMARTDRV_SIZE_RESTORED_BEGIN\r\nSMARTDRV /S\r\nECHO SMARTDRV_SIZE_RESTORED_END\r\n'
    printf 'SMARTDRV 129 /Q\r\nIF NOT ERRORLEVEL 1 ECHO SMARTDRV_BAD_SIZE_ACCEPTED\r\n'
    printf 'SMARTDRV /E:1234\r\nIF NOT ERRORLEVEL 1 ECHO SMARTDRV_BAD_ELEMENT_ACCEPTED\r\n'
    printf 'ECHO SMARTDRV_OFF_BEGIN\r\nSMARTDRV C- /S\r\nECHO SMARTDRV_OFF_END\r\n'
    printf 'ECHO SMARTDRV_READ_BEGIN\r\nSMARTDRV C /S\r\nECHO SMARTDRV_READ_END\r\n'
    printf 'ECHO SMARTDRV_NOWRITE_BEGIN\r\nSMARTDRV C+ /X /S\r\nECHO SMARTDRV_NOWRITE_END\r\n'
    printf 'SMARTDRV /N /Q\r\n'
    printf 'SMARTDRV /R\r\n'
    printf 'SMARTDRV C+ /F /V\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_CONFIG_FAILED\r\n'
    printf 'SMARTDRV /R\r\nSMARTDRV /E:1024 /B:1024 /Q\r\n'
    printf 'ECHO SMARTDRV_SHORT_READ_BEFORE_BEGIN\r\nSMARTDRV /S\r\nECHO SMARTDRV_SHORT_READ_BEFORE_END\r\n'
    printf 'SDREAD.COM\r\nIF ERRORLEVEL 1 ECHO SMARTDRV_READ_AHEAD_FAILED\r\n'
    printf 'ECHO SMARTDRV_SHORT_READ_AFTER_BEGIN\r\nSMARTDRV /S\r\nECHO SMARTDRV_SHORT_READ_AFTER_END\r\n'
    printf 'SMARTDRV /R\r\nSMARTDRV /B:16384 /Q\r\n'
    printf 'ECHO SMARTDRV_LONG_READ_BEFORE_BEGIN\r\nSMARTDRV /S\r\nECHO SMARTDRV_LONG_READ_BEFORE_END\r\n'
    printf 'SDREAD.COM\r\nIF ERRORLEVEL 1 ECHO SMARTDRV_READ_AHEAD_FAILED\r\n'
    printf 'ECHO SMARTDRV_LONG_READ_AFTER_BEGIN\r\nSMARTDRV /S\r\nECHO SMARTDRV_LONG_READ_AFTER_END\r\n'
    printf 'SMARTDRV /R\r\n'
    printf 'SDEVICT.COM\r\nIF ERRORLEVEL 1 ECHO SMARTDRV_EVICTION_FAILED\r\n'
    printf 'SMARTDRV /C\r\nIF ERRORLEVEL 1 ECHO SMARTDRV_EVICTION_FLUSH_FAILED\r\nSMARTDRV /R\r\n'
    printf 'SMARTDRV /E:1024 /Q\r\n'
    printf 'ECHO SMARTDRV_SMALL_BEFORE_BEGIN\r\nSMARTDRV /S\r\nECHO SMARTDRV_SMALL_BEFORE_END\r\n'
    printf 'SDIO.COM\r\nSMARTDRV /C\r\n'
    printf 'ECHO SMARTDRV_SMALL_AFTER_BEGIN\r\nSMARTDRV /S\r\nECHO SMARTDRV_SMALL_AFTER_END\r\n'
    printf 'SMARTDRV /R\r\nSMARTDRV /E:8192 /Q\r\n'
    printf 'ECHO SMARTDRV_LARGE_BEFORE_BEGIN\r\nSMARTDRV /S\r\nECHO SMARTDRV_LARGE_BEFORE_END\r\n'
    printf 'SDIO.COM\r\nSMARTDRV /C\r\n'
    printf 'ECHO SMARTDRV_LARGE_AFTER_BEGIN\r\nSMARTDRV /S\r\nECHO SMARTDRV_LARGE_AFTER_END\r\n'
    printf 'SMARTDRV /E:4096 /Q\r\nSMARTDRV /R\r\n'
    printf 'SDIO.COM\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_IO_FAILED\r\n'
    printf 'ECHO SMARTDRV_DIRTY_BEGIN\r\nSMARTDRV /S\r\nECHO SMARTDRV_DIRTY_END\r\n'
    printf 'ECHO SMARTDRV_LOCKED_BEGIN\r\nSMARTDRV /L /S\r\nECHO SMARTDRV_LOCKED_END\r\n'
    printf 'ECHO SMARTDRV_UNLOCKED_BEGIN\r\nSMARTDRV /U /S\r\nECHO SMARTDRV_UNLOCKED_END\r\n'
    printf 'SMARTDRV /C\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_FLUSH_FAILED\r\n'
    printf 'ECHO SMARTDRV_CLEAN_BEGIN\r\nSMARTDRV /S\r\nECHO SMARTDRV_CLEAN_END\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

: >"$SERIAL_LOG"
timeout 25 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=ide,index=0,format=raw,file="$HDD_IMG",cache=writethrough \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 -boot a -serial stdio -no-reboot \
    >"$SERIAL_LOG" 2>&1 || true

dirty="$(sed -n '/SMARTDRV_DIRTY_BEGIN/,/SMARTDRV_DIRTY_END/p' "$SERIAL_LOG")"
locked="$(sed -n '/SMARTDRV_LOCKED_BEGIN/,/SMARTDRV_LOCKED_END/p' "$SERIAL_LOG")"
unlocked="$(sed -n '/SMARTDRV_UNLOCKED_BEGIN/,/SMARTDRV_UNLOCKED_END/p' "$SERIAL_LOG")"
clean="$(sed -n '/SMARTDRV_CLEAN_BEGIN/,/SMARTDRV_CLEAN_END/p' "$SERIAL_LOG")"
quiet_output="$(sed -n '/SMARTDRV_QUIET_BEGIN/,/SMARTDRV_QUIET_END/p' "$SERIAL_LOG")"
off_status="$(sed -n '/SMARTDRV_OFF_BEGIN/,/SMARTDRV_OFF_END/p' "$SERIAL_LOG")"
read_status="$(sed -n '/SMARTDRV_READ_BEGIN/,/SMARTDRV_READ_END/p' "$SERIAL_LOG")"
nowrite_status="$(sed -n '/SMARTDRV_NOWRITE_BEGIN/,/SMARTDRV_NOWRITE_END/p' "$SERIAL_LOG")"
size_256="$(sed -n '/SMARTDRV_SIZE_256_BEGIN/,/SMARTDRV_SIZE_256_END/p' "$SERIAL_LOG")"
size_128="$(sed -n '/SMARTDRV_SIZE_128_BEGIN/,/SMARTDRV_SIZE_128_END/p' "$SERIAL_LOG")"
size_restored="$(sed -n '/SMARTDRV_SIZE_RESTORED_BEGIN/,/SMARTDRV_SIZE_RESTORED_END/p' "$SERIAL_LOG")"
move_count() {
    sed -n "/$1_BEGIN/,/$1_END/p" "$SERIAL_LOG" \
        | sed -n 's/.*movement chunks: \([0-9][0-9]*\).*/\1/p' \
        | tail -1
}
small_before="$(move_count SMARTDRV_SMALL_BEFORE)"
small_after="$(move_count SMARTDRV_SMALL_AFTER)"
large_before="$(move_count SMARTDRV_LARGE_BEFORE)"
large_after="$(move_count SMARTDRV_LARGE_AFTER)"
small_delta=$((small_after - small_before))
large_delta=$((large_after - large_before))
short_read_before="$(move_count SMARTDRV_SHORT_READ_BEFORE)"
short_read_after="$(move_count SMARTDRV_SHORT_READ_AFTER)"
long_read_before="$(move_count SMARTDRV_LONG_READ_BEFORE)"
long_read_after="$(move_count SMARTDRV_LONG_READ_AFTER)"
short_read_delta=$((short_read_after - short_read_before))
long_read_delta=$((long_read_after - long_read_before))
sector_matches="$(python3 - "$HDD_IMG" <<'PY'
import sys
with open(sys.argv[1], 'rb') as f:
    f.seek((63 + 1000) * 512); actual=f.read(512)
expected=b'SMARTDRV_SECTOR_OK'+bytes([0xA5])*(512-len(b'SMARTDRV_SECTOR_OK'))
print('yes' if actual == expected else 'no')
PY
)"
eviction_matches="$(python3 - "$HDD_IMG" <<'PY'
import sys
with open(sys.argv[1], 'rb') as f:
    for i in range(1, 10):
        f.seek((63 + 1000 + i * 63) * 512)
        if f.read(512) != bytes([0xA0 + i]) * 512:
            print('no')
            break
    else:
        print('yes')
PY
)"

if [[ "$(grep -c 'SMARTDRV_QUIET_' <<<"$quiet_output")" == 2 ]] \
    && grep -q 'Cache size: 256K current, 256K maximum, 128K minimum' <<<"$size_256" \
    && grep -q 'Tracks: 8 total' <<<"$size_256" \
    && grep -q 'Cache size: 128K current, 256K maximum, 128K minimum' <<<"$size_128" \
    && grep -q 'Tracks: 4 total' <<<"$size_128" \
    && grep -q 'Cache size: 256K current, 256K maximum, 128K minimum' <<<"$size_restored" \
    && grep -q 'Tracks: 8 total' <<<"$size_restored" \
    && grep -q 'Transfer element: 4096 bytes; read-ahead: 16384 bytes' <<<"$size_128" \
    && (( small_delta > large_delta )) \
    && (( long_read_delta > short_read_delta )) \
    && grep -q 'C:  Read cache no  Write cache no' <<<"$off_status" \
    && grep -q 'C:  Read cache yes  Write cache no' <<<"$read_status" \
    && grep -q 'C:  Read cache yes  Write cache no' <<<"$nowrite_status" \
    && grep -q 'C:  Read cache yes  Write cache yes' "$SERIAL_LOG" \
    && grep -Eq '[1-9][0-9]* dirty' <<<"$dirty" \
    && grep -Eq 'Cache lock: on, [1-9][0-9]* tracks locked' <<<"$locked" \
    && grep -q 'Cache lock: off, 0 tracks locked' <<<"$unlocked" \
    && grep -q '0 dirty' <<<"$clean" \
    && [[ "$sector_matches" == yes ]] \
    && [[ "$eviction_matches" == yes ]] \
    && grep -q 'SMARTDRV: invalid cache element or read-ahead size' "$SERIAL_LOG" \
    && ! grep -q 'SMARTDRV_.*_FAILED\|SMARTDRV_BAD_ELEMENT_ACCEPTED\|SMARTDRV_BAD_SIZE_ACCEPTED' "$SERIAL_LOG"; then
    echo "  PASS: DOS 6 SMARTDRV read-ahead, transfer sizing, eviction, and write-behind"
    exit 0
fi

echo "  FAIL: DOS 6 SMARTDRV controller/write-behind contract did not complete"
sed -n '1,220p' "$SERIAL_LOG"
exit 1
