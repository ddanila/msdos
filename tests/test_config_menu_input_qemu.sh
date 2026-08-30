#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
IMAGE="$OUT/config-menu-input.img"
LOG="$OUT/config-menu-input.log"
MONITOR="$OUT/config-menu-input.monitor"
SCREEN="$OUT/config-menu-input.ppm"
EXIT_COM="$OUT/config-menu-input-exit.com"
QEMU_PID=''

cleanup() {
    if [[ -n "$QEMU_PID" ]] && kill -0 "$QEMU_PID" 2>/dev/null; then
        kill "$QEMU_PID" 2>/dev/null || true
        wait "$QEMU_PID" 2>/dev/null || true
    fi
    rm -f "$MONITOR"
}
trap cleanup EXIT

cp "$OUT/floppy.img" "$IMAGE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
mcopy -o -i "$IMAGE" "$ROOT/src/BIOS/SYSMENU.OVL" ::SYSMENU.OVL
mcopy -o -i "$IMAGE" "$EXIT_COM" ::QEXIT.COM
{
    printf '[menu]\r\n'
    printf 'submenu=missing,This missing submenu must be hidden\r\n'
    printf 'menuitem=one,Keyboard-selected configuration\r\n'
    printf 'menuitem=two,Timeout configuration\r\n'
    printf 'menudefault=two,10\r\n'
    # MENUCOLOR is intentionally after the items: it applies to the whole menu.
    printf 'menucolor=15,1\r\n'
    printf '[one]\r\n'
    printf 'set selected=ONE\r\n'
    printf '[two]\r\n'
    printf 'set selected=TWO\r\n'
} | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'ECHO CONFIG_MENU_INPUT=%%CONFIG%%/%%SELECTED%%\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

rm -f "$LOG" "$MONITOR" "$SCREEN"
qemu-system-i386 \
    -display none -monitor "unix:$MONITOR,server=on,wait=off" -boot a -m 4 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -serial "file:$LOG" -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >/dev/null 2>&1 &
QEMU_PID=$!

for _ in $(seq 1 50); do
    [[ -S "$MONITOR" ]] && break
    sleep 0.1
done
[[ -S "$MONITOR" ]] || {
    echo 'FAIL: QEMU monitor did not become ready' >&2
    exit 1
}

# Let SYSINIT reach the menu, exercise invalid-key recovery, then choose item 1.
sleep 1
printf 'screendump %s\nsendkey x\nsendkey 1\n' "$SCREEN" |
    nc -w 1 -U "$MONITOR" >/dev/null

for _ in $(seq 1 20); do
    [[ -s "$SCREEN" ]] && break
    sleep 0.1
done
[[ -s "$SCREEN" ]] || {
    echo 'FAIL: CONFIG menu screen capture was not created' >&2
    exit 1
}
HEADER_BYTES=$(head -n 3 "$SCREEN" | wc -c | tr -d ' ')
PIXEL_OFFSET=$((HEADER_BYTES + (390 * 720 + 700) * 3))
read -r RED GREEN BLUE < <(
    dd if="$SCREEN" bs=1 skip="$PIXEL_OFFSET" count=3 2>/dev/null |
        od -An -tu1
)
case "$RED $GREEN $BLUE" in
    '0 0 168'|'0 0 170') ;;
    *)
        echo 'FAIL: MENUCOLOR did not produce a blue screen background' >&2
        exit 1
        ;;
esac

for _ in $(seq 1 100); do
    if grep -Fq 'CONFIG_MENU_INPUT=one/ONE' "$LOG" 2>/dev/null; then
        wait "$QEMU_PID" 2>/dev/null || true
        QEMU_PID=''
        echo '  PASS: CONFIG menu keyboard selection and invalid-key recovery'
        exit 0
    fi
    kill -0 "$QEMU_PID" 2>/dev/null || break
    sleep 0.1
done

echo 'FAIL: CONFIG menu did not honor explicit keyboard selection' >&2
sed -n '1,120p' "$LOG" >&2 || true
exit 1
