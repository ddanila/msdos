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
FAIL_SERIAL_IN="$OUT/command-fail-serial.in"
FAIL_SERIAL_OUT="$OUT/command-fail-serial.out"
EXIT_COM="$OUT/command-startup-qexit.com"
ENV_PROBE="$OUT/command-environment-probe.com"
CRITICAL_ABI_PROBE="$OUT/command-critical-abi.com"
COPY_ASCII_OUT="$OUT/command-copy-destination-ascii.bin"
COPY_BINARY_OUT="$OUT/command-copy-source-ascii.bin"

PASS=0
FAIL=0
CRITICAL_ABI=${COMMAND_CRITICAL_ABI:-0}
CRITICAL_MESSAGES=${COMMAND_CRITICAL_MESSAGES:-disk}
CRITICAL_NO_HOOK=${COMMAND_CRITICAL_NO_HOOK:-0}
CRITICAL_ACTION=${COMMAND_CRITICAL_ACTION:-fail}
if [[ "$CRITICAL_ABI" != 0 && "$CRITICAL_ABI" != 1 ]] \
    || [[ "$CRITICAL_MESSAGES" != disk && "$CRITICAL_MESSAGES" != resident ]] \
    || [[ "$CRITICAL_NO_HOOK" != 0 && "$CRITICAL_NO_HOOK" != 1 ]] \
    || [[ "$CRITICAL_ACTION" != fail && "$CRITICAL_ACTION" != retry ]]; then
    echo 'ERROR: invalid critical ABI diagnostic configuration'
    exit 1
fi
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== COMMAND.COM startup-switch tests (QEMU) ==="
echo "Critical ABI=$CRITICAL_ABI messages=$CRITICAL_MESSAGES no-hook=$CRITICAL_NO_HOOK action=$CRITICAL_ACTION"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

cp "$FLOPPY" "$BOOT_IMG"
dd if=/dev/zero bs=512 count=2880 of="$B_IMG" status=none
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
nasm -f bin "$REPO_ROOT/tests/command_environment_probe.asm" -o "$ENV_PROBE"
critical_defines=(-f bin)
if [[ "$CRITICAL_ACTION" == retry ]]; then
    critical_defines+=(-DFIRST_CRITICAL_RESPONSE=1)
fi
if [[ "$CRITICAL_NO_HOOK" == 1 ]]; then
    critical_defines+=(-DNO_CRITICAL_HOOK)
fi
nasm "${critical_defines[@]}" "$REPO_ROOT/tests/command_critical_abi_probe.asm" -o "$CRITICAL_ABI_PROBE"
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
    printf 'ENVPROBE.COM > REOUT.TXT\r\n'
    printf 'ECHO REDIRECT_APPEND>>REOUT.TXT\r\n'
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

# Exercise a real INT 24h in the permanent DOS-high interpreter. This forces
# the text lookup through COMMAND's relocated HMA catalog; the serial
# coordinator selects Fail at the prompt and proves normal return.
cp "$FLOPPY" "$FAIL_BOOT_IMG"
mcopy -o -i "$FAIL_BOOT_IMG" "$EXIT_COM" ::QEXIT.COM
mcopy -o -i "$FAIL_BOOT_IMG" "$CRITICAL_ABI_PROBE" ::CRITABI.COM
if [[ -n ${COMMAND_CRITICAL_LOADER:-} ]]; then
    mcopy -o -i "$FAIL_BOOT_IMG" "$COMMAND_CRITICAL_LOADER" ::CRITHIGH.COM
