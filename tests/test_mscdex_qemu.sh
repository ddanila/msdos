#!/bin/bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/mscdex-test.img"
LOG="$OUT/mscdex-test.log"
DRIVER="$OUT/MSCDDRV.SYS"
PROBE="$OUT/MSCAPI.COM"
EXIT_COM="$OUT/mscdex-qexit.com"
DOS_PROBE="$OUT/MSCDFILE.COM"
SHARE_PROBE="$OUT/MSCSHARE.COM"
NOSHARE_PROBE="$OUT/MSCNSHAR.COM"
NOSHARE_IMAGE="$OUT/mscdex-noshare.img"
NOSHARE_LOG="$OUT/mscdex-noshare.log"

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || { echo "missing required tool: $tool" >&2; exit 1; }
done
[[ -f "$BASE" ]] || { echo 'run make deploy first' >&2; exit 1; }

nasm -f bin "$ROOT/tests/mscd_test_driver.asm" -o "$DRIVER"
nasm -f bin "$ROOT/tests/mscdex_api_probe.asm" -o "$PROBE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
nasm -f bin "$ROOT/tests/mscdex_dos_file_probe.asm" -o "$DOS_PROBE"
nasm -DEXPECT_SHARE -f bin "$ROOT/tests/mscdex_share_probe.asm" -o "$SHARE_PROBE"
nasm -f bin "$ROOT/tests/mscdex_share_probe.asm" -o "$NOSHARE_PROBE"
cp "$BASE" "$IMAGE"
mcopy -o -i "$IMAGE" "$ROOT/src/CMD/MSCDEX/MSCDEX.EXE" ::MSCDEX.EXE
mcopy -o -i "$IMAGE" "$DRIVER" ::MSCDDRV.SYS
mcopy -o -i "$IMAGE" "$PROBE" ::MSCAPI.COM
mcopy -o -i "$IMAGE" "$EXIT_COM" ::QEXIT.COM
mcopy -o -i "$IMAGE" "$DOS_PROBE" ::MSCDFILE.COM
mcopy -o -i "$IMAGE" "$SHARE_PROBE" ::MSCSHARE.COM
{
    printf 'LASTDRIVE=Z\r\n'
    printf 'DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF\r\n'
    printf 'DEVICE=A:\\EMM386.EXE RAM\r\n'
    printf 'DEVICE=A:\\MSCDDRV.SYS /D:MSCD001\r\n'
} | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'MSCDEX /?\r\nIF NOT ERRORLEVEL 1 ECHO MSCDEX_HELP_STATUS_BAD\r\n'
    printf 'MSCDEX /D:NOTHERE /L:E\r\nIF NOT ERRORLEVEL 1 ECHO MSCDEX_MISSING_ACCEPTED\r\n'
    printf 'MSCDEX /D:MSCD001 /L:E /M:12 /E /K /S /V\r\n'
    printf 'IF ERRORLEVEL 1 ECHO MSCDEX_INSTALL_FAILED\r\n'
    printf 'MSCDEX\r\n'
    printf 'ECHO MSCDEX_TEST_DONE\r\n'
    printf 'MSCDFILE.COM\r\nIF ERRORLEVEL 1 ECHO MSCDEX_DOS_FILE_FAILED\r\n'
    printf 'MSCSHARE.COM\r\nIF ERRORLEVEL 1 ECHO MSCDEX_SHARE_FAILED\r\n'
    printf 'MSCAPI.COM\r\nIF ERRORLEVEL 1 ECHO MSCDEX_API_FAILED\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

timeout 60 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$LOG" 2>&1 || true

for marker in \
    "Illegal option '?'" \
    'usage: MSCDEX [/E/K/S/V] [/D:<driver> ... ] [/L:<letter>] [/M:<buffers>]' \
    "Device driver not found: 'NOTHERE'." \
    'No valid CDROM device drivers selected' \
    'MSCDEX Version 2.23' 'Cache storage: expanded memory' \
    'Drive assigned to driver: E:' 'MSCDEX_DOS_FILE_PASS' \
    'MSCDEX_API_PASS' 'MSCDEX_SHARE_PASS' 'MSCDEX already installed.' 'MSCDEX_TEST_DONE'; do
    grep -Fq "$marker" "$LOG" || { echo "missing MSCDEX evidence: $marker" >&2; sed -n '1,180p' "$LOG" >&2; exit 1; }
done
if grep -Eq 'MSCDEX_(HELP_STATUS_BAD|MISSING_ACCEPTED|INSTALL_FAILED|DOS_FILE_FAILED|API_FAILED|SHARE_FAILED)' "$LOG"; then
    sed -n '1,180p' "$LOG" >&2
    exit 1
fi

# Without /S the same redirector remains remote-only and must not advertise
# the local/shareable CDS bit through IOCTL 4409h.
cp "$BASE" "$NOSHARE_IMAGE"
mcopy -o -i "$NOSHARE_IMAGE" "$ROOT/src/CMD/MSCDEX/MSCDEX.EXE" ::MSCDEX.EXE
mcopy -o -i "$NOSHARE_IMAGE" "$DRIVER" ::MSCDDRV.SYS
mcopy -o -i "$NOSHARE_IMAGE" "$NOSHARE_PROBE" ::MSCNSHAR.COM
mcopy -o -i "$NOSHARE_IMAGE" "$EXIT_COM" ::QEXIT.COM
printf 'LASTDRIVE=Z\r\nDEVICE=A:\\MSCDDRV.SYS /D:MSCD001\r\n' \
    | mcopy -o -i "$NOSHARE_IMAGE" - ::CONFIG.SYS
printf '@ECHO OFF\r\nCTTY AUX\r\nMSCDEX /D:MSCD001 /L:E\r\nMSCNSHAR.COM\r\nQEXIT.COM\r\n' \
    | mcopy -o -i "$NOSHARE_IMAGE" - ::AUTOEXEC.BAT
timeout 30 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=floppy,index=0,format=raw,file="$NOSHARE_IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$NOSHARE_LOG" 2>&1 || true
grep -Fq 'MSCDEX_NOSHARE_PASS' "$NOSHARE_LOG"
! grep -Fq 'MSCDEX_SHARE_FLAGS_FAIL' "$NOSHARE_LOG"

echo '  PASS: MSCDEX DOS files, ISO/media APIs, EMS maps, and /S sharing state'
