#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/help-ui.img"
QMP="$OUT/help-ui-qmp.sock"
SERIAL="$OUT/help-ui.log"

[[ -f "$BASE" ]] || { echo "missing $BASE; run make deploy" >&2; exit 1; }
cp "$BASE" "$IMAGE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$OUT/help-ui-qexit.com"
mcopy -o -i "$IMAGE" "$ROOT/src/CMD/HELP/HELP.COM" ::HELP.COM
mcopy -o -i "$IMAGE" "$ROOT/src/CMD/HELP/HELP.HLP" ::HELP.HLP
mcopy -o -i "$IMAGE" "$OUT/help-ui-qexit.com" ::QEXIT.COM
printf '@ECHO OFF\r\nECHO SCREEN_RESTORE_SENTINEL\r\nHELP\r\nPAUSE\r\nCTTY AUX\r\nECHO HELP_UI_RETURNED\r\nQEXIT.COM\r\n' |
    mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT
unlink "$QMP" 2>/dev/null || true
unlink "$SERIAL" 2>/dev/null || true
qemu-system-i386 -display none -monitor none -m 4 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial file:"$SERIAL" \
    -qmp unix:"$QMP",server,nowait \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >/dev/null 2>&1 &
qemu_pid=$!
if ! timeout 45 python3 "$ROOT/tests/help_ui_coordinator.py" "$QMP" "$OUT"; then
    kill "$qemu_pid" 2>/dev/null || true
    wait "$qemu_pid" 2>/dev/null || true
    exit 1
fi
for attempt in {1..100}; do
    [[ -f "$SERIAL" ]] && grep -q HELP_UI_RETURNED "$SERIAL" && break
    sleep 0.05
done
kill "$qemu_pid" 2>/dev/null || true
wait "$qemu_pid" 2>/dev/null || true

grep -q 'MS-DOS 6.22 Help' "$OUT/index.txt"
grep -q 'FORMAT' "$OUT/search.txt"
grep -q 'Syntax: FORMAT drive:' "$OUT/topic.txt"
grep -q 'Syntax: SYS' "$OUT/link.txt"
grep -q SCREEN_RESTORE_SENTINEL "$OUT/restore.txt"
grep -q HELP_UI_RETURNED "$SERIAL"

# Install a deterministic INT 33h test driver. Its delayed left click selects
# the first index row, proving the mouse path opens a topic and returns safely.
MOUSE_IMAGE="$OUT/help-ui-mouse.img"
MOUSE_SERIAL="$OUT/help-ui-mouse.log"
MOUSE_QMP="$OUT/help-ui-mouse-qmp.sock"
nasm -f bin "$ROOT/tests/help_mouse_probe.asm" -o "$OUT/help-mouse-probe.com"
cp "$BASE" "$MOUSE_IMAGE"
mcopy -o -i "$MOUSE_IMAGE" "$ROOT/src/CMD/HELP/HELP.COM" ::HELP.COM
mcopy -o -i "$MOUSE_IMAGE" "$ROOT/src/CMD/HELP/HELP.HLP" ::HELP.HLP
mcopy -o -i "$MOUSE_IMAGE" "$OUT/help-ui-qexit.com" ::QEXIT.COM
mcopy -o -i "$MOUSE_IMAGE" "$OUT/help-mouse-probe.com" ::MOUSETSR.COM
printf '@ECHO OFF\r\nMOUSETSR.COM\r\nECHO SCREEN_RESTORE_SENTINEL\r\nHELP\r\nPAUSE\r\nCTTY AUX\r\nECHO HELP_MOUSE_RETURNED\r\nQEXIT.COM\r\n' |
    mcopy -o -i "$MOUSE_IMAGE" - ::AUTOEXEC.BAT
unlink "$MOUSE_QMP" 2>/dev/null || true
unlink "$MOUSE_SERIAL" 2>/dev/null || true
qemu-system-i386 -display none -monitor none -m 4 \
    -drive if=floppy,index=0,format=raw,file="$MOUSE_IMAGE",cache=writethrough \
    -boot a -serial file:"$MOUSE_SERIAL" \
    -qmp unix:"$MOUSE_QMP",server,nowait \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >/dev/null 2>&1 &
qemu_pid=$!
if ! timeout 45 python3 "$ROOT/tests/help_ui_coordinator.py" "$MOUSE_QMP" "$OUT" mouse; then
    kill "$qemu_pid" 2>/dev/null || true
    wait "$qemu_pid" 2>/dev/null || true
    exit 1
fi
for attempt in {1..100}; do
    [[ -f "$MOUSE_SERIAL" ]] && grep -q HELP_MOUSE_RETURNED "$MOUSE_SERIAL" && break
    sleep 0.05
done
kill "$qemu_pid" 2>/dev/null || true
wait "$qemu_pid" 2>/dev/null || true
grep -q 'Provides ANSI escape-sequence display' "$OUT/mouse.txt"
grep -q SCREEN_RESTORE_SENTINEL "$OUT/mouse-restore.txt"
grep -q HELP_MOUSE_RETURNED "$MOUSE_SERIAL"
echo "HELP full-screen search, links, mouse, and screen-restore contracts passed"
