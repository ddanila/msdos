#!/bin/bash
# tests/test_label.sh — E2E test for interactive LABEL.COM label removal via QEMU.
#
# Interactive test pattern (template for all interactive tools):
#   - QEMU -serial pipe:<prefix>  separates serial input (.in) and output (.out)
#   - tests/serial_expect.py acts as an expect-like coordinator:
#       reads .out (QEMU→host), logs it, detects prompt patterns, writes .in (host→QEMU)
#   - With CTTY AUX, DOS stdin/stdout use COM1 → serial pipe
#
# LABEL remove prompt sequence (LABL.SKL verified):
#   COMMON35: "Volume label (11 characters, ENTER for none)? "  — no trailing \n
#   msg 9:    CR,LF,"Delete current volume label (Y/N)? "       — no trailing \n
# Responses:
#   → \r\n  (empty label — triggers delete prompt)
#   → Y\r\n (confirm deletion)
# Y/N input is read via SYSDISPMSG through DOS handle 0 (= COM1 with CTTY AUX).
# Y = proceed to delete, N = set NO_DELETE flag (skip deletion).
#
# FIFO ordering trick (see serial_expect.py header):
#   exec 3<>"$SERIAL_IN"  opens .in with O_RDWR → QEMU's O_RDONLY open doesn't block.
#   Python opens .in for O_WRONLY (non-blocking, write-end already present).
#   Python opens .out for O_RDONLY (blocks until QEMU opens for O_WRONLY) — they
#   unblock each other since QEMU is already running in background at that point.
#
# Run via: make test-label  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

BOOT_IMG="$OUT/label-boot.img"
TARGET_IMG="$OUT/label-target.img"
SERIAL_LOG="$OUT/label-serial.log"
SERIAL_IN="$OUT/label-serial.in"
SERIAL_OUT="$OUT/label-serial.out"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

trap 'rm -f "$SERIAL_IN" "$SERIAL_OUT" 2>/dev/null; true' EXIT

echo "=== LABEL E2E tests (QEMU, interactive serial expect) ==="

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

# ── Step 1: build images ──────────────────────────────────────────────────────
echo "Building test images..."
cp "$FLOPPY" "$BOOT_IMG"

# Build target floppy with label "TESTLABEL" — this is what LABEL will remove
dd if=/dev/zero bs=512 count=2880 of="$TARGET_IMG" status=none
mformat -i "$TARGET_IMG" -f 1440 ::
mlabel  -i "$TARGET_IMG" ::TESTLABEL

# Verify label was written before the test
prelabel=$(mlabel -i "$TARGET_IMG" -s :: 2>/dev/null || echo "")
if ! echo "$prelabel" | grep -qi "TESTLABEL"; then
    echo "ERROR: failed to pre-write label 'TESTLABEL' to target — got: '$prelabel'"
    exit 1
fi
echo "  Pre-test label on B: '$prelabel'"

# AUTOEXEC.BAT: run LABEL B: interactively (no label on command line → interactive mode)
{
    printf 'CTTY AUX\r\n'
    printf 'ECHO ---LABEL-REMOVE---\r\n'
    printf 'LABEL B:\r\n'
    printf 'ECHO LABEL_DONE\r\n'
    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

# ── Step 2: set up serial FIFOs ───────────────────────────────────────────────
# See serial_expect.py header for the O_RDWR trick that prevents FIFO open deadlocks.
mkfifo "$SERIAL_IN" "$SERIAL_OUT"
exec 3<>"$SERIAL_IN"    # O_RDWR: keeps read-end alive so QEMU/Python O_WRONLY won't block

# ── Step 3: boot QEMU ─────────────────────────────────────────────────────────
echo "Booting QEMU with interactive LABEL test..."
rm -f "$SERIAL_LOG"
timeout 120 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial pipe:"$OUT/label-serial" \
    2>/dev/null &
QEMU_PID=$!

# ── Step 4: run serial expect coordinator ─────────────────────────────────────
# Python opens $SERIAL_IN (O_WRONLY, non-blocking) then $SERIAL_OUT (O_RDONLY,
# blocks until QEMU opens it).  Coordinator exits on EOF (QEMU exits).
#
# Interactions in order:
#   1. "ENTER for none"              → \r\n  (submit empty label → triggers delete prompt)
#   2. "Delete current volume label" → Y\r\n (confirm deletion)
python3 "$REPO_ROOT/tests/serial_expect.py" \
    "$SERIAL_IN" "$SERIAL_OUT" "$SERIAL_LOG" \
    "ENTER for none"              $'\\r\\n' \
    "Delete current volume label" $'Y\\r\\n'

wait $QEMU_PID || true
exec 3>&-    # close our O_RDWR fd on SERIAL_IN

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi

# ── Step 5: checks ────────────────────────────────────────────────────────────
echo ""
echo "--- LABEL serial log checks ---"

if grep -q "LABEL_DONE" "$SERIAL_LOG"; then
    ok "LABEL B: (batch continued after LABEL)"
else
    fail "LABEL B: (batch hung or crashed after LABEL)"
fi

if grep -qi "ENTER for none" "$SERIAL_LOG"; then
    ok "LABEL B: (label prompt appeared in serial log)"
else
    fail "LABEL B: (label prompt not seen — CTTY AUX routing issue?)"
fi

if grep -qi "Delete current volume label" "$SERIAL_LOG"; then
    ok "LABEL B: (delete confirmation prompt appeared)"
else
    fail "LABEL B: (delete prompt not seen — empty label may not have triggered it)"
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
echo "--- LABEL post-QEMU image check ---"

postlabel=$(mlabel -i "$TARGET_IMG" -s :: 2>/dev/null || echo "")
# After successful removal, mlabel should print "has no label" or show empty/no label name.
# We check that "TESTLABEL" is gone from the label output.
if echo "$postlabel" | grep -qi "TESTLABEL"; then
    fail "LABEL remove (label 'TESTLABEL' still present: '$postlabel')"
else
    ok "LABEL remove (label cleared — mlabel output: '$postlabel')"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