fi
{
    printf 'DEVICE=A:\\HIMEM.SYS\r\n'
    printf 'DOS=HIGH\r\n'
    if [[ "$CRITICAL_MESSAGES" == resident ]]; then
        printf 'SHELL=A:\\COMMAND.COM /P /MSG\r\n'
    fi
} | mcopy -o -i "$FAIL_BOOT_IMG" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    if [[ -n ${COMMAND_CRITICAL_LOADER:-} ]]; then
        printf 'CRITHIGH.COM\r\n'
    fi
    if [[ "$CRITICAL_ABI" == 1 ]]; then
        printf 'CRITABI.COM > CRITABI.TXT\r\n'
        printf 'TYPE CRITABI.TXT\r\n'
    fi
    printf 'TYPE B:\\NOFILE.TXT\r\n'
    printf 'ECHO COMMAND_CRITICAL_HMA_CONTINUED\r\n'
    printf 'COMMAND /F /C TYPE B:\\NOFILE.TXT\r\n'
    printf 'ECHO COMMAND_FAIL_ALL_CONTINUED\r\n'
    if [[ -n ${COMMAND_CRITICAL_LOADER:-} ]]; then
        printf 'CRITHIGH.COM /CHECK\r\n'
    fi
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$FAIL_BOOT_IMG" - ::AUTOEXEC.BAT
rm -f "$FAIL_SERIAL_LOG" "$FAIL_SERIAL_IN" "$FAIL_SERIAL_OUT"
mkfifo "$FAIL_SERIAL_IN" "$FAIL_SERIAL_OUT"
exec 3<>"$FAIL_SERIAL_IN"
timeout 30 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$FAIL_BOOT_IMG",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$B_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial pipe:"$OUT/command-fail-serial" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null &
FAIL_QEMU_PID=$!
critical_responses=('Abort, Retry, Fail?' 'F\r')
if [[ "$CRITICAL_ABI" == 1 ]]; then
    if [[ "$CRITICAL_ACTION" == retry ]]; then
        critical_responses=('Abort, Retry, Fail?' 'R\r')
    fi
    critical_responses+=('Abort, Retry, Fail?' 'F\r' 'Abort, Retry, Fail?' 'F\r')
fi
python3 "$REPO_ROOT/tests/serial_expect.py" \
    "$FAIL_SERIAL_IN" "$FAIL_SERIAL_OUT" "$FAIL_SERIAL_LOG" \
    "${critical_responses[@]}"
wait "$FAIL_QEMU_PID" || true
exec 3>&-
rm -f "$FAIL_SERIAL_IN" "$FAIL_SERIAL_OUT"

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

redirection_output=$(mtype -i "$BOOT_IMG" ::REOUT.TXT 2>/dev/null | tr -d '\r')
if echo "$redirection_output" | grep -q '^COMMAND_ENV_SIZE=' \
    && echo "$redirection_output" | grep -q '^REDIRECT_APPEND$'; then
    ok "output redirection survives external EXEC/reload and append"
else
    fail "output redirection did not survive external EXEC/reload and append"
fi

if grep -q '^COMMAND_KEEP_INITIAL' "$SERIAL_LOG" \
    && grep -q '^COMMAND_KEEP_CONTINUED' "$SERIAL_LOG" \
    && grep -q '^COMMAND_KEEP_RETURNED' "$SERIAL_LOG"; then
    ok "COMMAND /K executes its initial command and remains active until EXIT"
else
    fail "COMMAND /K did not preserve the secondary interpreter"
fi
if grep -q '^COMMAND_CRITICAL_HMA_CONTINUED' "$FAIL_SERIAL_LOG" \
    && grep -q '^COMMAND_FAIL_ALL_CONTINUED' "$FAIL_SERIAL_LOG" \
    && grep -q 'General failure reading drive B' "$FAIL_SERIAL_LOG" \
    && grep -q 'Fail on INT 24' "$FAIL_SERIAL_LOG"; then
    ok "DOS-high permanent COMMAND survives critical errors (messages=$CRITICAL_MESSAGES)"
else
    fail "DOS-high permanent COMMAND did not survive the critical disk error"
fi

if grep -q '^COMMAND_PERMANENT_RETURNED_WRONG' "$SERIAL_LOG"; then
    fail "permanent COMMAND unexpectedly returned to its parent batch"
else
    ok "COMMAND /P remains the active interpreter"
fi

if [[ "$CRITICAL_ABI" == 1 ]]; then
    if [[ -n ${COMMAND_CRITICAL_LOADER:-} ]]; then
        if grep -q '^COMMAND_CRITICAL_BODY_HIGH' "$FAIL_SERIAL_LOG" \
            && grep -q '^COMMAND_CRITICAL_OLD_BODY_UNTOUCHED' "$FAIL_SERIAL_LOG" \
            && ! grep -q 'COMMAND_CRITICAL_BODY_LOAD_FAIL' "$FAIL_SERIAL_LOG"; then
            ok "development critical body installed in HMA with old low body poisoned"
        else
            fail "development critical body HMA installation"
        fi
    fi
    if grep -q '^COMMAND_CRITICAL_ABI_PASS' "$FAIL_SERIAL_LOG" \
        && ! grep -q 'COMMAND_CRITICAL_ABI_FAIL' "$FAIL_SERIAL_LOG"; then
        ok "critical $CRITICAL_ACTION preserves foreign stack/registers and JFNs across repeated opens"
    else
        fail "critical-error return ABI or redirected JFN restoration"
    fi
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
