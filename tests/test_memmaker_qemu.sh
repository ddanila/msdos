#!/bin/bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/memmaker.img"
LOG="$OUT/memmaker.log"
UNDO_LOG="$OUT/memmaker-undo.log"
SESSION_LOG="$OUT/memmaker-session.log"
QEXIT="$OUT/memmaker-qexit.com"
SERIAL_IN="$OUT/memmaker-serial.in"
SERIAL_OUT="$OUT/memmaker-serial.out"
ORIGINAL_CONFIG="$OUT/memmaker-config.original"
ORIGINAL_AUTOEXEC="$OUT/memmaker-autoexec.original"
ORIGINAL_SYSTEM="$OUT/memmaker-system.original"
PASS=0
FAIL=0

ok() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

[[ -f "$BASE" ]] || { echo "missing $BASE; run make deploy" >&2; exit 1; }
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
trap 'rm -f "$SERIAL_IN" "$SERIAL_OUT" 2>/dev/null; true' EXIT
cp "$BASE" "$IMAGE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
mcopy -o -i "$IMAGE" "$ROOT/src/CMD/MEMMAKER/MEMMAKER.EXE" ::MEMMAKER.EXE
mcopy -o -i "$IMAGE" "$ROOT/src/DEV/HIMEM/HIMEM.SYS" ::HIMEM.SYS
mcopy -o -i "$IMAGE" "$ROOT/src/MEMM/MEMM/EMM386.EXE" ::EMM386.EXE
mcopy -o -i "$IMAGE" "$QEXIT" ::QEXIT.COM
mmd -i "$IMAGE" ::WINDOWS
printf 'FCBS=4,0\r\nDEVICE=A:\\DRIVER.SYS\r\nLASTDRIVE=Z\r\nFILES=20\r\nBUFFERS=15\r\n' >"$ORIGINAL_CONFIG"
{
    printf '@ECHO OFF\r\nCTTY AUX\r\nSET WINDIR=A:\\WINDOWS\r\nNLSFUNC A:\\COUNTRY.SYS\r\n'
    printf 'IF EXIST A:\\MEMMAKER.STS ECHO MEMMAKER_SESSION_DONE\r\n'
    printf 'IF EXIST A:\\MEMMAKER.STS QEXIT.COM\r\n'
} >"$ORIGINAL_AUTOEXEC"
printf '[boot]\r\nshell=progman.exe\r\n[386Enh]\r\nMinTimeSlice=20\r\n' >"$ORIGINAL_SYSTEM"
printf 'Microsoft Windows Version 3.00\r\n' | mcopy -o -i "$IMAGE" - ::WINDOWS/WIN.COM
mcopy -o -i "$IMAGE" "$ORIGINAL_CONFIG" ::CONFIG.SYS
mcopy -o -i "$IMAGE" "$ORIGINAL_AUTOEXEC" ::AUTOEXEC.BAT
mcopy -o -i "$IMAGE" "$ORIGINAL_SYSTEM" ::WINDOWS/SYSTEM.INI

rm -f "$SERIAL_IN" "$SERIAL_OUT"
mkfifo "$SERIAL_IN" "$SERIAL_OUT"
exec 3<>"$SERIAL_IN"
timeout 15 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial pipe:"$OUT/memmaker-serial" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null &
QEMU_PID=$!
python3 "$ROOT/tests/serial_expect.py" "$SERIAL_IN" "$SERIAL_OUT" "$LOG" \
    'A>' 'MEMMAKER /CUSTOM /SWAP:A /W:4,8\r' \
    'Do programs require expanded memory (Y/N)?' 'Y\r' \
    'Use monochrome region B000-B7FF for programs (Y/N)?' 'N\r' \
    'Load this driver into upper memory (Y/N)?' 'N\r' \
    'Load this TSR into upper memory (Y/N)?' 'Y\r'
wait "$QEMU_PID" || true
exec 3>&-

rm -f "$SERIAL_IN" "$SERIAL_OUT"
mkfifo "$SERIAL_IN" "$SERIAL_OUT"
exec 3<>"$SERIAL_IN"
timeout 40 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial pipe:"$OUT/memmaker-serial" -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null &
QEMU_PID=$!
python3 "$ROOT/tests/serial_expect.py" "$SERIAL_IN" "$SERIAL_OUT" "$SESSION_LOG" \
    'A>' 'QEXIT.COM\r'
