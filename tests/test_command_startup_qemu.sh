#!/bin/bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT_IMG="$OUT/command-startup-boot.img"
B_IMG="$OUT/command-startup-unformatted-b.img"
SERIAL_LOG="$OUT/command-startup-serial.log"
FAIL_BOOT_IMG="$OUT/command-fail-boot.img"
FAIL_SERIAL_LOG="$OUT/command-fail-serial.log"
EXIT_COM="$OUT/command-startup-qexit.com"
ENV_PROBE="$OUT/command-environment-probe.com"
COPY_ASCII_OUT="$OUT/command-copy-destination-ascii.bin"
COPY_BINARY_OUT="$OUT/command-copy-source-ascii.bin"

PASS=0
FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== COMMAND.COM startup-switch tests (QEMU) ==="
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

cp "$FLOPPY" "$BOOT_IMG"
dd if=/dev/zero bs=512 count=2880 of="$B_IMG" status=none
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
nasm -f bin "$REPO_ROOT/tests/command_environment_probe.asm" -o "$ENV_PROBE"
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM
mcopy -o -i "$BOOT_IMG" "$ENV_PROBE" ::ENVPROBE.COM

{
    printf 'EXIT\r\n'
    printf 'ECHO COMMAND_PERMANENT_EXIT_IGNORED\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::PERM.IN

printf '\r\n' | mcopy -o -i "$BOOT_IMG" - ::EMPTY.IN
printf 'ECHO COMMAND_KEEP_CONTINUED\r\nEXIT\r\n' | mcopy -o -i "$BOOT_IMG" - ::KEEP.IN
printf 'RENAME_SOURCE_PAYLOAD\r\n' | mcopy -o -i "$BOOT_IMG" - ::RENSRC.TXT
printf 'RENAME_DEST_PAYLOAD\r\n' | mcopy -o -i "$BOOT_IMG" - ::RENDST.TXT
printf 'DESTMODE' | mcopy -o -i "$BOOT_IMG" - ::DMODE.BIN
printf 'BEFORE\032AFTER' | mcopy -o -i "$BOOT_IMG" - ::SMODE.BIN

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'ECHO ---COMMAND-RENAME-CONFLICT---\r\n'
    printf 'RENAME RENSRC.TXT RENDST.TXT\r\n'
    printf 'IF EXIST RENSRC.TXT ECHO RENAME_SOURCE_PRESERVED\r\n'
    printf 'IF EXIST RENDST.TXT ECHO RENAME_DEST_PRESERVED\r\n'
    printf 'TYPE RENSRC.TXT\r\n'
    printf 'TYPE RENDST.TXT\r\n'
    printf 'ECHO ---COMMAND-RENAME-CONFLICT-END---\r\n'
    printf 'COPY /B DMODE.BIN DASCII.BIN /A\r\n'
    printf 'COPY /A SMODE.BIN DBINARY.BIN /B\r\n'
    printf 'ECHO ---COMMAND-DATE-TIME---\r\n'
    printf 'DATE 01-02-1990\r\n'
    printf 'DATE < EMPTY.IN\r\n'
    printf 'TIME 12:34:56.78\r\n'
    printf 'TIME < EMPTY.IN\r\n'
    printf 'DATE 02-30-1990 < EMPTY.IN\r\n'
    printf 'ECHO COMMAND_INVALID_DATE_RETURNED\r\n'
    printf 'TIME 25:00 < EMPTY.IN\r\n'
    printf 'ECHO COMMAND_INVALID_TIME_RETURNED\r\n'
    printf 'ECHO ---COMMAND-DATE-TIME-END---\r\n'
    printf 'ECHO ---COMMAND-E-MIN---\r\n'
    printf 'COMMAND /E:160 /C ENVPROBE.COM\r\n'
    printf 'ECHO ---COMMAND-E-LARGE---\r\n'
    printf 'COMMAND /E:512 /C ENVPROBE.COM\r\n'
    printf 'COMMAND /K ECHO COMMAND_KEEP_INITIAL < KEEP.IN\r\n'
    printf 'ECHO COMMAND_KEEP_RETURNED\r\n'
    printf 'ECHO COMMAND_PERMANENT_START\r\n'
    printf 'COMMAND /P /D /MSG < PERM.IN\r\n'
    printf 'ECHO COMMAND_PERMANENT_RETURNED_WRONG\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

rm -f "$SERIAL_LOG" "$COPY_ASCII_OUT" "$COPY_BINARY_OUT"
timeout 120 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$B_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null | tee "$SERIAL_LOG" >/dev/null; true

# Exercise /F from a clean interpreter state. The main image deliberately
# performs extensive redirection and DATE/TIME recovery first; keeping the
# critical-error contract independent makes failures attributable to /F.
cp "$FLOPPY" "$FAIL_BOOT_IMG"
mcopy -o -i "$FAIL_BOOT_IMG" "$EXIT_COM" ::QEXIT.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'COMMAND /F /C TYPE B:\\NOFILE.TXT\r\n'
    printf 'ECHO COMMAND_FAIL_ALL_CONTINUED\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$FAIL_BOOT_IMG" - ::AUTOEXEC.BAT
rm -f "$FAIL_SERIAL_LOG"
timeout 30 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$FAIL_BOOT_IMG",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$B_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null | tee "$FAIL_SERIAL_LOG" >/dev/null; true

if grep -q '^COMMAND_PERMANENT_EXIT_IGNORED' "$SERIAL_LOG"; then
    ok "COMMAND /P ignores EXIT and continues reading the permanent shell"
else
    fail "COMMAND /P did not continue after EXIT"
fi

rename_section=$(sed -n '/---COMMAND-RENAME-CONFLICT---/,/---COMMAND-RENAME-CONFLICT-END---/p' "$SERIAL_LOG")
if echo "$rename_section" | grep -q '^RENAME_SOURCE_PRESERVED' \
    && echo "$rename_section" | grep -q '^RENAME_DEST_PRESERVED' \
    && echo "$rename_section" | grep -q '^RENAME_SOURCE_PAYLOAD' \
    && echo "$rename_section" | grep -q '^RENAME_DEST_PAYLOAD'; then
    ok "RENAME existing target preserves both names and exact payloads"
else
    fail "RENAME existing target did not preserve both DOS files"
fi

mcopy -i "$BOOT_IMG" ::DASCII.BIN "$COPY_ASCII_OUT" 2>/dev/null || true
mcopy -i "$BOOT_IMG" ::DBINARY.BIN "$COPY_BINARY_OUT" 2>/dev/null || true
copy_ascii_hex=$(od -An -tx1 "$COPY_ASCII_OUT" 2>/dev/null | tr -d ' \n')
copy_binary_hex=$(od -An -tx1 "$COPY_BINARY_OUT" 2>/dev/null | tr -d ' \n')
if [[ "$copy_ascii_hex" == "444553544d4f4445" ]]; then
    ok "COPY destination /A preserves the exact source bytes on real DOS"
else
    fail "COPY destination /A real-DOS bytes (got: $copy_ascii_hex)"
fi
if [[ "$copy_binary_hex" == "4245464f52451a" ]]; then
    ok "COPY source /A plus destination /B retains one EOF marker on real DOS"
else
    fail "COPY source /A destination /B real-DOS bytes (got: $copy_binary_hex)"
fi

date_time_section=$(sed -n '/---COMMAND-DATE-TIME---/,/---COMMAND-DATE-TIME-END---/p' "$SERIAL_LOG")
if echo "$date_time_section" | grep -q 'Current date is.*01-02-1990'; then
    ok "DATE sets and reports the exact requested calendar date"
else
    fail "DATE did not report 01-02-1990 after setting it"
fi
if echo "$date_time_section" | grep -Eq 'Current time is.*12:34:56\.[0-9][0-9]p'; then
    ok "TIME sets and reports hours, minutes, seconds, and ticking hundredths"
else
    fail "TIME did not report the requested 12:34:56.78 state"
fi
if echo "$date_time_section" | grep -qi 'Invalid date' \
    && grep -q '^COMMAND_INVALID_DATE_RETURNED' "$SERIAL_LOG"; then
    ok "DATE rejects an impossible calendar date and returns after empty input"
else
    fail "DATE did not reject 02-30-1990 deterministically"
fi
if echo "$date_time_section" | grep -qi 'Invalid time' \
    && grep -q '^COMMAND_INVALID_TIME_RETURNED' "$SERIAL_LOG"; then
    ok "TIME rejects an out-of-range hour and returns after empty input"
else
    fail "TIME did not reject 25:00 deterministically"
fi

small_environment=$(sed -n '/---COMMAND-E-MIN---/,/---COMMAND-E-LARGE---/p' "$SERIAL_LOG" \
    | sed -n 's/^COMMAND_ENV_SIZE=//p' | tr -d '\r' | head -1)
large_environment=$(sed -n '/---COMMAND-E-LARGE---/,/COMMAND_PERMANENT_START/p' "$SERIAL_LOG" \
    | sed -n 's/^COMMAND_ENV_SIZE=//p' | tr -d '\r' | head -1)
if [[ "$small_environment" == "000A" && "$large_environment" == "0020" ]]; then
    ok "COMMAND /E assigns the exact requested child environment capacity"
else
    fail "COMMAND /E capacities (160=$small_environment, 512=$large_environment)"
fi

if grep -q '^COMMAND_KEEP_INITIAL' "$SERIAL_LOG" \
    && grep -q '^COMMAND_KEEP_CONTINUED' "$SERIAL_LOG" \
    && grep -q '^COMMAND_KEEP_RETURNED' "$SERIAL_LOG"; then
    ok "COMMAND /K executes its initial command and remains active until EXIT"
else
    fail "COMMAND /K did not preserve the secondary interpreter"
fi
if grep -q '^COMMAND_FAIL_ALL_CONTINUED' "$FAIL_SERIAL_LOG" \
    && grep -q 'Fail on INT 24' "$FAIL_SERIAL_LOG"; then
    ok "COMMAND /F automatically selects Fail for a real critical disk error"
else
    fail "COMMAND /F did not automatically fail the critical disk error"
fi

if grep -q '^COMMAND_PERMANENT_RETURNED_WRONG' "$SERIAL_LOG"; then
    fail "permanent COMMAND unexpectedly returned to its parent batch"
else
    ok "COMMAND /P remains the active interpreter"
fi

if grep -q 'Required parameter missing' "$SERIAL_LOG"; then
    fail "COMMAND /MSG was rejected despite accompanying /P"
else
    ok "COMMAND /P /MSG accepts resident in-memory messages"
fi

if grep -q '^COMMAND_PERMANENT_START' "$SERIAL_LOG"; then
    ok "COMMAND /D startup reached the permanent child without date/time input"
else
    fail "COMMAND /D startup did not reach the permanent child"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
