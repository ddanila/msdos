#!/bin/bash
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT="$OUT/undelete-test-boot.img"
TARGET="$OUT/undelete-test-target.img"
TRACK_TARGET="$OUT/undelete-track-target.img"
LOG="$OUT/undelete-test.log"
TRACK_LOG="$OUT/undelete-track.log"
QEXIT="$OUT/undelete-test-qexit.com"
HDELETE="$OUT/undelete-test-hdelete.com"
LATER_TSR="$OUT/undelete-test-later-tsr.com"
PASS=0
FAIL=0

ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

[[ -f "$BASE" ]] || { echo "missing $BASE; run make deploy" >&2; exit 1; }
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
nasm -f bin "$ROOT/tests/delete_handle.asm" -o "$HDELETE"
nasm -f bin "$ROOT/tests/later_int21_tsr.asm" -o "$LATER_TSR"
cp "$BASE" "$BOOT"
mdel -i "$BOOT" ::HELP.HLP >/dev/null 2>&1 || true
mcopy -o -i "$BOOT" "$ROOT/src/CMD/UNDELETE/UNDELETE.COM" ::UNDELETE.COM
mcopy -o -i "$BOOT" "$ROOT/src/CMD/MIRROR/MIRROR.COM" ::MIRROR.COM
mcopy -o -i "$BOOT" "$QEXIT" ::QEXIT.COM
mcopy -o -i "$BOOT" "$HDELETE" ::HDELETE.COM
mcopy -o -i "$BOOT" "$LATER_TSR" ::LATER.COM
printf 'Y\r\nA\r\n' | mcopy -o -i "$BOOT" - ::ANSWERS.TXT

dd if=/dev/zero of="$TARGET" bs=512 count=2880 status=none
mformat -i "$TARGET" -f 1440 ::
printf 'ROOT INTERACTIVE PAYLOAD\r\n' | mcopy -i "$TARGET" - ::ALPHA.TXT
mmd -i "$TARGET" ::SUB
printf 'NESTED EXACT PAYLOAD\r\n' | mcopy -i "$TARGET" - ::SUB/NESTED.DAT
printf 'COLLISION PAYLOAD\r\n' | mcopy -i "$TARGET" - '::SUB/#ESTED.DAT'

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'DEL B:\\ALPHA.TXT\r\n'
    printf 'DEL B:\\SUB\\NESTED.DAT\r\n'
    printf 'UNDELETE B:\\*.TXT /LIST /DOS\r\n'
    printf 'IF ERRORLEVEL 1 ECHO LIST_FAILED\r\n'
    printf 'UNDELETE B:\\ALPHA.TXT /DOS < A:\\ANSWERS.TXT\r\n'
    printf 'IF ERRORLEVEL 1 ECHO INTERACTIVE_FAILED\r\n'
    printf 'B:\r\n'
    printf 'CD \\SUB\r\n'
    printf 'A:\r\n'
    printf 'UNDELETE B:*.DAT /ALL\r\n'
    printf 'IF ERRORLEVEL 1 ECHO NESTED_FAILED\r\n'
    printf 'ECHO UNDELETE_TEST_DONE\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT

timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$LOG" 2>&1 || true

if grep -q '?LPHA.TXT  26 bytes' "$LOG" && ! grep -q 'LIST_FAILED' "$LOG"; then
    ok "/LIST reports the deleted DOS directory entry"
else
    fail "/LIST contract"
fi
if grep -q 'Restored ALPHA.TXT' "$LOG" && ! grep -q 'INTERACTIVE_FAILED' "$LOG"; then
    ok "/DOS accepts an interactive first character"
else
    fail "/DOS interactive recovery"
fi
if grep -q 'Restored %ESTED.DAT' "$LOG" && ! grep -q 'NESTED_FAILED' "$LOG"; then
    ok "/ALL uses the next collision-free replacement in a current subdirectory"
else
    fail "/ALL nested recovery"
fi

root_payload="$(mcopy -i "$TARGET" ::ALPHA.TXT - 2>/dev/null | tr -d '\r\n')"
nested_payload="$(mcopy -i "$TARGET" '::SUB/%ESTED.DAT' - 2>/dev/null | tr -d '\r\n')"
if [[ "$root_payload" == 'ROOT INTERACTIVE PAYLOAD' ]]; then
    ok "interactive recovery preserves the exact root payload"
else
    fail "root payload mismatch"
fi
if [[ "$nested_payload" == 'NESTED EXACT PAYLOAD' ]]; then
    ok "automatic recovery preserves the exact nested payload"
else
    fail "nested payload mismatch"
fi