wait "$QEMU_PID" || true
exec 3>&-
cat "$SESSION_LOG" >>"$LOG"

if grep -q 'MEMMAKER_SESSION_DONE' "$LOG"; then
    ok "Custom optimization schedules and completes its own /SESSION pass"
else
    fail "MemMaker reboot/session workflow"
    tail -80 "$LOG"
fi

config="$(mcopy -i "$IMAGE" ::CONFIG.SYS - 2>/dev/null | tr -d '\r')"
autoexec="$(mcopy -i "$IMAGE" ::AUTOEXEC.BAT - 2>/dev/null | tr -d '\r')"
status="$(mcopy -i "$IMAGE" ::MEMMAKER.STS - 2>/dev/null | tr -d '\r')"
if grep -qi '^DEVICE=A:\\HIMEM.SYS /TESTMEM:ON' <<<"$config" &&
   grep -qi '^DEVICE=A:\\EMM386.EXE RAM M5' <<<"$config" &&
   grep -qi '^DOS=HIGH,UMB' <<<"$config" &&
   grep -qi '^DEVICE=A:\\DRIVER.SYS' <<<"$config" &&
   ! grep -qi '^DEVICEHIGH=A:\\DRIVER.SYS' <<<"$config"; then
    ok "CONFIG.SYS honors the Custom driver-high choice"
else
    fail "optimized CONFIG.SYS contents"
fi
config_order="$(grep -Ein '^(DEVICE=.*HIMEM|DEVICE=.*EMM386|BUFFERS=|FILES=|DOS=|LASTDRIVE=|FCBS=)' <<<"$config" | cut -d: -f2-)"
expected_order=$'DEVICE=A:\\HIMEM.SYS /TESTMEM:ON\nDEVICE=A:\\EMM386.EXE RAM M5\nBUFFERS=15\nFILES=20\nDOS=HIGH,UMB\nLASTDRIVE=Z\nFCBS=4,0'
config_order_upper="$(tr '[:lower:]' '[:upper:]' <<<"$config_order")"
expected_order_upper="$(tr '[:lower:]' '[:upper:]' <<<"$expected_order")"
if [[ "$config_order_upper" == "$expected_order_upper" ]]; then
    ok "CONFIG.SYS uses the retail MemMaker leading-entry order"
else
    fail "MemMaker CONFIG.SYS leading-entry order"
fi
if grep -qi '^LH NLSFUNC A:\\COUNTRY.SYS' <<<"$autoexec" &&
   ! grep -qi '^@MEMMAKER /SESSION' <<<"$autoexec"; then
    ok "AUTOEXEC.BAT loads the eligible TSR high and removes session plumbing"
else
    fail "optimized AUTOEXEC.BAT contents"
fi
if grep -q 'optimization completed after measured reboot passes' <<<"$status" &&
   grep -q 'Windows UMB reserve: 4,8' <<<"$status" &&
   grep -Eq 'Measured largest UMB: [1-9][0-9]*K' <<<"$status" &&
   grep -Eq 'Measured largest conventional block: [1-9][0-9]*K' <<<"$status" &&
   grep -Eq 'Post-CONFIG largest UMB: [1-9][0-9]*K' <<<"$status" &&
   grep -Eq 'Post-CONFIG largest conventional block: [1-9][0-9]*K' <<<"$status" &&
   grep -Eq 'Baseline largest conventional block: [1-9][0-9]*K' <<<"$status" &&
   grep -Eq 'Measured UMB after /W reserve: [0-9]+K' <<<"$status" &&
   grep -q 'Windows SYSTEM.INI: Windows 3.0 settings applied and backed up' <<<"$status" &&
   grep -q 'Drivers selected for upper memory: 0 of 1' <<<"$status" &&
   grep -q 'TSRs selected for upper memory: 1 of 1' <<<"$status"; then
    ok "MEMMAKER.STS records measurements, /W policy, and Custom choices"
else
    fail "MemMaker status report"
