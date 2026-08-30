#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
FAULT_OBJ="$OUT/memmaker_fault.obj"
FAULT_EXE="$OUT/memmaker_fault.exe"
QEXIT="$OUT/memmaker-fault-exit.com"

for tool in mcopy mdir nasm qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done
[[ -f "$BASE" ]] || { echo "ERROR: run make deploy first" >&2; exit 1; }

(
    cd "$OUT"
    ../bin/wcc '-AS -Os -Zp -DMEMMAKER_TEST_FAULTS -c -Fomemmaker_fault.obj ../src/CMD/MEMMAKER/MEMMAKER.C'
    ../bin/wlink 'memmaker_fault.obj,memmaker_fault.exe,,;'
)
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"

for point in CONFIG AUTOEXEC STATUS; do
    image="$OUT/memmaker-fault-${point}.img"
    log="$OUT/memmaker-fault-${point}.log"
    cp "$BASE" "$image"
    mcopy -o -i "$image" "$FAULT_EXE" ::MEMMAKER.EXE
    mcopy -o -i "$image" "$QEXIT" ::QEXIT.COM
    printf 'FILES=20\r\n' | mcopy -o -i "$image" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\nCTTY AUX\r\n'
        printf 'SET MEMMAKER_FAULT=%s\r\n' "$point"
        printf 'MEMMAKER /BATCH /SWAP:A\r\n'
        printf 'IF ERRORLEVEL 1 ECHO MEMMAKER_%s_ROLLBACK_PASS\r\n' "$point"
        printf 'QEXIT.COM\r\n'
    } | mcopy -o -i "$image" - ::AUTOEXEC.BAT

    timeout 25 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 16 \
        -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$log" 2>&1 || true

    grep -Fq "MEMMAKER_${point}_ROLLBACK_PASS" "$log"
    grep -Fq 'MemMaker rolled back an incomplete startup-file update.' "$log"
    current_config=$(mcopy -i "$image" ::CONFIG.SYS - 2>/dev/null | tr -d '\r')
    current_autoexec=$(mcopy -i "$image" ::AUTOEXEC.BAT - 2>/dev/null | tr -d '\r')
    backup_config=$(mcopy -i "$image" ::CONFIG.MM - 2>/dev/null | tr -d '\r')
    backup_autoexec=$(mcopy -i "$image" ::AUTOEXEC.MM - 2>/dev/null | tr -d '\r')
    [[ "$current_config" == "$backup_config" ]]
    [[ "$current_autoexec" == "$backup_autoexec" ]]
    ! mdir -b -i "$image" :: 2>/dev/null | grep -Eq 'MEMMAKER\.STS|CONFIG\.MMT|AUTOEXEC\.MMT'
done

echo '  PASS: MemMaker rolls both startup files back at every commit boundary'
