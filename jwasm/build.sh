#!/bin/bash
# Build the pinned custom JWasm revision for the current supported host.

set -euo pipefail

readonly REVISION=a41092c069bb1d8ae6dda889d7d5643b744edd99
readonly REPOSITORY=https://github.com/ddanila/JWasm.git
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

case "$(uname -s)-$(uname -m)" in
    Darwin-arm64)
        platform=macos-arm64
        compiler=clang
        ;;
    Linux-x86_64)
        platform=linux-x64
        compiler="${CC:-gcc}"
        ;;
    *)
        echo "build.sh: unsupported host $(uname -s)-$(uname -m)" >&2
        exit 1
        ;;
esac

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT HUP INT TERM

git clone --quiet --filter=blob:none "$REPOSITORY" "$workdir/JWasm"
git -C "$workdir/JWasm" checkout --quiet --detach "$REVISION"

if [[ "$platform" == macos-arm64 ]]; then
    # GccUnix.mak's Linux-only strip/map link flags fail on macOS, after all
    # objects have been compiled. Link those objects natively with clang.
    make -C "$workdir/JWasm" -f GccUnix.mak CC="$compiler" >/dev/null 2>&1 || true
    "$compiler" "$workdir"/JWasm/build/GccUnixR/*.o -o "$workdir/jwasm-bin"
else
    make -C "$workdir/JWasm" -f GccUnix.mak CC="$compiler"
    cp "$workdir/JWasm/build/GccUnixR/jwasm" "$workdir/jwasm-bin"
fi

mkdir -p "$SCRIPT_DIR/$platform"
install -m 0755 "$workdir/jwasm-bin" "$SCRIPT_DIR/$platform/jwasm"
"$SCRIPT_DIR/$platform/jwasm" '-?' 2>&1 | sed -n '1p'
echo "Built $platform JWasm from $REVISION"
