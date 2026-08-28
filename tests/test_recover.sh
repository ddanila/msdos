#!/bin/bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"

BOOT_IMG="$OUT/recover-boot.img"
SERIAL_LOG="$OUT/recover-serial.log"
DRIVE_IMG="$OUT/recover-drive.img"
EXIT_COM="$OUT/qemu-exit.com"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== RECOVER E2E tests (QEMU) ==="

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

echo "Building test image..."
cp "$FLOPPY" "$BOOT_IMG"
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
dd if=/dev/zero of="$DRIVE_IMG" bs=512 count=2880 status=none
mformat -i "$DRIVE_IMG" -f 1440 ::

printf 'RECOVER TEST FILE CONTENTS\r\n' | mcopy -o -i "$BOOT_IMG" - ::TESTFILE.TXT
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM
printf 'RECOVER DRIVE ALPHA\r\n' | mcopy -o -i "$DRIVE_IMG" - ::ALPHA.TXT
printf 'RECOVER DRIVE BETA\r\n' | mcopy -o -i "$DRIVE_IMG" - ::BETA.TXT

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'

    printf 'ECHO ---RECOVER-FILE---\r\n'
    printf 'RECOVER A:TESTFILE.TXT\r\n'
    printf 'ECHO RECOVER_FILE_DONE\r\n'

    printf 'ECHO ---RECOVER-DRIVE---\r\n'
    printf 'RECOVER B:\r\n'
    printf 'DIR B:\\FILE*.REC\r\n'
    printf 'ECHO RECOVER_DRIVE_DONE\r\n'

    printf 'ECHO ===DONE===\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

echo "Booting QEMU (may take ~90s)..."
rm -f "$SERIAL_LOG"
(while true; do sleep 0.5; printf '\r\n'; done) | \
timeout 120 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$DRIVE_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null | tee "$SERIAL_LOG" > /dev/null; true

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi

echo ""
echo "--- RECOVER serial log checks ---"

if grep -qi "Press any key" "$SERIAL_LOG"; then
    ok "RECOVER (keypress prompt appeared on serial)"
else
    fail "RECOVER (keypress prompt not seen — CTTY AUX routing issue?)"
fi

if grep -qi "bytes recovered" "$SERIAL_LOG"; then
    ok "RECOVER A:TESTFILE.TXT ('bytes recovered' message printed)"
else
    fail "RECOVER A:TESTFILE.TXT (expected 'bytes recovered' in output)"
fi

if grep -q "RECOVER_FILE_DONE" "$SERIAL_LOG"; then
    ok "RECOVER A:TESTFILE.TXT (batch continued after recovery)"
else
    fail "RECOVER A:TESTFILE.TXT (batch hung or crashed)"
fi

if sed -n '/---RECOVER-DRIVE---/,/RECOVER_DRIVE_DONE/p' "$SERIAL_LOG" \
    | grep -Eqi '[12] file\(s\) recovered' \
    && grep -q 'RECOVER_DRIVE_DONE' "$SERIAL_LOG"; then
    ok "RECOVER B: rebuilt the private drive directory"
else
    fail "RECOVER B: did not complete whole-drive recovery"
fi

file_contents="$(mtype -i "$BOOT_IMG" ::TESTFILE.TXT 2>/dev/null | tr -d '\r' || true)"
if [[ "$file_contents" == 'RECOVER TEST FILE CONTENTS' ]]; then
    ok "RECOVER file mode preserved the exact recovered bytes"
else
    fail "RECOVER file mode contents differ: '$file_contents'"
fi

drive_listing="$(mdir -b -i "$DRIVE_IMG" :: 2>/dev/null || true)"
drive_contents="$({
    mtype -i "$DRIVE_IMG" ::FILE0001.REC 2>/dev/null || true
    mtype -i "$DRIVE_IMG" ::FILE0002.REC 2>/dev/null || true
} | tr -d '\r')"
if ! grep -qi 'ALPHA.TXT\|BETA.TXT' <<<"$drive_listing" \
    && grep -q 'FILE0001.REC' <<<"$drive_listing" \
    && grep -q 'FILE0002.REC' <<<"$drive_listing" \
    && grep -q 'RECOVER DRIVE ALPHA' <<<"$drive_contents" \
    && grep -q 'RECOVER DRIVE BETA' <<<"$drive_contents"; then
    ok "RECOVER drive mode renamed both chains and preserved their bytes"
else
    fail "RECOVER drive mode persistence mismatch: $drive_listing"
fi

if grep -q "===DONE===" "$SERIAL_LOG"; then
    ok "Batch reached ===DONE==="
else
    fail "Batch did NOT reach ===DONE=== (hung or crashed early)"
    echo "--- last 20 lines of serial log ---"
    tail -20 "$SERIAL_LOG"
    echo "---"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
