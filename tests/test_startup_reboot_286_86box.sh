#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C MTOOLS_SKIP_CHECK=1

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/tests/86box_286_lib.sh"

for tool in nasm mcopy mformat mtype python3; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done
check_86box_286_prerequisites || exit $?

work=$(mktemp -d "${TMPDIR:-/tmp}/msdos-startup-reboot-286.XXXXXX")
trap 'rm -rf "$work"' EXIT
image="$work/startup-reboot-286.img"

nasm -f bin "$ROOT/tests/reboot_286.asm" -o "$work/REBOOT.COM"
make_86box_286_boot_image "$image" "$ROOT"
mcopy -o -i "$image" "$work/REBOOT.COM" ::REBOOT.COM
{
    printf '[MENU]\r\n'
    printf 'MENUITEM=FIRST, IBM AT warm reboot\r\n'
    printf 'MENUDEFAULT=FIRST,1\r\n'
} | mcopy -o -i "$image" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'IF NOT "%%CONFIG%%"=="FIRST" GOTO FAIL\r\n'
    printf 'IF EXIST REBOOT.TAG GOTO SECOND\r\n'
    printf 'ECHO FIRST_BOOT>REBOOT.TAG\r\n'
    printf 'REBOOT.COM\r\n'
    printf 'GOTO FAIL\r\n'
    printf ':SECOND\r\n'
    printf 'ECHO 86BOX_STARTUP_REBOOT_286_PASS>RESULT.TXT\r\n'
    printf 'TYPE RESULT.TXT\r\n'
    printf 'GOTO WAIT\r\n'
    printf ':FAIL\r\n'
    printf 'ECHO 86BOX_STARTUP_REBOOT_286_PRODUCT_FAIL>RESULT.TXT\r\n'
    printf 'TYPE RESULT.TXT\r\n'
    printf ':WAIT\r\n'
    printf 'GOTO WAIT\r\n'
} | mcopy -o -i "$image" - ::AUTOEXEC.BAT

run_86box_286 "$image" 86BOX_STARTUP_REBOOT_286_PASS \
    86BOX_STARTUP_REBOOT_286_PRODUCT_FAIL "${BOX86_TIMEOUT:-240}" "$ROOT" >/dev/null
echo '  PASS: IBM AT startup selection and warm reboot persistence'
