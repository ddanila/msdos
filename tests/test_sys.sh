#!/bin/bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_ROOT/src"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"
COMMAND_COM="$SRC/CMD/COMMAND/COMMAND.COM"
SYS_BASE="$OUT/floppy-sys-base.img"

SYS_BOOT="$OUT/floppy-sys-boot.img"
SYS_TARGET="$OUT/floppy-sys-target.img"
SYS_LOG="$OUT/sys-serial.log"
SYS_BOOT2_LOG="$OUT/sys-boot2-serial.log"
SYS_SERIAL_IN="$OUT/sys-serial.in"
SYS_SERIAL_OUT="$OUT/sys-serial.out"
SYS_RO_BOOT="$OUT/floppy-sys-readonly-boot.img"
SYS_RO_TARGET="$OUT/floppy-sys-readonly-target.img"
SYS_RO_LOG="$OUT/sys-readonly-serial.log"
SYS_288_BOOT="$OUT/floppy-sys-2880-boot.img"
SYS_288_TARGET="$OUT/floppy-sys-2880-target.img"
SYS_288_LOG="$OUT/sys-2880-serial.log"
SYS_288_BOOT_LOG="$OUT/sys-2880-boot-serial.log"
SYS_288_SERIAL_IN="$OUT/sys-2880-serial.in"
SYS_288_SERIAL_OUT="$OUT/sys-2880-serial.out"
EXIT_COM="$OUT/qemu-exit.com"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

trap 'kill ${QEMU_PID:-} 2>/dev/null; rm -f "$SYS_SERIAL_IN" "$SYS_SERIAL_OUT" "$SYS_288_SERIAL_IN" "$SYS_288_SERIAL_OUT" 2>/dev/null; true' EXIT

echo "=== SYS.COM e2e test ==="

echo "Building test images..."
# Keep drive A at 1.44 MB while testing 1.44/2.88 MB media in drive B.
# Some real BIOSes, and this DOS FORMAT implementation, derive the secondary
# drive's default media behavior from the boot-drive class.
dd if=/dev/zero bs=512 count=2880 of="$SYS_BASE" status=none
dd if="$SRC/BOOT/MSBOOT.BIN" of="$SYS_BASE" bs=1 skip=31744 count=512 conv=notrunc status=none
"$REPO_ROOT/bin/patch-bpb" "$SYS_BASE"
mformat -i "$SYS_BASE" -k ::
mcopy -i "$SYS_BASE" "$SRC/BIOS/IO.SYS" ::IO.SYS
mcopy -i "$SYS_BASE" "$SRC/DOS/MSDOS.SYS" ::MSDOS.SYS
mcopy -i "$SYS_BASE" "$COMMAND_COM" ::COMMAND.COM
mcopy -i "$SYS_BASE" "$SRC/CMD/FORMAT/FORMAT.COM" ::FORMAT.COM
mcopy -i "$SYS_BASE" "$SRC/CMD/SYS/SYS.COM" ::SYS.COM
mcopy -i "$SYS_BASE" "$SRC/CMD/MIRROR/MIRROR.COM" ::MIRROR.COM
cp "$SYS_BASE" "$SYS_BOOT"
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
mcopy -o -i "$SYS_BOOT" "$EXIT_COM" ::QEXIT.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'FORMAT B:\r\n'
    printf 'SYS B:\r\n'
    printf 'ECHO SYS_DEFAULT_SOURCE_DONE\r\n'
    printf 'SYS A: B:\r\n'
    printf 'ECHO SYS_EXPLICIT_SOURCE_DONE\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -i "$SYS_BOOT" - ::AUTOEXEC.BAT

dd if=/dev/zero bs=512 count=2880 of="$SYS_TARGET" status=none

echo "Running FORMAT B: + SYS B: in QEMU (may take ~30s)..."
rm -f "$SYS_LOG" "$SYS_SERIAL_IN" "$SYS_SERIAL_OUT"
mkfifo "$SYS_SERIAL_IN" "$SYS_SERIAL_OUT"
exec 3<>"$SYS_SERIAL_IN"
timeout 45 qemu-system-i386 \
    -drive if=floppy,index=0,format=raw,file="$SYS_BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$SYS_TARGET",cache=writethrough \
    -boot a -m 4 -display none \
    -serial pipe:"$OUT/sys-serial" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null &
QEMU_PID=$!

