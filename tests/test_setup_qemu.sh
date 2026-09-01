#!/bin/bash

set -uo pipefail
export LC_ALL=C MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
DISK1="$OUT/distribution/disk1.img"
DISK2="$OUT/distribution/disk2.img"
FLOPPY_IMAGE="$OUT/setup-boot.img"
HDD="$OUT/setup-hdd.img"
LOG="$OUT/setup.log"
SERIAL_IN="$OUT/setup-serial.in"
SERIAL_OUT="$OUT/setup-serial.out"
QMP="$OUT/setup-qmp.sock"
PART_OFFSET=32256

for tool in mcopy mformat mtype python3 qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null || { echo "ERROR: missing $tool"; exit 1; }
done
[[ -f "$DISK1" && -f "$DISK2" ]] || { echo "ERROR: run make distribution"; exit 1; }

cp "$DISK1" "$FLOPPY_IMAGE"
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'SETUP C:\\DOS /Y\r\n'
} | mcopy -o -i "$FLOPPY_IMAGE" - ::AUTOEXEC.BAT

dd if=/dev/zero of="$HDD" bs=512 count=64512 status=none
python3 - "$ROOT/src/CMD/FDISK/FDBOOT.BIN" "$HDD" <<'PY'
import struct, sys
with open(sys.argv[1], 'rb') as f:
    f.seek(0x600)
    code = f.read(446)
mbr = bytearray(512)
mbr[:446] = code
mbr[446:462] = bytes((0x80, 1, 1, 0, 4, 15, 63, 63)) + struct.pack('<II', 63, 64449)
mbr[510:512] = b'\x55\xaa'
with open(sys.argv[2], 'r+b') as f:
    f.write(mbr)
PY
mformat -i "$HDD@@$PART_OFFSET" -t 64 -h 16 -n 63 -H 63 -c 4 ::
printf 'preserve-during-setup\r\n' | mcopy -i "$HDD@@$PART_OFFSET" - ::KEEP.TXT

unlink "$SERIAL_IN" 2>/dev/null || true
unlink "$SERIAL_OUT" 2>/dev/null || true
unlink "$QMP" 2>/dev/null || true
mkfifo "$SERIAL_IN" "$SERIAL_OUT"
exec 3<>"$SERIAL_IN"
qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=floppy,index=0,format=raw,file="$FLOPPY_IMAGE",cache=writethrough \
    -drive if=ide,index=0,format=raw,file="$HDD",cache=writethrough \
    -qmp unix:"$QMP",server,nowait -boot a -serial pipe:"$OUT/setup-serial" \
    -no-reboot >/dev/null 2>&1 &
QEMU_PID=$!
python3 "$ROOT/tests/setup_coordinator.py" \
    "$SERIAL_IN" "$SERIAL_OUT" "$LOG" "$QMP" "$DISK2" || true
kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
exec 3>&-

PASS=0
FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== SETUP guided installation tests ==="
if grep -Fq 'Fresh installation to C:\DOS' "$LOG" \
    && grep -Fq 'Setup completed successfully' "$LOG" \
    && ! grep -Fq 'Setup could not complete' "$LOG"; then
    ok "SETUP completes its guided fresh-install and Disk 2 workflow"
else
    fail "SETUP runtime"
    sed -n '1,180p' "$LOG"
fi

missing=0
while read -r destination; do
    case "$destination" in
        IO.SYS|MSDOS.SYS|SYSMENU.OVL)
            mdir -a -i "$HDD@@$PART_OFFSET" "::$destination" >/dev/null 2>&1 || missing=$((missing+1))
            ;;
        *)
            mdir -i "$HDD@@$PART_OFFSET" "::DOS/$destination" >/dev/null 2>&1 || missing=$((missing+1))
            ;;
    esac
done < <(python3 - "$ROOT/distribution/files.json" <<'PY'
import json,sys
m=json.load(open(sys.argv[1]))
for _, name in m['boot'] + m['compressed']:
    print(name)
PY
)
if [[ $missing -eq 0 ]]; then
    ok "SETUP installs every manifest file in the root or DOS directory"
else
    fail "SETUP omitted $missing manifest files"
fi

keep="$(mtype -i "$HDD@@$PART_OFFSET" ::KEEP.TXT 2>/dev/null | tr -d '\r\n')"
config="$(mtype -i "$HDD@@$PART_OFFSET" ::CONFIG.SYS 2>/dev/null | tr -d '\r')"
autoexec="$(mtype -i "$HDD@@$PART_OFFSET" ::AUTOEXEC.BAT 2>/dev/null | tr -d '\r')"
if [[ "$keep" == preserve-during-setup ]]; then
    ok "fresh SETUP preserves unrelated target files"
