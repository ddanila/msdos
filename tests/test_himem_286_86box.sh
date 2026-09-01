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

work=$(mktemp -d "${TMPDIR:-/tmp}/msdos-himem-286-86box.XXXXXX")
trap 'rm -rf "$work"' EXIT
baseline_image="$work/int15-87.img"
himem_image="$work/himem-286.img"

"$ROOT/bin/jwasm-bin" -DFORCE_286 -Fo"$work/HIMEM.SYS" \
    "$ROOT/src/DEV/HIMEM/HIMEM.ASM"
nasm -f bin "$ROOT/tests/int15_87_286_probe.asm" -o "$work/INT1587.COM"
nasm -f bin "$ROOT/tests/himem_286_probe.asm" -o "$work/HIM286.COM"

# Prove that the BIOS can perform and return from an 80286 protected-mode
# block move independently of HIMEM's CONFIG.SYS initialization.
make_86box_286_boot_image "$baseline_image" "$ROOT"
mcopy -o -i "$baseline_image" "$work/INT1587.COM" ::INT1587.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'INT1587.COM\r\n'
    printf 'IF ERRORLEVEL 1 GOTO FAIL\r\n'
    printf 'ECHO 86BOX_INT15_RESULT_PASS>RESULT.TXT\r\n'
    printf 'TYPE RESULT.TXT\r\n'
    printf 'GOTO WAIT\r\n'
    printf ':FAIL\r\n'
    printf 'ECHO 86BOX_INT15_RESULT_PRODUCT_FAIL>RESULT.TXT\r\n'
    printf 'TYPE RESULT.TXT\r\n'
    printf ':WAIT\r\n'
    printf 'GOTO WAIT\r\n'
} | mcopy -o -i "$baseline_image" - ::AUTOEXEC.BAT
run_86box_286 "$baseline_image" 86BOX_INT15_RESULT_PASS \
    86BOX_INT15_RESULT_PRODUCT_FAIL "${BOX86_TIMEOUT:-180}" "$ROOT" >/dev/null
echo '  PASS: IBM AT BIOS INT 15h/AH=87h block move on an 8 MHz 80286'

# Use a fresh boot for the product path: CONFIG.SYS loads HIMEM before any
# AUTOEXEC.BAT program can run.
make_86box_286_boot_image "$himem_image" "$ROOT"
mcopy -o -i "$himem_image" "$work/HIMEM.SYS" ::HIMEM.SYS
mcopy -o -i "$himem_image" "$work/HIM286.COM" ::HIM286.COM
printf 'DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF\r\n' | \
    mcopy -o -i "$himem_image" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'ECHO 86BOX_286_TEST_STARTED\r\n'
    printf 'HIM286.COM\r\n'
    printf 'IF ERRORLEVEL 1 GOTO HIMEMFAIL\r\n'
    printf 'ECHO 86BOX_RESULT_PASS>RESULT.TXT\r\n'
    printf 'TYPE RESULT.TXT\r\n'
    printf 'GOTO WAIT\r\n'
    printf ':HIMEMFAIL\r\n'
    printf 'ECHO 86BOX_RESULT_PRODUCT_FAIL_HIMEM>RESULT.TXT\r\n'
    printf 'TYPE RESULT.TXT\r\n'
    printf ':WAIT\r\n'
    printf 'GOTO WAIT\r\n'
} | mcopy -o -i "$himem_image" - ::AUTOEXEC.BAT

run_86box_286 "$himem_image" 86BOX_RESULT_PASS 86BOX_RESULT_PRODUCT_FAIL \
    "${BOX86_TIMEOUT:-180}" "$ROOT" >/dev/null
echo '  PASS: HIMEM XMS lifecycle on an 8 MHz 80286'
