#!/bin/bash
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT="$OUT/undelete-test-boot.img"
TARGET="$OUT/undelete-test-target.img"
TRACK_TARGET="$OUT/undelete-track-target.img"
SENTRY_TARGET="$OUT/undelete-sentry-target.img"
SENTRY_LOAD_TARGET="$OUT/undelete-sentry-load-target.img"
SENTRY_LIMIT_TARGET="$OUT/undelete-sentry-limit-target.img"
LOG="$OUT/undelete-test.log"
TRACK_LOG="$OUT/undelete-track.log"
SENTRY_LOG="$OUT/undelete-sentry.log"
SENTRY_LOAD_LOG="$OUT/undelete-sentry-load.log"
SENTRY_LIMIT_LOG="$OUT/undelete-sentry-limit.log"
SENTRY_AGE_LOG="$OUT/undelete-sentry-age.log"
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
printf '[mirror.drives]\r\nB=3\r\n[defaults]\r\nd.sentry=FALSE\r\nd.tracker=TRUE\r\n' |
    mcopy -o -i "$BOOT" - ::UNDELETE.INI

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

if grep -Eq '\?LPHA\.TXT +26 ' "$LOG" &&
   grep -q 'Using the MS-DOS directory method' "$LOG" &&
   ! grep -q 'LIST_FAILED' "$LOG"; then
    ok "/LIST reports the deleted DOS directory entry"
else
    fail "/LIST contract"
fi
if grep -q 'File successfully undeleted' "$LOG" && ! grep -q 'INTERACTIVE_FAILED' "$LOG"; then
    ok "/DOS accepts an interactive first character"
else
    fail "/DOS interactive recovery"
fi
if grep -Fq 'File Specifications: *.DAT' "$LOG" &&
   grep -Eq '\?ESTED\.DAT +22 ' "$LOG" && ! grep -q 'NESTED_FAILED' "$LOG"; then
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
    printf 'UNDELETE /LOAD\r\n'
    printf 'IF ERRORLEVEL 1 ECHO PUBLIC_TRACK_LOAD_FAILED\r\n'
    printf 'UNDELETE /STATUS\r\n'
    printf 'IF ERRORLEVEL 1 ECHO PUBLIC_TRACK_STATUS_FAILED\r\n'
    printf 'ECHO PUBLIC TRACKER PAYLOAD>B:\\PUBLIC.TXT\r\n'
    printf 'DEL B:\\PUBLIC.TXT\r\n'
    printf 'UNDELETE B:\\PUBLIC.TXT /ALL\r\n'
    printf 'IF ERRORLEVEL 1 ECHO PUBLIC_TRACK_RESTORE_FAILED\r\n'
    printf 'UNDELETE /UNLOAD\r\n'
    printf 'IF ERRORLEVEL 1 ECHO PUBLIC_TRACK_UNLOAD_FAILED\r\n'
    printf 'ECHO [mirror.drives]>A:\\UNDELETE.INI\r\n'
    printf 'ECHO B=1000>>A:\\UNDELETE.INI\r\n'
    printf 'ECHO [defaults]>>A:\\UNDELETE.INI\r\n'
    printf 'ECHO d.tracker=TRUE>>A:\\UNDELETE.INI\r\n'
    printf 'ECHO d.sentry=FALSE>>A:\\UNDELETE.INI\r\n'
    printf 'UNDELETE /LOAD\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO PUBLIC_BAD_INI_ACCEPTED\r\n'
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
if grep -q 'Delete Tracker enabled on drive B: for 3 entries' "$TRACK_LOG" &&
   grep -q 'Drive B: Delete Tracker is active' "$TRACK_LOG" &&
   grep -q 'The Undelete memory-resident program was unloaded' "$TRACK_LOG" &&
   grep -q 'Delete Tracker enabled on drive B: for 75 entries' "$TRACK_LOG" &&
   [[ "$public_payload" == 'PUBLIC TRACKER PAYLOAD' ]] &&
   grep -q 'invalid tracker entry count in UNDELETE.INI' "$TRACK_LOG" &&
   ! grep -Eq 'PUBLIC_TRACK_(LOAD|STATUS|RESTORE|UNLOAD|DEFAULT)_FAILED|PUBLIC_TRACK_(ZERO|LARGE)_ACCEPTED|PUBLIC_BAD_INI_ACCEPTED' "$TRACK_LOG"; then
    ok "retail /LOAD, /T defaults and bounds, /STATUS, and /UNLOAD manage Delete Tracker"
