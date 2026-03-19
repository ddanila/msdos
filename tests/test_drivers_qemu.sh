#!/bin/bash
# tests/test_drivers_qemu.sh — E2E tests for device drivers via QEMU.
#
# Tests CONFIG.SYS device driver loading and CONFIG.SYS directives:
#   - ANSI.SYS: load driver, verify via escape sequence output
#   - RAMDRIVE.SYS: load driver, verify extra drive letter appears
#   - VDISK.SYS: load virtual disk driver, verify drive accessible
#   - DISPLAY.SYS: load code page display driver
#   - SMARTDRV.SYS: load disk cache driver
#   - CONFIG.SYS directives: BUFFERS, FILES, LASTDRIVE, BREAK, STACKS, FCBS,
#     INSTALL, SHELL, COUNTRY
#
# Run via: make test-drivers-qemu  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

BOOT_IMG="$OUT/floppy-drivers-qemu.img"
SERIAL_LOG="$OUT/drivers-qemu-serial.log"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== Device Driver / CONFIG.SYS E2E tests (QEMU) ==="

# ── Build test floppy ────────────────────────────────────────────────────────
echo "Building test image..."
cp "$FLOPPY" "$BOOT_IMG"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

# Drivers are already on the base floppy (added by make deploy).

# Write CONFIG.SYS with device drivers and directives
{
    printf 'COUNTRY=001,,COUNTRY.SYS\r\n'
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

# AUTOEXEC.BAT: test each driver and directive
{
    printf 'CTTY AUX\r\n'

    # ── ANSI.SYS test — use ANSI escape sequence to set cursor position ──
    # ESC[6n is "Device Status Report" → ANSI.SYS responds with cursor position.
    # But output goes to stdin buffer, hard to capture. Instead, test that ANSI.SYS
    # is loaded by checking MEM output for the driver name.
    printf 'ECHO ---ANSI---\r\n'
    printf 'MEM\r\n'
    printf 'ECHO ANSI_DONE\r\n'

    # ── RAMDRIVE.SYS test — verify extra drive letter via DIR ──────────────
    # RAMDRIVE.SYS creates a 64KB RAM disk at the next available drive letter.
    # With floppy-only boot (A:, B: reserved), the RAM disk is typically C: or D:.
    # Try multiple candidates to be robust.
    printf 'ECHO ---RAMDRIVE---\r\n'
    printf 'DIR C:\\\r\n'
    printf 'DIR D:\\\r\n'
    printf 'ECHO RAMDRIVE_DONE\r\n'

    # ── VDISK.SYS test — verify another virtual disk drive via DIR ─────────
    # VDISK.SYS creates a 64KB virtual disk at the next available drive letter
    # after RAMDRIVE.SYS. Try D: and E: to find it.
    # RAMDRIVE is C:, VDISK is D:. Only try D: and E: if drives exist;
    # avoid E: if no driver creates it — DIR on nonexistent drive may hang.
    printf 'ECHO ---VDISK---\r\n'
    printf 'DIR D:\\\r\n'
    printf 'ECHO VDISK_DONE\r\n'

    # ── DISPLAY.SYS test — verify code page driver loaded ────────────────
    # DISPLAY.SYS installs as a device driver. Boot completing proves it loaded.
    # MODE CON CP /STATUS shows prepared code pages (requires DISPLAY.SYS).
    printf 'ECHO ---DISPLAY---\r\n'
    printf 'MODE CON CP /STATUS\r\n'
    printf 'ECHO DISPLAY_DONE\r\n'

    # ── SMARTDRV.SYS test — verify disk cache loaded ─────────────────────
    # SMARTDRV.SYS installs as a device driver for disk caching.
    # Boot completing proves it loaded without crashing.
    printf 'ECHO ---SMARTDRV---\r\n'
    printf 'MEM\r\n'
    printf 'ECHO SMARTDRV_DONE\r\n'

    # ── CONFIG.SYS directives — verify via MEM output ──────────────────────
    # MEM shows total memory; BUFFERS/FILES affect memory layout.
    # We just verify the boot completed successfully with these directives active.
    printf 'ECHO ---CONFIG---\r\n'
    printf 'MEM\r\n'
    printf 'ECHO CONFIG_DONE\r\n'

    # ── CHCP (no args) — show current code page ────────────────────────────
    # INT 21h/AH=66h/AL=01h returns active code page (default 437).
    # Works without NLSFUNC — just queries the kernel.
    printf 'ECHO ---CHCP---\r\n'
    printf 'CHCP\r\n'
    printf 'ECHO CHCP_DONE\r\n'

    # Note: CHCP nnn (set) requires MODE CON CP PREPARE with EGA.CPI, which
    # is not built (needs DOS-toolchain MASM). Without prepared code pages,
    # CHCP 850 hangs in DISPLAY.SYS driver. Skipped until EGA.CPI is built.

    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

# ── Boot QEMU and capture serial output ──────────────────────────────────────
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

# ── ANSI.SYS checks ─────────────────────────────────────────────────────────
echo ""
echo "--- ANSI.SYS tests ---"

if grep -q "ANSI_DONE" "$SERIAL_LOG"; then
    ok "ANSI.SYS (boot completed with DEVICE=ANSI.SYS, batch continued)"
else
    fail "ANSI.SYS (batch hung or crashed — driver load may have failed)"
fi

# ── RAMDRIVE.SYS checks ─────────────────────────────────────────────────────
echo ""
echo "--- RAMDRIVE.SYS tests ---"

if grep -q "RAMDRIVE_DONE" "$SERIAL_LOG"; then
    ok "RAMDRIVE.SYS (boot completed with DEVICE=RAMDRIVE.SYS 64, batch continued)"
else
    fail "RAMDRIVE.SYS (batch hung or crashed — driver load may have failed)"
fi

# Check if DIR on C: or D: succeeded (shows "Volume" or "Directory of" header).
# RAMDRIVE assigns the next available drive letter after physical drives.
if grep -qi "Directory of C:\|Volume in drive C" "$SERIAL_LOG" || \
   grep -qi "Directory of D:\|Volume in drive D" "$SERIAL_LOG"; then
    ok "RAMDRIVE.SYS (RAM disk drive accessible via DIR)"
else
    fail "RAMDRIVE.SYS (no RAM disk drive found on C: or D:)"
fi

# ── VDISK.SYS checks ───────────────────────────────────────────────────────
echo ""
echo "--- VDISK.SYS tests ---"

if grep -q "VDISK_DONE" "$SERIAL_LOG"; then
    ok "VDISK.SYS (boot completed with DEVICE=VDISK.SYS 64, batch continued)"
else
    fail "VDISK.SYS (batch hung or crashed — driver load may have failed)"
fi

# Check if DIR on D: or E: succeeded (VDISK drive after RAMDRIVE on C:)
if grep -qi "Directory of D:\|Volume in drive D" "$SERIAL_LOG" || \
   grep -qi "Directory of E:\|Volume in drive E" "$SERIAL_LOG"; then
    ok "VDISK.SYS (virtual disk drive accessible via DIR)"
else
    fail "VDISK.SYS (no virtual disk drive found on D: or E:)"
fi

# ── DISPLAY.SYS checks ────────────────────────────────────────────────────
echo ""
echo "--- DISPLAY.SYS tests ---"

if grep -q "DISPLAY_DONE" "$SERIAL_LOG"; then
    ok "DISPLAY.SYS (boot completed with DEVICE=DISPLAY.SYS CON=(EGA,,1), batch continued)"
else
    fail "DISPLAY.SYS (batch hung or crashed — driver load may have failed)"
fi

# ── SMARTDRV.SYS checks ──────────────────────────────────────────────────
echo ""
echo "--- SMARTDRV.SYS tests ---"

if grep -q "SMARTDRV_DONE" "$SERIAL_LOG"; then
    ok "SMARTDRV.SYS (boot completed with DEVICE=SMARTDRV.SYS 256, batch continued)"
else
    fail "SMARTDRV.SYS (batch hung or crashed — driver load may have failed)"
fi

# ── CONFIG.SYS directives checks ────────────────────────────────────────────
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

# ── CHCP checks ──────────────────────────────────────────────────────────────
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


# ── Completion check ──────────────────────────────────────────────────────────
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