fi
if ! mdir -b -i "$IMAGE" :: 2>/dev/null | grep -q 'MEMMAKER.MEM'; then
    ok "measurement handoff is removed after the final pass"
else
    fail "stale MemMaker measurement handoff"
fi
system_backup_hash="$(mcopy -i "$IMAGE" ::WINDOWS/SYSTEM.UMB - 2>/dev/null | sha256sum | awk '{print $1}')"
[[ "$system_backup_hash" == "$(sha256sum "$ORIGINAL_SYSTEM" | awk '{print $1}')" ]] &&
    ok "Windows SYSTEM.INI backup is byte-exact" || fail "Windows SYSTEM.INI backup"
system_ini="$(mcopy -i "$IMAGE" ::WINDOWS/SYSTEM.INI - 2>/dev/null | tr -d '\r')"
if grep -qi '^SYSTEMROMBREAKPOINT=FALSE$' <<<"$system_ini" &&
   grep -qi '^EMMEXCLUDE=A000-FFFF$' <<<"$system_ini" &&
   ! grep -qi '^DUALDISPLAY=' <<<"$system_ini" &&
   ! grep -qi '^NOEMMDRIVER=' <<<"$system_ini"; then
    ok "Windows 3.0 base compatibility settings are written"
else
    fail "Windows 3.0 SYSTEM.INI compatibility settings"
fi
config_backup_hash="$(mcopy -i "$IMAGE" ::CONFIG.MM - 2>/dev/null | sha256sum | awk '{print $1}')"
auto_backup_hash="$(mcopy -i "$IMAGE" ::AUTOEXEC.MM - 2>/dev/null | sha256sum | awk '{print $1}')"
[[ "$config_backup_hash" == "$(sha256sum "$ORIGINAL_CONFIG" | awk '{print $1}')" &&
   "$auto_backup_hash" == "$(sha256sum "$ORIGINAL_AUTOEXEC" | awk '{print $1}')" ]] &&
    ok "startup-file backups are byte-exact" || fail "startup-file backup mismatch"

{
    printf '@ECHO OFF\r\nCTTY AUX\r\nSET WINDIR=A:\\WINDOWS\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT
printf '[damaged]\r\n' | mcopy -o -i "$IMAGE" - ::WINDOWS/SYSTEM.INI
rm -f "$SERIAL_IN" "$SERIAL_OUT"
mkfifo "$SERIAL_IN" "$SERIAL_OUT"
exec 3<>"$SERIAL_IN"
timeout 40 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial pipe:"$OUT/memmaker-serial" -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null &
QEMU_PID=$!
python3 "$ROOT/tests/serial_expect.py" "$SERIAL_IN" "$SERIAL_OUT" "$UNDO_LOG" \
    'A>' 'MEMMAKER /UNDO /SWAP:A\rIF ERRORLEVEL 1 ECHO MEMMAKER_UNDO_FAILED\rECHO MEMMAKER_UNDO_DONE\rQEXIT.COM\r'
wait "$QEMU_PID" || true
exec 3>&-

restored_config="$(mcopy -i "$IMAGE" ::CONFIG.SYS - 2>/dev/null | sha256sum | awk '{print $1}')"
restored_auto="$(mcopy -i "$IMAGE" ::AUTOEXEC.BAT - 2>/dev/null | sha256sum | awk '{print $1}')"
restored_system="$(mcopy -i "$IMAGE" ::WINDOWS/SYSTEM.INI - 2>/dev/null | sha256sum | awk '{print $1}')"
if grep -q 'MEMMAKER_UNDO_DONE' "$UNDO_LOG" &&
   ! grep -q '^MEMMAKER_UNDO_FAILED' "$UNDO_LOG" &&
   [[ "$restored_config" == "$(sha256sum "$ORIGINAL_CONFIG" | awk '{print $1}')" ]] &&
   [[ "$restored_auto" == "$(sha256sum "$ORIGINAL_AUTOEXEC" | awk '{print $1}')" ]] &&
   [[ "$restored_system" == "$(sha256sum "$ORIGINAL_SYSTEM" | awk '{print $1}')" ]]; then
    ok "/UNDO restores all startup files byte-for-byte"
else
    fail "MemMaker /UNDO"
    tail -60 "$UNDO_LOG"
fi

echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