python3 "$REPO_ROOT/tests/serial_expect.py" \
    "$SYS_SERIAL_IN" "$SYS_SERIAL_OUT" "$SYS_LOG" \
    'press ENTER when ready' '\r\n' \
    'Volume label' '\r\n' \
    'Format another' 'N\r\n'

wait "$QEMU_PID" || true
exec 3>&-

if grep -qi "Format complete" "$SYS_LOG"; then
    ok "FORMAT B: completed"
else
    fail "FORMAT B: did not complete"
    echo "--- serial log ---"; cat "$SYS_LOG"; echo "---"
fi

if [[ $(grep -ci "System transferred" "$SYS_LOG") -eq 2 ]] \
    && grep -q 'SYS_DEFAULT_SOURCE_DONE' "$SYS_LOG" \
    && grep -q 'SYS_EXPLICIT_SOURCE_DONE' "$SYS_LOG"; then
    ok "SYS transferred from both default and explicit source paths"
else
    fail "SYS did not complete both supported command-line arities"
    echo "--- serial log ---"; cat "$SYS_LOG"; echo "---"
fi

if [[ $(dd if="$SYS_TARGET" bs=1 skip=3 count=8 2>/dev/null) == "MSDOS5.0" ]]; then
    ok "SYS retained the MS-DOS 6.22-compatible MSDOS5.0 OEM identifier"
else
    fail "SYS did not install the MSDOS5.0 boot-sector OEM identifier"
fi

mcopy -i "$SYS_TARGET" "$COMMAND_COM" ::COMMAND.COM
mcopy -o -i "$SYS_TARGET" "$EXIT_COM" ::QEXIT.COM
printf '@ECHO OFF\r\nCTTY AUX\r\nVER\r\nQEXIT.COM\r\n' | mcopy -o -i "$SYS_TARGET" - ::AUTOEXEC.BAT

echo "Booting SYS'd floppy..."
rm -f "$SYS_BOOT2_LOG"
timeout 15 qemu-system-i386 \
    -drive if=floppy,index=0,format=raw,file="$SYS_TARGET",cache=writethrough \
    -boot a -m 4 -display none \
    -serial file:"$SYS_BOOT2_LOG" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null; true

if grep -Eq "MS-DOS Version 6\.22" "$SYS_BOOT2_LOG"; then
    ok "SYS'd floppy boots MS-DOS successfully"
else
    fail "SYS'd floppy did not boot as MS-DOS 6.22"
    echo "--- serial log ---"; cat "$SYS_BOOT2_LOG"; echo "---"
fi

echo "Testing SYS-created 2.88 MB boot media..."
cp "$SYS_BASE" "$SYS_288_BOOT"
mcopy -o -i "$SYS_288_BOOT" "$EXIT_COM" ::QEXIT.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'FORMAT B: /F:2.88\r\n'
    printf 'SYS B:\r\n'
    printf 'ECHO SYS_2880_TRANSFER_DONE\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$SYS_288_BOOT" - ::AUTOEXEC.BAT
dd if=/dev/zero bs=512 count=5760 of="$SYS_288_TARGET" status=none

rm -f "$SYS_288_LOG" "$SYS_288_SERIAL_IN" "$SYS_288_SERIAL_OUT"
mkfifo "$SYS_288_SERIAL_IN" "$SYS_288_SERIAL_OUT"
exec 4<>"$SYS_288_SERIAL_IN"
timeout 60 qemu-system-i386 \
    -drive if=floppy,index=0,format=raw,file="$SYS_288_BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$SYS_288_TARGET",cache=writethrough \
    -boot a -m 4 -display none \
    -serial pipe:"$OUT/sys-2880-serial" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null &
QEMU_PID=$!

python3 "$REPO_ROOT/tests/serial_expect.py" \
    "$SYS_288_SERIAL_IN" "$SYS_288_SERIAL_OUT" "$SYS_288_LOG" \
    'press ENTER when ready' '\r\n' \
    'Volume label' '\r\n' \
    'Format another' 'N\r\n'

wait "$QEMU_PID" || true
QEMU_PID=
exec 4>&-

mcopy -o -i "$SYS_288_TARGET" "$COMMAND_COM" ::COMMAND.COM
mcopy -o -i "$SYS_288_TARGET" "$EXIT_COM" ::QEXIT.COM
printf '@ECHO OFF\r\nCTTY AUX\r\nVER\r\nQEXIT.COM\r\n' | \
    mcopy -o -i "$SYS_288_TARGET" - ::AUTOEXEC.BAT

