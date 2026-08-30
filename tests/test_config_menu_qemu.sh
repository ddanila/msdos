#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
IMAGE="$OUT/config-menu.img"
LOG="$OUT/config-menu.log"
EXIT_COM="$OUT/config-menu-exit.com"

cp "$OUT/floppy.img" "$IMAGE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
mcopy -o -i "$IMAGE" "$ROOT/src/BIOS/SYSMENU.OVL" ::SYSMENU.OVL
mcopy -o -i "$IMAGE" "$EXIT_COM" ::QEXIT.COM
{
    printf '[menu]\r\n'
    printf 'menuitem=one,First configuration\r\n'
    printf 'submenu=advanced,Advanced configurations\r\n'
    printf 'menudefault=advanced,1\r\n'
    printf '[advanced]\r\n'
    printf 'menuitem=two,Second configuration\r\n'
    printf 'menuitem=three,Third configuration\r\n'
    printf 'menudefault=two,0\r\n'
    printf '[common]\r\n'
    printf 'set common=YES\r\n'
    printf '[one]\r\n'
    printf 'set selected=ONE\r\n'
    printf '[two]\r\n'
    printf 'set order=SELECTED\r\n'
    printf 'include=extras\r\n'
    printf 'set order=AFTER\r\n'
    printf 'set selected=TWO\r\n'
    printf '[three]\r\n'
    printf 'set selected=THREE\r\n'
    printf '[extras]\r\n'
    printf 'set included=YES\r\n'
    printf 'set order=INCLUDED\r\n'
    printf 'include=deep\r\n'
    printf '[deep]\r\n'
    printf 'set deep=YES\r\n'
} | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'ECHO CONFIG_MENU_CONFIG=%%CONFIG%%\r\n'
    printf 'ECHO CONFIG_MENU_COMMON=%%COMMON%%\r\n'
    printf 'ECHO CONFIG_MENU_SELECTED=%%SELECTED%%\r\n'
    printf 'ECHO CONFIG_MENU_INCLUDED=%%INCLUDED%%\r\n'
    printf 'ECHO CONFIG_MENU_DEEP=%%DEEP%%\r\n'
    printf 'ECHO CONFIG_MENU_ORDER=%%ORDER%%\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

rm -f "$LOG"
timeout 20 qemu-system-i386 \
    -display none -monitor none -boot a -m 4 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$LOG" 2>&1 || true

for marker in \
    'CONFIG_MENU_CONFIG=two' \
    'CONFIG_MENU_COMMON=YES' \
    'CONFIG_MENU_SELECTED=TWO' \
    'CONFIG_MENU_INCLUDED=YES' \
    'CONFIG_MENU_DEEP=YES' \
    'CONFIG_MENU_ORDER=AFTER'; do
    grep -Fq "$marker" "$LOG" || {
        echo "FAIL: missing CONFIG menu evidence: $marker" >&2
        sed -n '1,120p' "$LOG" >&2
        exit 1
    }
done

if grep -Eq 'CONFIG_MENU_SELECTED=(ONE|THREE)' "$LOG"; then
    echo 'FAIL: unselected CONFIG.SYS section executed' >&2
    exit 1
fi

echo '  PASS: CONFIG menu nesting, defaults, ordered INCLUDE, and environment'
