#!/bin/bash

set -uo pipefail
export LC_ALL=C MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="$OUT/floppy.img"
EXIT_COM="$OUT/sys-hdd-qexit.com"
MBR_IMAGE="$ROOT/src/CMD/FDISK/FDBOOT.BIN"
PART_OFFSET=32256

for tool in dd mattrib mcopy mformat mtype nasm python3 qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null || { echo "ERROR: missing $tool"; exit 1; }
done
[[ -f "$BASE" ]] || { echo "ERROR: run make deploy first"; exit 1; }
[[ -f "$MBR_IMAGE" ]] || { echo "ERROR: missing $MBR_IMAGE"; exit 1; }

nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"

PASS=0
FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

make_disk() {
    local disk="$1" cylinders="$2" sectors="$3" clustersize="$4" upgrade="$5"
    dd if=/dev/zero of="$disk" bs=512 count="$sectors" status=none
    python3 - "$MBR_IMAGE" "$disk" "$cylinders" "$sectors" <<'PY'
import struct, sys

mbr_source, image, cylinders, sectors = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
heads, spt, start = 16, 63, 63
size = sectors - start

def chs(lba):
    cylinder, remainder = divmod(lba, heads * spt)
    head, sector0 = divmod(remainder, spt)
    cylinder = min(cylinder, 1023)
    return bytes((head, (sector0 + 1) | ((cylinder >> 2) & 0xc0), cylinder & 0xff))

with open(mbr_source, 'rb') as f:
    f.seek(0x600)
    boot_code = f.read(446)
if len(boot_code) != 446:
    raise SystemExit('FDISK MBR template is incomplete')

mbr = bytearray(512)
mbr[:446] = boot_code
ptype = 0x04 if size <= 65535 else 0x06
mbr[446:462] = bytes((0x80,)) + chs(start) + bytes((ptype,)) + chs(start + size - 1) + struct.pack('<II', start, size)
mbr[510:512] = b'\x55\xaa'
with open(image, 'r+b') as f:
    f.write(mbr)
PY
    mformat -i "$disk@@$PART_OFFSET" -t "$cylinders" -h 16 -n 63 -H 63 -c "$clustersize" ::
    printf 'preserve-user-data\r\n' | mcopy -i "$disk@@$PART_OFFSET" - ::KEEP.TXT
    printf 'FILES=17\r\n' | mcopy -i "$disk@@$PART_OFFSET" - ::CONFIG.SYS
    if [[ "$upgrade" == yes ]]; then
        printf 'old-io-system-file\r\n' | mcopy -i "$disk@@$PART_OFFSET" - ::IO.SYS
        printf 'old-dos-system-file\r\n' | mcopy -i "$disk@@$PART_OFFSET" - ::MSDOS.SYS
        mattrib -i "$disk@@$PART_OFFSET" +h +s +r ::IO.SYS
        mattrib -i "$disk@@$PART_OFFSET" +h +s +r ::MSDOS.SYS
    fi
}

