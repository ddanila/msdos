#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE_IMAGE="${MUTATION_BASE_IMAGE:-$ROOT/out/floppy.img}"

if [[ $# -lt 2 ]]; then
    echo "usage: $0 tests/test_name.sh DOS_FILE [test arguments ...]" >&2
    exit 2
fi

TEST_SCRIPT=$1
DOS_FILE=$2
shift 2

case "$TEST_SCRIPT" in
    tests/test*.sh) ;;
    *) echo "test script must be a tests/test*.sh path" >&2; exit 2 ;;
esac
if [[ ! "$DOS_FILE" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
    echo "DOS file must be a root-directory 8.3-style name" >&2
    exit 2
fi
if [[ ! -f "$ROOT/$TEST_SCRIPT" || ! -f "$BASE_IMAGE" ]]; then
    echo "missing test script or base floppy image" >&2
    exit 2
fi

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/msdos-oracle-mutation.XXXXXX")
trap 'rm -f "$WORKDIR/floppy.img"; rmdir "$WORKDIR"' EXIT HUP INT TERM
MUTATED_IMAGE="$WORKDIR/floppy.img"
cp "$BASE_IMAGE" "$MUTATED_IMAGE"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
if ! mdel -i "$MUTATED_IMAGE" "::$DOS_FILE" 2>/dev/null; then
    echo "cannot remove $DOS_FILE from the mutation image" >&2
    exit 2
fi

echo "=== Oracle mutation: remove $DOS_FILE, run $TEST_SCRIPT ==="
if FLOPPY_IMAGE="$MUTATED_IMAGE" bash "$ROOT/$TEST_SCRIPT" "$@"; then
    echo "SURVIVED: $TEST_SCRIPT passed without $DOS_FILE" >&2
    exit 1
fi

echo "KILLED: $TEST_SCRIPT detected removal of $DOS_FILE"