else
    fail "public Delete Tracker management"
fi
if grep -q 'Deletion tracking enabled for drive B:' "$TRACK_LOG" &&
   grep -q 'SECOND.TXT' "$TRACK_LOG" &&
   grep -q 'File successfully undeleted' "$TRACK_LOG" &&
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

dd if=/dev/zero of="$SENTRY_TARGET" bs=512 count=2880 status=none
mformat -i "$SENTRY_TARGET" -f 1440 ::
mmd -i "$SENTRY_TARGET" ::SUB
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'UNDELETE /SB\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SENTRY_LOAD_FAILED\r\n'
    printf 'UNDELETE /STATUS\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SENTRY_STATUS_FAILED\r\n'
    printf 'ECHO DELETE SENTRY EXACT PAYLOAD>B:\\SENTRY.TXT\r\n'
    printf 'ATTRIB -A B:\\SENTRY.TXT\r\n'
    printf 'DEL B:\\SENTRY.TXT\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SENTRY_DELETE_FAILED\r\n'
    printf 'IF EXIST B:\\SENTRY.TXT ECHO SENTRY_ORIGINAL_REMAINS\r\n'
    printf 'IF NOT EXIST B:\\SENTRY\\CONTROL.FIL ECHO SENTRY_CONTROL_MISSING\r\n'
    printf 'UNDELETE B:\\SENTRY.TXT /LIST /DS\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SENTRY_LIST_FAILED\r\n'
    printf 'UNDELETE B:\\SENTRY.TXT /ALL\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SENTRY_RESTORE_FAILED\r\n'
    printf 'ECHO NESTED SENTRY EXACT PAYLOAD>B:\\SUB\\NESTED.DAT\r\n'
    printf 'ATTRIB -A B:\\SUB\\NESTED.DAT\r\n'
    printf 'DEL B:\\SUB\\NESTED.DAT\r\n'
    printf 'UNDELETE B:\\SUB\\NESTED.DAT /LIST /DS\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SENTRY_NESTED_LIST_FAILED\r\n'
    printf 'UNDELETE B:\\SUB\\NESTED.DAT /ALL\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SENTRY_NESTED_RESTORE_FAILED\r\n'
    printf 'ECHO EXCLUDED TEMPORARY PAYLOAD>B:\\SKIP.TMP\r\n'
    printf 'ATTRIB -A B:\\SKIP.TMP\r\n'
    printf 'DEL B:\\SKIP.TMP\r\n'
    printf 'IF EXIST B:\\SKIP.TMP ECHO SENTRY_FILTER_DELETE_FAILED\r\n'
    printf 'UNDELETE B:\\SKIP.TMP /LIST /DS\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO SENTRY_FILTER_PROTECTED\r\n'
    printf 'ECHO PURGE SENTRY PAYLOAD>B:\\PURGE.TXT\r\n'
    printf 'ATTRIB -A B:\\PURGE.TXT\r\n'
    printf 'DEL B:\\PURGE.TXT\r\n'
    printf 'UNDELETE /PURGEB\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SENTRY_PURGE_FAILED\r\n'
    printf 'UNDELETE /UNLOAD\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SENTRY_UNLOAD_FAILED\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT
timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$SENTRY_TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$SENTRY_LOG" 2>&1 || true
sentry_payload="$(mcopy -i "$SENTRY_TARGET" ::SENTRY.TXT - 2>/dev/null | tr -d '\r\n')"
nested_sentry_payload="$(mcopy -i "$SENTRY_TARGET" ::SUB/NESTED.DAT - 2>/dev/null | tr -d '\r\n')"
if grep -q 'Delete Sentry enabled on drive B:' "$SENTRY_LOG" &&
   grep -q 'Drive B: Delete Sentry is active' "$SENTRY_LOG" &&
   grep -q 'SENTRY.TXT' "$SENTRY_LOG" &&
   grep -q 'NESTED.DAT' "$SENTRY_LOG" &&
   grep -q 'Protected by Delete Sentry' "$SENTRY_LOG" &&
   [[ "$(grep -c 'File successfully undeleted' "$SENTRY_LOG")" -ge 2 ]] &&
   grep -q 'Purged 1 Delete Sentry file(s) from drive B:' "$SENTRY_LOG" &&
   grep -q 'The Undelete memory-resident program was unloaded' "$SENTRY_LOG" &&
   [[ "$sentry_payload" == 'DELETE SENTRY EXACT PAYLOAD' ]] &&
   [[ "$nested_sentry_payload" == 'NESTED SENTRY EXACT PAYLOAD' ]] &&
   ! mdir -i "$SENTRY_TARGET" ::PURGE.TXT >/dev/null 2>&1 &&
   ! mdir -i "$SENTRY_TARGET" '::SENTRY/#0000003.MS' >/dev/null 2>&1 &&
   ! grep -Eq 'SENTRY_(LOAD|STATUS|DELETE|LIST|RESTORE|PURGE|UNLOAD|NESTED_LIST|NESTED_RESTORE|FILTER_DELETE)_FAILED|SENTRY_(ORIGINAL_REMAINS|CONTROL_MISSING|FILTER_PROTECTED)' "$SENTRY_LOG"; then
    ok "retail /S, /DS selection, automatic restore, and /PURGE preserve SENTRY semantics"
else
    fail "Delete Sentry interception"
fi

