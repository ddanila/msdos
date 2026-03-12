#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KVIKDOS="$SCRIPT_DIR/kvikdos/kvikdos"
SRC="$SCRIPT_DIR/MS-DOS/v4.0/src"
OZZIE="$SCRIPT_DIR/MS-DOS/v4.0-ozzie/bin/DISK1"
OUT="$SCRIPT_DIR/out"

mkdir -p "$OUT"

run_dos() {
    "$KVIKDOS" \
        --mount=c:"$OZZIE"/ \
        --mount=d:"$SRC"/ \
        --mount=e:"$OUT"/ \
        --drive=d \
        --env="PATH=d:\TOOLS" \
        --env="INCLUDE=d:\TOOLS\INC" \
        --env="LIB=d:\TOOLS\LIB" \
        --env="INIT=d:\TOOLS" \
        --env="COUNTRY=usa-ms" \
        --env="COMSPEC=c:\COMMAND.COM" \
        "$@"
}

echo "Testing NMAKE..."
run_dos "$SRC/TOOLS/NMAKE.EXE"
