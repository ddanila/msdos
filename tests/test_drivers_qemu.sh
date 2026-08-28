#!/bin/bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"

BOOT_IMG="$OUT/floppy-drivers-qemu.img"
SERIAL_LOG="$OUT/drivers-qemu-serial.log"
PROBE_COM="$OUT/block-driver-request.com"
COUNTRY_PROBE_COM="$OUT/country-config-probe.com"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== Device Driver / CONFIG.SYS E2E tests (QEMU) ==="

echo "Building test image..."
cp "$FLOPPY" "$BOOT_IMG"
nasm -f bin "$REPO_ROOT/tests/block_driver_probe.asm" -o "$PROBE_COM"
nasm -f bin "$REPO_ROOT/tests/country_config_probe.asm" -o "$COUNTRY_PROBE_COM"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

mcopy -o -i "$BOOT_IMG" "$PROBE_COM" ::BLKREQ.COM
mcopy -o -i "$BOOT_IMG" "$COUNTRY_PROBE_COM" ::CNTRYCHK.COM

{
    printf 'COUNTRY=049,,COUNTRY.SYS\r\n'
    printf 'DEVICE=ANSI.SYS\r\n'
    printf 'DEVICE=RAMDRIVE.SYS 64\r\n'
    printf 'DEVICE=VDISK.SYS 64\r\n'
    printf 'DEVICE=DISPLAY.SYS CON=(EGA,,1)\r\n'
    printf 'DEVICE=SMARTDRV.SYS 256\r\n'
    printf 'BUFFERS=20\r\n'
    printf 'FILES=30\r\n'
    printf 'LASTDRIVE=Z\r\n'
    printf 'BREAK=ON\r\n'
    printf 'STACKS=9,256\r\n'
    printf 'FCBS=4\r\n'
    printf 'INSTALL=FASTOPEN.EXE C:=10\r\n'
    printf 'SHELL=COMMAND.COM /P\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'

    printf 'ECHO ---ANSI---\r\n'
    printf 'MEM\r\n'
    printf 'ECHO ANSI_DONE\r\n'

    printf 'ECHO ---RAMDRIVE---\r\n'
    printf 'DIR C:\\\r\n'
    printf 'DIR D:\\\r\n'
    printf 'ECHO RAMDRIVE_DONE\r\n'

    printf 'ECHO ---VDISK---\r\n'
    printf 'DIR D:\\\r\n'
    printf 'VERIFY OFF\r\n'
    printf 'ECHO RAM_WRITE>C:\\RAMW.TXT\r\n'
    printf 'ECHO VDISK_WRITE>D:\\VDSKW.TXT\r\n'
    printf 'VERIFY ON\r\n'
    printf 'ECHO RAM_VERIFY>C:\\RAMV.TXT\r\n'
    printf 'ECHO VDISK_VERIFY>D:\\VDSKV.TXT\r\n'
    printf 'VERIFY OFF\r\n'
    printf 'TYPE C:\\RAMW.TXT\r\n'
    printf 'TYPE C:\\RAMV.TXT\r\n'
    printf 'TYPE D:\\VDSKW.TXT\r\n'
    printf 'TYPE D:\\VDSKV.TXT\r\n'
    printf 'BLKREQ.COM\r\n'
    printf 'ECHO VDISK_DONE\r\n'

    printf 'ECHO ---DISPLAY---\r\n'
    printf 'MODE CON CP /STATUS\r\n'
    printf 'ECHO DISPLAY_DONE\r\n'

    printf 'ECHO ---SMARTDRV---\r\n'
    printf 'MEM\r\n'
    printf 'ECHO SMARTDRV_DONE\r\n'

    printf 'ECHO ---CONFIG---\r\n'
    printf 'CNTRYCHK.COM\r\n'
    printf 'MEM\r\n'
    printf 'ECHO CONFIG_DONE\r\n'

    printf 'ECHO ---CHCP---\r\n'
    printf 'CHCP\r\n'
    printf 'ECHO CHCP_DONE\r\n'

    printf 'ECHO ---CHCP-SET---\r\n'
    printf 'NLSFUNC\r\n'
    printf 'MODE CON CP PREPARE=((850) A:\\EGA.CPI)\r\n'
    printf 'MODE CON CP SELECT=850\r\n'
    printf 'ECHO CHCP_SET_DONE\r\n'

    printf 'ECHO ---CHCP-VERIFY---\r\n'
    printf 'MODE CON CP /STATUS\r\n'
    printf 'CHCP\r\n'
    printf 'ECHO CHCP_VERIFY_DONE\r\n'

    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

echo "Booting QEMU (may take ~90s)..."
rm -f "$SERIAL_LOG"
(while true; do sleep 0.5; printf '\r\n'; done) | \
timeout 120 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial stdio \
    2>/dev/null | tee "$SERIAL_LOG" > /dev/null; true

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi

echo ""
echo "--- ANSI.SYS tests ---"

if grep -q "ANSI_DONE" "$SERIAL_LOG"; then
    ok "ANSI.SYS (boot completed with DEVICE=ANSI.SYS, batch continued)"
else
    fail "ANSI.SYS (batch hung or crashed — driver load may have failed)"
fi

echo ""
echo "--- RAMDRIVE.SYS tests ---"

if grep -q "RAMDRIVE_DONE" "$SERIAL_LOG"; then
    ok "RAMDRIVE.SYS (boot completed with DEVICE=RAMDRIVE.SYS 64, batch continued)"
else
    fail "RAMDRIVE.SYS (batch hung or crashed — driver load may have failed)"
fi

if grep -qi "Directory of C:\|Volume in drive C" "$SERIAL_LOG" || \
   grep -qi "Directory of D:\|Volume in drive D" "$SERIAL_LOG"; then
    ok "RAMDRIVE.SYS (RAM disk drive accessible via DIR)"
else
    fail "RAMDRIVE.SYS (no RAM disk drive found on C: or D:)"
fi

echo ""
echo "--- VDISK.SYS tests ---"

if grep -q "VDISK_DONE" "$SERIAL_LOG"; then
    ok "VDISK.SYS (boot completed with DEVICE=VDISK.SYS 64, batch continued)"
else
    fail "VDISK.SYS (batch hung or crashed — driver load may have failed)"
fi

if grep -qi "Directory of D:\|Volume in drive D" "$SERIAL_LOG" || \
   grep -qi "Directory of E:\|Volume in drive E" "$SERIAL_LOG"; then
    ok "VDISK.SYS (virtual disk drive accessible via DIR)"
else
    fail "VDISK.SYS (no virtual disk drive found on D: or E:)"
fi

for marker in RAM_WRITE RAM_VERIFY VDISK_WRITE VDISK_VERIFY; do
    if grep -qx "$marker"$'\r' "$SERIAL_LOG"; then
        ok "Block driver returned the exact $marker payload through DOS I/O"
    else
        fail "Block driver did not persist $marker"
    fi
done

if grep -q 'BLOCK_DRIVER_REQUEST_PASS' "$SERIAL_LOG"; then
    ok "RAMDRIVE.SYS and VDISK.SYS expose exact geometry and isolated raw I/O"
else
    fail "Block-driver removable-media requests did not pass"
fi

echo ""
echo "--- DISPLAY.SYS tests ---"

if grep -q "DISPLAY_DONE" "$SERIAL_LOG"; then
    ok "DISPLAY.SYS (boot completed with DEVICE=DISPLAY.SYS CON=(EGA,,1), batch continued)"
else
    fail "DISPLAY.SYS (batch hung or crashed — driver load may have failed)"
fi

echo ""
echo "--- SMARTDRV.SYS tests ---"

if grep -q "SMARTDRV_DONE" "$SERIAL_LOG"; then
    ok "SMARTDRV.SYS (boot completed with DEVICE=SMARTDRV.SYS 256, batch continued)"
else
    fail "SMARTDRV.SYS (batch hung or crashed — driver load may have failed)"
fi

echo ""
echo "--- CONFIG.SYS directive tests ---"

if grep -q "CONFIG_DONE" "$SERIAL_LOG"; then
    ok "CONFIG.SYS directives (BUFFERS FILES LASTDRIVE BREAK STACKS FCBS INSTALL SHELL COUNTRY — boot completed)"
else
    fail "CONFIG.SYS directives (batch did not reach CONFIG_DONE marker)"
fi

if grep -qi "bytes total memory" "$SERIAL_LOG"; then
    ok "CONFIG.SYS + MEM (memory report confirms DOS loaded with custom config)"
else
    fail "CONFIG.SYS + MEM (expected 'bytes total memory' in MEM output)"
fi

if grep -q "COUNTRY_CONFIG_PASS" "$SERIAL_LOG"; then
    ok "COUNTRY=049 loaded exact German conventions from COUNTRY.SYS"
else
    fail "COUNTRY=049 did not expose the expected live country information"
fi

echo ""
echo "--- CHCP tests ---"

if grep -q "CHCP_DONE" "$SERIAL_LOG"; then
    ok "CHCP (show current code page, batch continued)"
else
    fail "CHCP (batch hung or crashed)"
fi

if grep -qi "Active code page.*437" "$SERIAL_LOG"; then
    ok "CHCP (default code page is 437)"
else
    fail "CHCP (expected 'Active code page: 437')"
fi

if grep -q "CHCP_SET_DONE" "$SERIAL_LOG"; then
    ok "Code page set (batch continued — didn't hang)"
else
    fail "Code page set (batch hung or crashed)"
fi

if sed -n '/---CHCP-SET---/,/CHCP_SET_DONE/p' "$SERIAL_LOG" | grep -qi "prepare.*completed\|prepared"; then
    ok "MODE CON CP PREPARE=((850) EGA.CPI) succeeded"
else
    fail "MODE CON CP PREPARE (expected 'prepared' or 'completed')"
fi

if sed -n '/---CHCP-SET---/,/CHCP_SET_DONE/p' "$SERIAL_LOG" | grep -qi "select.*completed\|selected"; then
    ok "MODE CON CP SELECT=850 succeeded"
else
    fail "MODE CON CP SELECT=850 (expected 'selected' or 'completed')"
fi

if grep -q "CHCP_VERIFY_DONE" "$SERIAL_LOG"; then
    ok "CHCP verify (batch continued)"
else
    fail "CHCP verify (batch hung or crashed)"
fi

if sed -n '/---CHCP-VERIFY---/,/CHCP_VERIFY_DONE/p' "$SERIAL_LOG" | grep -qi "Active code page.*850"; then
    ok "CHCP 850 (active code page is 850 after switch)"
else
    fail "CHCP 850 (expected 'Active code page: 850' after switch)"
fi

echo ""
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