rm -f "$SYS_288_BOOT_LOG"
timeout 20 qemu-system-i386 \
    -drive if=floppy,index=0,format=raw,file="$SYS_288_TARGET",cache=writethrough \
    -boot a -m 4 -display none \
    -serial file:"$SYS_288_BOOT_LOG" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null; true

read -r bps288 total288 media288 spf288 spt288 heads288 < <(python3 -c "
import struct
b = open('$SYS_288_TARGET', 'rb').read(36)
print(struct.unpack_from('<H', b, 11)[0], struct.unpack_from('<H', b, 19)[0],
      b[21], struct.unpack_from('<H', b, 22)[0],
      struct.unpack_from('<H', b, 24)[0], struct.unpack_from('<H', b, 26)[0])
")

if grep -q 'SYS_2880_TRANSFER_DONE' "$SYS_288_LOG" \
    && grep -q 'System transferred' "$SYS_288_LOG" \
    && grep -Eq 'MS-DOS Version 6\.22' "$SYS_288_BOOT_LOG" \
    && [[ "$bps288 $total288 $media288 $spf288 $spt288 $heads288" == '512 5760 240 9 36 2' ]]; then
    ok "SYS creates bootable DOS 6.22 media with exact 2.88 MB geometry"
else
    fail "SYS-created 2.88 MB media did not transfer, boot, or retain exact geometry"
fi

echo "Testing SYS against a read-only target..."
cp "$SYS_BASE" "$SYS_RO_BOOT"
mcopy -o -i "$SYS_RO_BOOT" "$EXIT_COM" ::QEXIT.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'SYS\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SYS_NO_ARG_NONZERO\r\n'
    printf 'SYS /Z\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SYS_SWITCH_NONZERO\r\n'
    printf 'SYS A: B: C:\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SYS_EXTRA_ARG_NONZERO\r\n'
    printf 'SYS A:\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SYS_DEFAULT_DRIVE_NONZERO\r\n'
    printf 'SYS Z:\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SYS_INVALID_DRIVE_NONZERO\r\n'
    printf 'SYS B:\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SYS_READONLY_NONZERO\r\n'
    printf 'ECHO SYS_READONLY_DONE\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$SYS_RO_BOOT" - ::AUTOEXEC.BAT
dd if=/dev/zero bs=512 count=2880 of="$SYS_RO_TARGET" status=none
mformat -i "$SYS_RO_TARGET" -f 1440 ::
readonly_before="$(sha256sum "$SYS_RO_TARGET" | awk '{print $1}')"
rm -f "$SYS_RO_LOG"
(while true; do sleep 0.2; printf 'F\r\n'; done) | \
timeout 25 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$SYS_RO_BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$SYS_RO_TARGET",readonly=on \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null | tee "$SYS_RO_LOG" >/dev/null; true
readonly_after="$(sha256sum "$SYS_RO_TARGET" | awk '{print $1}')"

if grep -q 'SYS_READONLY_DONE' "$SYS_RO_LOG" \
    && ! grep -q 'SYS_READONLY_NONZERO' "$SYS_RO_LOG" \
    && grep -q 'Write protect error writing drive B' "$SYS_RO_LOG" \
    && ! grep -q 'System transferred' "$SYS_RO_LOG" \
    && [[ "$readonly_before" == "$readonly_after" ]]; then
    ok "SYS reports read-only media, preserves its historical zero status, and leaves the target unchanged"
else
    fail "SYS read-only failure contract or target immutability check failed"
fi

if grep -q 'Required parameter missing' "$SYS_RO_LOG" \
    && grep -q 'Parameter format not correct.*\/Z' "$SYS_RO_LOG" \
    && grep -q 'Too many parameters.*C:' "$SYS_RO_LOG" \
    && grep -q 'Cannot specify default drive' "$SYS_RO_LOG" \
    && grep -q 'Invalid drive specification' "$SYS_RO_LOG" \
    && ! grep -q 'SYS_.*_NONZERO' "$SYS_RO_LOG"; then
    ok "SYS diagnoses unsupported forms while preserving its historical zero status"
else
    fail "SYS parser/target diagnostic and status contracts were incomplete"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
