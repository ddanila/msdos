#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
QEXIT="$OUT/memmaker-windows-qexit.com"

for tool in mcopy mdir nasm qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: missing $tool" >&2; exit 1; }
done
[[ -f "$BASE" ]] || { echo "ERROR: run make deploy first" >&2; exit 1; }
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"

for version in 31 unknown options; do
    image="$OUT/memmaker-windows-${version}.img"
    log="$OUT/memmaker-windows-${version}.log"
    serial_in="$OUT/memmaker-windows-${version}-serial.in"
    serial_out="$OUT/memmaker-windows-${version}-serial.out"
    original="$OUT/memmaker-windows-${version}.ini"
    cp "$BASE" "$image"
    mcopy -o -i "$image" "$ROOT/src/CMD/MEMMAKER/MEMMAKER.EXE" ::MEMMAKER.EXE
    mcopy -o -i "$image" "$ROOT/src/DEV/HIMEM/HIMEM.SYS" ::HIMEM.SYS
    mcopy -o -i "$image" "$ROOT/src/MEMM/MEMM/EMM386.EXE" ::EMM386.EXE
    mcopy -o -i "$image" "$QEXIT" ::QEXIT.COM
    mmd -i "$image" ::WINDOWS
    if [[ "$version" == options ]]; then
        printf 'DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF\r\nDEVICE=A:\\EMM386.EXE RAM X=C800-CFFF\r\nFILES=20\r\n' \
            | mcopy -o -i "$image" - ::CONFIG.SYS
    else
        printf 'FILES=20\r\n' | mcopy -o -i "$image" - ::CONFIG.SYS
    fi
    {
        printf '@ECHO OFF\r\nCTTY AUX\r\nSET WINDIR=A:\\WINDOWS\r\n'
        printf 'IF EXIST A:\\MEMMAKER.STS QEXIT.COM\r\n'
    } | mcopy -o -i "$image" - ::AUTOEXEC.BAT
    printf '[386Enh]\r\nMinTimeSlice=20\r\n' >"$original"
    mcopy -o -i "$image" "$original" ::WINDOWS/SYSTEM.INI
    if [[ "$version" == 31 ]]; then
        printf 'Microsoft Windows Version 3.10\r\n' | mcopy -o -i "$image" - ::WINDOWS/WIN.COM
    elif [[ "$version" == options ]]; then
        printf 'Microsoft Windows Version 3.00\r\n' | mcopy -o -i "$image" - ::WINDOWS/WIN.COM
    else
        printf 'unversioned Windows launcher\r\n' | mcopy -o -i "$image" - ::WINDOWS/WIN.COM
    fi

    rm -f "$serial_in" "$serial_out"
    mkfifo "$serial_in" "$serial_out"
    exec 3<>"$serial_in"
    timeout 35 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 16 \
        -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
        -boot a -serial pipe:"$OUT/memmaker-windows-${version}-serial" -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 2>/dev/null &
    qemu_pid=$!
    if [[ "$version" == options ]]; then
        python3 "$ROOT/tests/serial_expect.py" "$serial_in" "$serial_out" "$log" \
            'A>' 'MEMMAKER /CUSTOM /SWAP:A\r' \
            'Do programs require expanded memory (Y/N)?' 'N\r' \
            'Use monochrome region B000-B7FF for programs (Y/N)?' 'Y\r'
    else
        python3 "$ROOT/tests/serial_expect.py" "$serial_in" "$serial_out" "$log" \
            'A>' 'MEMMAKER /BATCH /SWAP:A\r'
    fi
    wait "$qemu_pid" || true
    exec 3>&-
    rm -f "$serial_in" "$serial_out"

    current_hash=$(mcopy -i "$image" ::WINDOWS/SYSTEM.INI - 2>/dev/null | sha256sum | awk '{print $1}')
    original_hash=$(sha256sum "$original" | awk '{print $1}')
    if [[ "$version" == options ]]; then
        system_ini=$(mcopy -i "$image" ::WINDOWS/SYSTEM.INI - 2>/dev/null | tr -d '\r')
        config=$(mcopy -i "$image" ::CONFIG.SYS - 2>/dev/null | tr -d '\r')
        grep -qi '^DUALDISPLAY=TRUE$' <<<"$system_ini"
        grep -qi '^NOEMMDRIVER=TRUE$' <<<"$system_ini"
        grep -qi '^DEVICE=A:\\EMM386.EXE X=C800-CFFF NOEMS I=B000-B7FF$' <<<"$config"
        mdir -b -i "$image" ::WINDOWS 2>/dev/null | grep -q 'SYSTEM.UMB'
    else
        [[ "$current_hash" == "$original_hash" ]]
        ! mdir -b -i "$image" ::WINDOWS 2>/dev/null | grep -q 'SYSTEM.UMB'
    fi
done

echo '  PASS: MemMaker applies Windows 3.0 options and leaves 3.1/unknown unchanged'