dd if=/dev/zero of="$TRACK_TARGET" bs=512 count=2880 status=none
mformat -i "$TRACK_TARGET" -f 1440 ::
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'UNDELETE /TB-2\r\n'
    printf 'IF ERRORLEVEL 1 ECHO PUBLIC_TRACK_LOAD_FAILED\r\n'
    printf 'UNDELETE /STATUS\r\n'
    printf 'IF ERRORLEVEL 1 ECHO PUBLIC_TRACK_STATUS_FAILED\r\n'
    printf 'ECHO PUBLIC TRACKER PAYLOAD>B:\\PUBLIC.TXT\r\n'
    printf 'DEL B:\\PUBLIC.TXT\r\n'
    printf 'UNDELETE B:\\PUBLIC.TXT /ALL\r\n'
    printf 'IF ERRORLEVEL 1 ECHO PUBLIC_TRACK_RESTORE_FAILED\r\n'
    printf 'UNDELETE /UNLOAD\r\n'
    printf 'IF ERRORLEVEL 1 ECHO PUBLIC_TRACK_UNLOAD_FAILED\r\n'
    printf 'UNDELETE /TB-0\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO PUBLIC_TRACK_ZERO_ACCEPTED\r\n'
    printf 'UNDELETE /TB-1000\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO PUBLIC_TRACK_LARGE_ACCEPTED\r\n'
    printf 'UNDELETE /TB\r\n'
    printf 'IF ERRORLEVEL 1 ECHO PUBLIC_TRACK_DEFAULT_FAILED\r\n'
    printf 'UNDELETE /UNLOAD\r\n'
    printf 'MIRROR /TB-1\r\n'
    printf 'IF EXIST B:\\PCTRACKR.DEL ECHO TRACK_FILE_CREATED_EARLY\r\n'
    printf 'ECHO HANDLE API PAYLOAD>B:\\HANDLE.TXT\r\n'
    printf 'HDELETE.COM\r\n'
    printf 'UNDELETE B:\\HANDLE.TXT /LIST\r\n'
    printf 'IF ERRORLEVEL 1 ECHO HANDLE_TRACK_FAILED\r\n'
    printf 'ECHO FIRST TSR PAYLOAD>B:\\FIRST.TXT\r\n'
    printf 'DEL B:\\FIRST.TXT\r\n'
    printf 'ECHO SECOND TSR PAYLOAD>B:\\SECOND.TXT\r\n'
    printf 'DEL B:\\SECOND.TXT\r\n'
    printf 'UNDELETE B:\\FIRST.TXT /LIST\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO ROTATION_FAILED\r\n'
    printf 'UNDELETE B:\\SECOND.TXT /ALL\r\n'
    printf 'IF ERRORLEVEL 1 ECHO TSR_RESTORE_FAILED\r\n'
    printf 'MIRROR /U\r\n'
    printf 'IF ERRORLEVEL 1 ECHO TSR_UNLOAD_FAILED\r\n'
    printf 'ECHO AFTER UNLOAD PAYLOAD>B:\\AFTER.TXT\r\n'
    printf 'DEL B:\\AFTER.TXT\r\n'
    printf 'UNDELETE B:\\AFTER.TXT /LIST\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO TSR_STILL_ACTIVE\r\n'
    printf 'MIRROR /TB-1\r\n'
    printf 'LATER.COM\r\n'
    printf 'MIRROR /U\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO STACK_UNLOAD_SUCCEEDED\r\n'
    printf 'IF NOT EXIST B:\\PCTRACKR.ACT ECHO STACK_STATE_REMOVED\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT
timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TRACK_TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$TRACK_LOG" 2>&1 || true
tracked_payload="$(mcopy -i "$TRACK_TARGET" ::SECOND.TXT - 2>/dev/null | tr -d '\r\n')"
public_payload="$(mcopy -i "$TRACK_TARGET" ::PUBLIC.TXT - 2>/dev/null | tr -d '\r\n')"
if grep -q 'Delete Tracker enabled on drive B: for 2 entries' "$TRACK_LOG" &&
   grep -q 'Drive B: Delete Tracker is active' "$TRACK_LOG" &&
   grep -q 'The Undelete memory-resident program was unloaded' "$TRACK_LOG" &&
   grep -q 'Delete Tracker enabled on drive B: for 75 entries' "$TRACK_LOG" &&
   [[ "$public_payload" == 'PUBLIC TRACKER PAYLOAD' ]] &&
   ! grep -Eq 'PUBLIC_TRACK_(LOAD|STATUS|RESTORE|UNLOAD|DEFAULT)_FAILED|PUBLIC_TRACK_(ZERO|LARGE)_ACCEPTED' "$TRACK_LOG"; then
    ok "retail /T defaults and bounds, /STATUS, and /UNLOAD manage Delete Tracker"
else
    fail "public Delete Tracker management"
fi
if grep -q 'Deletion tracking enabled for drive B:' "$TRACK_LOG" &&
   grep -q 'Restored SECOND.TXT' "$TRACK_LOG" &&
   grep -q 'Deletion tracking disabled.' "$TRACK_LOG" &&
   [[ "$tracked_payload" == 'SECOND TSR PAYLOAD' ]] &&
   ! mdir -i "$TRACK_TARGET" ::PCTRACKR.ACT >/dev/null 2>&1 &&
   grep -q 'HANDLE.TXT' "$TRACK_LOG" &&
   grep -q 'unload resident programs loaded after deletion tracking first' "$TRACK_LOG" &&
   ! grep -Eq 'TRACK_FILE_CREATED_EARLY|HANDLE_TRACK_FAILED|ROTATION_FAILED|TSR_(RESTORE|UNLOAD)_FAILED|TSR_STILL_ACTIVE|STACK_(UNLOAD_SUCCEEDED|STATE_REMOVED)' "$TRACK_LOG"; then
    ok "resident tracking captures post-install deletes, rotates, restores, and unloads"
else
    fail "resident deletion-tracking lifecycle"
fi

echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
