#!/bin/bash
# Drive delayed serial input to prove DOS's Ctrl-Break and idle callbacks.

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"
BOOT_IMG="$OUT/floppy-dos-async-interrupt.img"
PROBE_COM="$OUT/dosasync.com"
SERIAL_SOCKET="$OUT/dos-async-interrupt.sock"
SERIAL_LOG="$OUT/dos-async-interrupt.log"
QEMU_LOG="$OUT/dos-async-interrupt-qemu.log"

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

for tool in nasm mcopy python3 qemu-system-i386 timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found: $tool"
        exit 1
    fi
done

cp "$FLOPPY" "$BOOT_IMG"
nasm -f bin "$REPO_ROOT/tests/dos_async_interrupt_probe.asm" -o "$PROBE_COM"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$BOOT_IMG" "$PROBE_COM" ::DOSASYNC.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'DOSASYNC.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

rm -f "$SERIAL_SOCKET" "$SERIAL_LOG" "$QEMU_LOG"
timeout 35 qemu-system-i386 \
    -display none \
    -monitor none \
    -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -serial "unix:$SERIAL_SOCKET,server=on,wait=off" -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$QEMU_LOG" 2>&1 &
qemu_pid=$!
trap 'kill "$qemu_pid" 2>/dev/null || true; rm -f "$SERIAL_SOCKET"' EXIT

python3 - "$SERIAL_SOCKET" "$SERIAL_LOG" <<'PY'
import socket
import sys
import time

socket_path, log_path = sys.argv[1:]
deadline = time.monotonic() + 30
client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
while True:
    try:
        client.connect(socket_path)
        break
    except (FileNotFoundError, ConnectionRefusedError):
        if time.monotonic() >= deadline:
            raise SystemExit("serial socket did not become ready")
        time.sleep(0.05)

client.settimeout(0.2)
output = bytearray()
sent = False
while time.monotonic() < deadline:
    try:
        chunk = client.recv(4096)
        if not chunk:
            break
        output.extend(chunk)
    except socket.timeout:
        pass
    if not sent and b"DOS_ASYNC_READY" in output:
        time.sleep(0.5)
        client.sendall(b"\x03X")
        sent = True
    if b"DOS_ASYNC_INTERRUPT_PASS" in output:
        break

with open(log_path, "wb") as stream:
    stream.write(output)
PY

wait "$qemu_pid" 2>/dev/null || true
trap - EXIT
rm -f "$SERIAL_SOCKET"

if grep -q 'DOS_ASYNC_INTERRUPT_PASS' "$SERIAL_LOG"; then
    echo "  PASS: DOS INT 23h Ctrl-Break and INT 28h idle callbacks"
    exit 0
fi

echo "  FAIL: DOS asynchronous interrupt probe did not complete"
sed -n '1,180p' "$SERIAL_LOG"
sed -n '1,80p' "$QEMU_LOG"
exit 1
