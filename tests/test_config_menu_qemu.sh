#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/config-menu.img"
LOG="$OUT/config-menu.log"
EXIT_COM="$OUT/config-menu-exit.com"
INSTALL_COM="$OUT/config-menu-install.com"

cp "$BASE" "$IMAGE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
nasm -f bin "$ROOT/tests/installhigh_test_tsr.asm" -o "$INSTALL_COM"
mcopy -o -i "$IMAGE" "$ROOT/src/BIOS/SYSMENU.OVL" ::SYSMENU.OVL
mcopy -o -i "$IMAGE" "$EXIT_COM" ::QEXIT.COM
mcopy -o -i "$IMAGE" "$INSTALL_COM" ::IHREF.COM
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
    printf 'device=HIMEM.SYS\r\n'
    printf 'dos=umb\r\n'
    printf '[one]\r\n'
    printf 'set selected=ONE\r\n'
    printf 'device=NOONE.SYS\r\n'
    printf 'install=NOONE.COM\r\n'
    printf 'shell=NOONE.COM /P\r\n'
    printf '[two]\r\n'
    printf 'set order=SELECTED\r\n'
    printf 'include=extras\r\n'
    printf 'set order=AFTER\r\n'
    printf 'set selected=TWO\r\n'
    printf 'devicehigh=ANSI.SYS\r\n'
    printf 'install=IHREF.COM SELECTED\r\n'
    printf 'shell=COMMAND.COM /P /E:512\r\n'
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
    printf 'MEM /M:ANSI\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

rm -f "$LOG"
timeout 35 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -boot a -m 16 \
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
    'CONFIG_MENU_ORDER=AFTER' \
    'TAIL= SELECTED' \
    'ANSI'; do
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

echo '  PASS: CONFIG menus, ordered INCLUDE, environment, and multipass directives'