run_case() {
    local name="$1" cylinders="$2" sectors="$3" clustersize="$4" upgrade="$5"
    local boot="$OUT/sys-hdd-$name-boot.img"
    local disk="$OUT/sys-hdd-$name.img"
    local install_log="$OUT/sys-hdd-$name-install.log"
    local boot_log="$OUT/sys-hdd-$name-boot.log"

    cp "$BASE" "$boot"
    make_disk "$disk" "$cylinders" "$sectors" "$clustersize" "$upgrade"
    mcopy -o -i "$boot" "$EXIT_COM" ::QEXIT.COM
    {
        printf '@ECHO OFF\r\n'
        printf 'CTTY AUX\r\n'
        printf 'SYS C:\r\n'
        printf 'IF ERRORLEVEL 1 ECHO SYS_HDD_%s_ERROR\r\n' "$name"
        printf 'ECHO SYS_HDD_%s_DONE\r\n' "$name"
        printf 'QEXIT.COM\r\n'
    } | mcopy -o -i "$boot" - ::AUTOEXEC.BAT

    timeout 35 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 4 \
        -drive if=floppy,index=0,format=raw,file="$boot",cache=writethrough \
        -drive if=ide,index=0,format=raw,file="$disk",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$install_log" 2>&1 || true

    if grep -q "SYS_HDD_${name}_DONE" "$install_log" \
        && ! grep -q "SYS_HDD_${name}_ERROR" "$install_log" \
        && grep -q 'System transferred' "$install_log"; then
        ok "SYS transfers to the $name FAT16 fixed disk"
    else
        fail "SYS transfer to the $name FAT16 fixed disk"
        sed -n '1,120p' "$install_log"
        return
    fi

    local keep config
    keep="$(mtype -i "$disk@@$PART_OFFSET" ::KEEP.TXT 2>/dev/null | tr -d '\r\n')"
    config="$(mtype -i "$disk@@$PART_OFFSET" ::CONFIG.SYS 2>/dev/null | tr -d '\r\n')"
    if [[ "$keep" == preserve-user-data && "$config" == FILES=17 ]]; then
        ok "SYS $name transfer preserves user files and configuration"
    else
        fail "SYS $name transfer damaged existing files"
    fi

    if cmp -s "$ROOT/src/BIOS/IO.SYS" <(mtype -i "$disk@@$PART_OFFSET" ::IO.SYS 2>/dev/null) \
        && cmp -s "$ROOT/src/DOS/MSDOS.SYS" <(mtype -i "$disk@@$PART_OFFSET" ::MSDOS.SYS 2>/dev/null); then
        ok "SYS $name installs exact current IO.SYS and MSDOS.SYS images"
    else
        fail "SYS $name did not replace the system files exactly"
    fi

    mcopy -o -i "$disk@@$PART_OFFSET" "$ROOT/src/CMD/COMMAND/COMMAND.COM" ::COMMAND.COM
    mcopy -o -i "$disk@@$PART_OFFSET" "$EXIT_COM" ::QEXIT.COM
    {
        printf '@ECHO OFF\r\n'
        printf 'CTTY AUX\r\n'
        printf 'VER\r\n'
        printf 'ECHO SYS_HDD_%s_BOOTED\r\n' "$name"
        printf 'QEXIT.COM\r\n'
    } | mcopy -o -i "$disk@@$PART_OFFSET" - ::AUTOEXEC.BAT

    timeout 20 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 4 \
        -drive if=ide,index=0,format=raw,file="$disk",cache=writethrough \
        -boot c -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$boot_log" 2>&1 || true

    if grep -q "SYS_HDD_${name}_BOOTED" "$boot_log" \
        && grep -Eq 'MS-DOS Version 6\.22' "$boot_log"; then
        ok "SYS-created $name fixed disk boots DOS 6.22"
    else
        fail "SYS-created $name fixed disk did not boot"
        sed -n '1,120p' "$boot_log"
    fi

    if python3 - "$disk" "$sectors" <<'PY'
import struct, sys
with open(sys.argv[1], 'rb') as f:
    f.seek(63 * 512)
    b = f.read(512)
expected = int(sys.argv[2]) - 63
small = struct.unpack_from('<H', b, 19)[0]
large = struct.unpack_from('<I', b, 32)[0]
assert struct.unpack_from('<I', b, 28)[0] == 63
assert (small == expected and large == 0) or (small == 0 and large == expected)
assert b[3:11] == b'MSDOS5.0'
assert b[36] == 0x80
assert b[510:512] == b'\x55\xaa'
PY
    then
        ok "SYS $name preserves hidden-sector and total-sector BPB geometry"
    else
        fail "SYS $name corrupted fixed-disk BPB geometry"
    fi
}

echo "=== SYS fixed-disk tests ==="
run_case SMALL 64 64512 4 no
run_case LARGE_UPGRADE 255 257040 4 yes

echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