else
    fail "fresh SETUP damaged an unrelated target file"
fi
if grep -Fq 'DEVICE=C:\DOS\HIMEM.SYS' <<<"$config" \
    && grep -Fq 'DEVICE=C:\DOS\EMM386.EXE NOEMS' <<<"$config" \
    && grep -Fq 'DOS=HIGH,UMB' <<<"$config" \
    && grep -Fq 'PATH C:\DOS' <<<"$autoexec" \
    && grep -Fq 'C:\DOS\SMARTDRV.EXE' <<<"$autoexec"; then
    ok "fresh SETUP creates DOS 6.22 memory and cache startup defaults"
else
    fail "fresh SETUP configuration defaults"
fi

if cmp -s "$ROOT/src/CMD/SORT/SORT.EXE" <(mtype -i "$HDD@@$PART_OFFSET" ::DOS/SORT.EXE 2>/dev/null) \
    && cmp -s "$ROOT/src/MEMM/MEMM/EMM386.EXE" <(mtype -i "$HDD@@$PART_OFFSET" ::DOS/EMM386.EXE 2>/dev/null); then
    ok "SETUP expands representative command and driver payloads byte-exactly"
else
    fail "SETUP expanded payload mismatch"
fi

# Run Setup again against the installed tree and require byte-for-byte
# preservation of user-owned startup files.
printf 'REM user config\r\nFILES=17\r\n' | mcopy -o -i "$HDD@@$PART_OFFSET" - ::CONFIG.SYS
printf '@ECHO OFF\r\nREM user autoexec\r\n' | mcopy -o -i "$HDD@@$PART_OFFSET" - ::AUTOEXEC.BAT
UPGRADE_CONFIG="$OUT/setup-upgrade-config.txt"
UPGRADE_AUTOEXEC="$OUT/setup-upgrade-autoexec.txt"
mcopy -i "$HDD@@$PART_OFFSET" ::CONFIG.SYS "$UPGRADE_CONFIG"
mcopy -i "$HDD@@$PART_OFFSET" ::AUTOEXEC.BAT "$UPGRADE_AUTOEXEC"
unlink "$SERIAL_IN" 2>/dev/null || true
unlink "$SERIAL_OUT" 2>/dev/null || true
unlink "$QMP" 2>/dev/null || true
mkfifo "$SERIAL_IN" "$SERIAL_OUT"
exec 3<>"$SERIAL_IN"
qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=floppy,index=0,format=raw,file="$FLOPPY_IMAGE",cache=writethrough \
    -drive if=ide,index=0,format=raw,file="$HDD",cache=writethrough \
    -qmp unix:"$QMP",server,nowait -boot a -serial pipe:"$OUT/setup-serial" \
    -no-reboot >/dev/null 2>&1 &
QEMU_PID=$!
python3 "$ROOT/tests/setup_coordinator.py" \
    "$SERIAL_IN" "$SERIAL_OUT" "$LOG.upgrade" "$QMP" "$DISK2" || true
kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
exec 3>&-

if grep -Fq 'Upgrade installation in C:\DOS' "$LOG.upgrade" \
    && grep -Fq 'Setup completed successfully' "$LOG.upgrade" \
    && cmp -s "$UPGRADE_CONFIG" <(mtype -i "$HDD@@$PART_OFFSET" ::CONFIG.SYS 2>/dev/null) \
    && cmp -s "$UPGRADE_AUTOEXEC" <(mtype -i "$HDD@@$PART_OFFSET" ::AUTOEXEC.BAT 2>/dev/null); then
    ok "upgrade SETUP detects the installed tree and preserves startup files byte-exactly"
else
    fail "upgrade SETUP behavior"
fi

# Replace AUTOEXEC only for the boot assertion; the preservation check above
# has already compared the original bytes.
printf '@ECHO OFF\r\nCTTY AUX\r\nECHO SETUP_HDD_BOOTED\r\n' \
    | mcopy -o -i "$HDD@@$PART_OFFSET" - ::AUTOEXEC.BAT
BOOT_LOG="$OUT/setup-hdd-boot.log"
timeout 20 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=ide,index=0,format=raw,file="$HDD",cache=writethrough \
    -boot c -serial stdio -no-reboot >"$BOOT_LOG" 2>&1 || true
if grep -Fq 'SETUP_HDD_BOOTED' "$BOOT_LOG"; then
    ok "SETUP produces a bootable fixed disk with a working command interpreter"
else
    fail "SETUP fixed-disk boot"
fi

echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
