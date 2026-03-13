#!/bin/bash
# run-qemu.sh — Launch MS-DOS 4.0 floppy image in QEMU with a graphical display.
# Usage: ./run-qemu.sh [path/to/floppy.img]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLOPPY="${1:-$SCRIPT_DIR/out/floppy.img}"

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: floppy image not found: $FLOPPY"
    echo "Run 'make deploy' first to build it."
    exit 1
fi

echo "Booting: $FLOPPY"
exec qemu-system-i386 \
    -drive if=floppy,format=raw,file="$FLOPPY" \
    -boot a \
    -m 4 \
    -display sdl \
    -name "MS-DOS 4.0"
