#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
FAULT_OBJ="$OUT/memmaker_fault.obj"
FAULT_EXE="$OUT/memmaker_fault.exe"
QEXIT="$OUT/memmaker-fault-exit.com"
SERIAL_IN="$OUT/memmaker-fault-serial.in"
SERIAL_OUT="$OUT/memmaker-fault-serial.out"

trap 'rm -f "$SERIAL_IN" "$SERIAL_OUT" 2>/dev/null; true' EXIT

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
    printf '@ECHO OFF\r\nCTTY AUX\r\n' | mcopy -o -i "$image" - ::AUTOEXEC.BAT

    rm -f "$SERIAL_IN" "$SERIAL_OUT"
    mkfifo "$SERIAL_IN" "$SERIAL_OUT"
    exec 3<>"$SERIAL_IN"
    timeout 25 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 16 \
        -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
        -boot a -serial pipe:"$OUT/memmaker-fault-serial" -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 2>/dev/null &
    qemu_pid=$!
    python3 "$ROOT/tests/serial_expect.py" "$SERIAL_IN" "$SERIAL_OUT" "$log" \
        'A>' "SET MEMMAKER_FAULT=$point\rMEMMAKER /BATCH /SWAP:A\rIF ERRORLEVEL 1 ECHO MEMMAKER_${point}_ROLLBACK_PASS\rQEXIT.COM\r"
    wait "$qemu_pid" || true
    exec 3>&-

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
