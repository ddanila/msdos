#!/bin/bash
# Boot the minimal WASM-built DOS floppy (IO.SYS + MSDOS.SYS + COMMAND.COM)
# in an interactive QEMU window.
#
# Controls:
#   Ctrl-Alt-F  — toggle fullscreen
#   Ctrl-Alt-G  — release mouse
#   Ctrl-Alt-2  — QEMU monitor (type 'quit' to exit)
#   Ctrl-Alt-1  — back to DOS display

IMG="$(dirname "$0")/out/mini.img"

if [ ! -f "$IMG" ]; then
    echo "ERROR: $IMG not found. Run 'make' first or check the build."
    exit 1
fi

exec qemu-system-i386 \
    -fda "$IMG" \
    -boot a \
    -m 4 \
    -cpu 486 \
    -display sdl \
    "$@"