dd if=/dev/zero of="$SENTRY_LOAD_TARGET" bs=512 count=2880 status=none
mformat -i "$SENTRY_LOAD_TARGET" -f 1440 ::
mdel -i "$BOOT" ::UNDELETE.INI >/dev/null 2>&1 || true
{
    printf '@ECHO OFF\r\nCTTY AUX\r\nB:\r\n'
    printf 'A:\\UNDELETE /LOAD\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SENTRY_DEFAULT_LOAD_FAILED\r\n'
    printf 'ECHO DEFAULT INI SENTRY PAYLOAD>DEFAULT.TXT\r\n'
    printf 'A:\\ATTRIB -A DEFAULT.TXT\r\n'
    printf 'DEL DEFAULT.TXT\r\n'
    printf 'A:\\UNDELETE DEFAULT.TXT /LIST /DS\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SENTRY_DEFAULT_LIST_FAILED\r\n'
    printf 'A:\\UNDELETE /UNLOAD\r\n'
    printf 'A:\\QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT
timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$SENTRY_LOAD_TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$SENTRY_LOAD_LOG" 2>&1 || true
default_sentry_payload="$(mcopy -i "$SENTRY_LOAD_TARGET" '::SENTRY/#0000001.MS' - 2>/dev/null | tr -d '\r\n')"
default_ini="$(mcopy -i "$BOOT" ::UNDELETE.INI - 2>/dev/null | tr -d '\r')"
if grep -q 'Delete Sentry enabled on drive B:' "$SENTRY_LOAD_LOG" &&
   grep -q 'DEFAULT.TXT' "$SENTRY_LOAD_LOG" &&
   grep -q 'Protected by Delete Sentry' "$SENTRY_LOAD_LOG" &&
   [[ "$default_sentry_payload" == 'DEFAULT INI SENTRY PAYLOAD' ]] &&
   grep -q '\[sentry.drives\]' <<<"$default_ini" &&
   grep -q 'd.sentry=TRUE' <<<"$default_ini" &&
   ! mdir -i "$SENTRY_LOAD_TARGET" ::UNDELETE.INI >/dev/null 2>&1 &&
   ! grep -Eq 'SENTRY_DEFAULT_(LOAD|LIST)_FAILED' "$SENTRY_LOAD_LOG"; then
    ok "retail /LOAD creates and applies the default Sentry UNDELETE.INI"
else
    fail "default Sentry UNDELETE.INI lifecycle"
fi

dd if=/dev/zero of="$SENTRY_LIMIT_TARGET" bs=512 count=2880 status=none
mformat -i "$SENTRY_LIMIT_TARGET" -f 1440 ::
dd if=/dev/zero of="$OUT/undelete-sentry-large.bin" bs=1024 count=10 status=none
mcopy -i "$SENTRY_LIMIT_TARGET" "$OUT/undelete-sentry-large.bin" ::ONE.DAT
mcopy -i "$SENTRY_LIMIT_TARGET" "$OUT/undelete-sentry-large.bin" ::TWO.DAT
printf '[sentry.drives]\r\nB=\r\n[sentry.files]\r\n*.*\r\n[configuration]\r\narchive=TRUE\r\ndays=7\r\npercentage=1\r\n[defaults]\r\nd.sentry=TRUE\r\nd.tracker=FALSE\r\n' |
    mcopy -o -i "$BOOT" - ::UNDELETE.INI
{
    printf '@ECHO OFF\r\nCTTY AUX\r\nB:\r\n'
    printf 'A:\\UNDELETE /LOAD\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SENTRY_LIMIT_LOAD_FAILED\r\n'
    printf 'DEL ONE.DAT\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SENTRY_LIMIT_FIRST_DELETE_FAILED\r\n'
    printf 'DEL TWO.DAT\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SENTRY_LIMIT_SECOND_DELETE_FAILED\r\n'
    printf 'A:\\UNDELETE ONE.DAT /LIST /DS\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO SENTRY_LIMIT_OLDEST_REMAINS\r\n'
    printf 'A:\\UNDELETE TWO.DAT /LIST /DS\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SENTRY_LIMIT_NEWEST_MISSING\r\n'
    printf 'A:\\UNDELETE /UNLOAD\r\n'
    printf 'A:\\QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT
timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$SENTRY_LIMIT_TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$SENTRY_LIMIT_LOG" 2>&1 || true
newest_size="$(mcopy -i "$SENTRY_LIMIT_TARGET" '::SENTRY/#0000002.MS' - 2>/dev/null | wc -c | tr -d ' ')"
if grep -q 'No Delete Sentry files were found' "$SENTRY_LIMIT_LOG" &&
   grep -q 'TWO.DAT' "$SENTRY_LIMIT_LOG" &&
   grep -q 'Protected by Delete Sentry' "$SENTRY_LIMIT_LOG" &&
   [[ "$newest_size" == 10240 ]] &&
   ! mdir -i "$SENTRY_LIMIT_TARGET" '::SENTRY/#0000001.MS' >/dev/null 2>&1 &&
   ! grep -Eq 'SENTRY_LIMIT_(LOAD|FIRST_DELETE|SECOND_DELETE)_FAILED|SENTRY_LIMIT_(OLDEST_REMAINS|NEWEST_MISSING)' "$SENTRY_LIMIT_LOG"; then
    ok "Sentry INI filters, archive policy, and percentage limit purge oldest data"
else
    fail "Sentry retention policy"
fi

mcopy -i "$SENTRY_LIMIT_TARGET" ::SENTRY/CONTROL.FIL "$OUT/undelete-sentry-control.fil"
printf '\041\000' | dd of="$OUT/undelete-sentry-control.fil" bs=1 seek=48 conv=notrunc status=none
mcopy -o -i "$SENTRY_LIMIT_TARGET" "$OUT/undelete-sentry-control.fil" ::SENTRY/CONTROL.FIL
{
    printf '@ECHO OFF\r\nCTTY AUX\r\nB:\r\n'
    printf 'A:\\UNDELETE /LOAD\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SENTRY_AGE_LOAD_FAILED\r\n'
    printf 'ECHO NEW RETENTION PAYLOAD>THREE.TXT\r\n'
    printf 'DEL THREE.TXT\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SENTRY_AGE_DELETE_FAILED\r\n'
    printf 'A:\\UNDELETE TWO.DAT /LIST /DS\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO SENTRY_AGE_EXPIRED_REMAINS\r\n'
    printf 'A:\\UNDELETE THREE.TXT /LIST /DS\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SENTRY_AGE_NEWEST_MISSING\r\n'
    printf 'A:\\UNDELETE /UNLOAD\r\n'
    printf 'A:\\QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT
timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$SENTRY_LIMIT_TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$SENTRY_AGE_LOG" 2>&1 || true
if grep -q 'No Delete Sentry files were found' "$SENTRY_AGE_LOG" &&
   grep -q 'THREE.TXT' "$SENTRY_AGE_LOG" &&
   grep -q 'Protected by Delete Sentry' "$SENTRY_AGE_LOG" &&
   ! mdir -i "$SENTRY_LIMIT_TARGET" '::SENTRY/#0000002.MS' >/dev/null 2>&1 &&
   ! grep -Eq 'SENTRY_AGE_(LOAD|DELETE)_FAILED|SENTRY_AGE_(EXPIRED_REMAINS|NEWEST_MISSING)' "$SENTRY_AGE_LOG"; then
    ok "Sentry days policy purges expired protected files before new deletion"
else
    fail "Sentry age retention"
fi

echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
