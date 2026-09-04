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

work=$(mktemp -d "${TMPDIR:-/tmp}/msdos-platform-286.XXXXXX")
trap 'rm -rf "$work"' EXIT
image="$work/platform-286.img"

nasm -f bin "$ROOT/tests/platform_286_probe.asm" -o "$work/PLAT286.COM"
sysbuf_hex=$(awk '$2 == "SYSBUF" { split($1, address, ":"); print address[2]; exit }' \
    "$ROOT/src/DOS/MSDOS.MAP")
[[ "$sysbuf_hex" =~ ^[0-9A-Fa-f]{4}$ ]] || {
    echo 'ERROR: could not read SYSBUF from MSDOS.MAP' >&2
    exit 1
}
hma_tail=$((16#$sysbuf_hex + 15 * (512 + 20) + 8))
catalog_start_hex=$(awk 'toupper($2) == "RESIDENT_CATALOG_START" { split($1, address, ":"); print address[2]; exit }' \
    "$ROOT/src/CMD/COMMAND/COMMAND.MAP")
dataresend_hex=$(awk 'toupper($2) == "DATARESEND" { split($1, address, ":"); print address[2]; exit }' \
    "$ROOT/src/CMD/COMMAND/COMMAND.MAP")
class_ptrs_hex=$(awk 'toupper($2) == "RESIDENT_CLASS_PTRS" { split($1, address, ":"); print address[2]; exit }' \
    "$ROOT/src/CMD/COMMAND/COMMAND.MAP")
[[ "$catalog_start_hex" =~ ^[0-9A-Fa-f]{4}$ && "$dataresend_hex" =~ ^[0-9A-Fa-f]{4}$ && "$class_ptrs_hex" =~ ^[0-9A-Fa-f]{4}$ ]] || {
    echo 'ERROR: could not read COMMAND resident-catalog range' >&2
    exit 1
}
command_hma_bytes=$((16#$dataresend_hex - 16#$catalog_start_hex))
hma_tail_after_command=$((hma_tail + command_hma_bytes))
nasm -DEXPECTED_CLASS_PTRS="0x$class_ptrs_hex" \
    -DEXPECTED_CATALOG_BASE="$hma_tail" -DEXPECTED_CATALOG_END="$hma_tail_after_command" \
    -DEXPECTED_HMA_CLASSES=2 \
    -f bin "$ROOT/tests/command_critical_hma_probe.asm" -o "$work/CMDCAT.COM"
nasm -DEXPECTED_TAIL="$hma_tail_after_command" -f bin "$ROOT/tests/hma_tail_probe.asm" \
    -o "$work/HMATAIL.COM"
make_86box_286_boot_image "$image" "$ROOT"
mcopy -o -i "$image" "$ROOT/src/DEV/HIMEM/HIMEM.SYS" ::HIMEM.SYS
mcopy -o -i "$image" "$work/PLAT286.COM" ::PLAT286.COM
mcopy -o -i "$image" "$work/HMATAIL.COM" ::HMATAIL.COM
mcopy -o -i "$image" "$work/CMDCAT.COM" ::CMDCAT.COM
{
    printf '[MENU]\r\n'
    printf 'MENUITEM=AT286, IBM AT 286 acceptance\r\n'
    printf 'MENUDEFAULT=AT286,1\r\n'
    printf '[COMMON]\r\n'
    printf 'DEVICE=A:\\HIMEM.SYS /MACHINE:AT /TESTMEM:ON\r\n'
    printf 'DOS=HIGH\r\n'
} | mcopy -o -i "$image" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'IF "%%CONFIG%%"=="AT286" GOTO SELECTED\r\n'
    printf 'GOTO FAIL\r\n'
    printf ':SELECTED\r\n'
    printf 'PLAT286.COM\r\n'
    printf 'IF ERRORLEVEL 1 GOTO FAIL\r\n'
    printf 'HMATAIL.COM\r\n'
    printf 'IF ERRORLEVEL 1 GOTO FAIL\r\n'
    printf 'CMDCAT.COM\r\n'
    printf 'IF ERRORLEVEL 1 GOTO FAIL\r\n'
    printf 'ECHO 86BOX_PLATFORM_286_PASS>RESULT.TXT\r\n'
    printf 'TYPE RESULT.TXT\r\n'
    printf 'GOTO WAIT\r\n'
    printf ':FAIL\r\n'
    printf 'ECHO 86BOX_PLATFORM_286_PRODUCT_FAIL>RESULT.TXT\r\n'
    printf 'TYPE RESULT.TXT\r\n'
    printf ':WAIT\r\n'
    printf 'GOTO WAIT\r\n'
} | mcopy -o -i "$image" - ::AUTOEXEC.BAT

run_86box_286 "$image" 86BOX_PLATFORM_286_PASS \
    86BOX_PLATFORM_286_PRODUCT_FAIL "${BOX86_TIMEOUT:-180}" "$ROOT" >/dev/null
echo '  PASS: 286 CPU, A20/HMA/XMS, TESTMEM, menu, keyboard, and disk geometry'
