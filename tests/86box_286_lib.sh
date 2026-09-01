#!/usr/bin/env bash

find_86box_286() {
    if [[ -n ${BOX86_BIN:-} && -x ${BOX86_BIN} ]]; then
        printf '%s\n' "$BOX86_BIN"
        return 0
    fi
    if command -v 86Box >/dev/null 2>&1; then
        command -v 86Box
        return 0
    fi
    if command -v 86box >/dev/null 2>&1; then
        command -v 86box
        return 0
    fi
    local mac_app=/Applications/86Box.app/Contents/MacOS/86Box
    [[ -x $mac_app ]] && printf '%s\n' "$mac_app"
}

find_86box_roms() {
    if [[ -n ${BOX86_ROMS:-} && -d ${BOX86_ROMS} ]]; then
        printf '%s\n' "$BOX86_ROMS"
        return 0
    fi
    local mac_roms=${HOME}/Library/Application\ Support/net.86box.86Box/roms
    [[ -d $mac_roms ]] && printf '%s\n' "$mac_roms"
}

skip_86box_286() {
    echo "SKIP: $1" >&2
    if [[ ${FAIL_ON_SKIP:-0} == 1 ]]; then
        return 1
    fi
    return 77
}

check_86box_286_prerequisites() {
    local executable roms required
    executable=$(find_86box_286 || true)
    roms=$(find_86box_roms || true)
    [[ -n $executable ]] || {
        skip_86box_286 "86Box 6.x is unavailable; install the 86box Homebrew cask or set BOX86_BIN"
        return
    }
    [[ -n $roms ]] || {
        skip_86box_286 "86Box ROMs are unavailable; install the official ROM set or set BOX86_ROMS"
        return
    }
    for required in \
        machines/ibmat/BIOS_5170_15NOV85_U27.BIN \
        machines/ibmat/BIOS_5170_15NOV85_U47.BIN; do
        [[ -f $roms/$required ]] || {
            skip_86box_286 "86Box IBM 5170 ROM is missing: $roms/$required"
            return
        }
    done
}

make_86box_286_boot_image() {
    local output=$1 root=$2
    local required
    for required in \
        "$root/src/BOOT/MSBOOT.BIN" \
        "$root/src/BIOS/IO.SYS" \
        "$root/src/DOS/MSDOS.SYS" \
        "$root/src/CMD/COMMAND/COMMAND.COM" \
        "$root/src/BIOS/SYSMENU.OVL"; do
        [[ -f $required ]] || {
            echo "ERROR: missing build artifact: $required; run 'make deploy' first" >&2
            return 1
        }
    done

    mkdir -p "$(dirname "$output")"
    dd if=/dev/zero of="$output" bs=512 count=2400 status=none
    dd if="$root/src/BOOT/MSBOOT.BIN" of="$output" bs=1 skip=31744 \
        count=512 conv=notrunc status=none
    "$root/bin/patch-bpb" "$output"
    mformat -i "$output" -k ::
    # IO.SYS must remain the first root entry for this boot sector.
    mcopy -i "$output" "$root/src/BIOS/IO.SYS" ::IO.SYS
    mcopy -i "$output" "$root/src/DOS/MSDOS.SYS" ::MSDOS.SYS
    mcopy -i "$output" "$root/src/CMD/COMMAND/COMMAND.COM" ::COMMAND.COM
    mcopy -i "$output" "$root/src/BIOS/SYSMENU.OVL" ::SYSMENU.OVL
    python3 "$root/tests/compact_fat_root.py" "$output"
}

stop_86box_286() {
    local pid=$1 attempt
    kill -TERM "$pid" 2>/dev/null || return 0
    for attempt in 1 2 3; do
        kill -0 "$pid" 2>/dev/null || return 0
        sleep 1
    done
    kill -KILL "$pid" 2>/dev/null || true
}

run_86box_286() {
    local image=$1 pass_marker=$2 fail_marker=$3 deadline=${4:-180}
    local root=$5 require_result=${6:-1}
    local executable roms work pid outcome second result failure_dir
    executable=$(find_86box_286)
    roms=$(find_86box_roms)
    work=$(mktemp -d "${TMPDIR:-/tmp}/msdos-86box-286.XXXXXX")
    cp "$root/tests/86box/ibmat-286.cfg" "$work/86box.cfg"
    cp "$root/tests/86box/global.cfg" "$work/global.cfg"
    cp "$image" "$work/test.img"
    python3 "$root/tests/seed_86box_ibmat_nvram.py" \
        "$work/nvr/ibm5170_111585.nvr"

    "$executable" -N -O "$work/global.cfg" -P "$work" -R "$roms" \
        -I "a:$work/test.img" \
        -L "$work/86box.log" >"$work/serial.log" 2>"$work/stderr.log" &
    pid=$!
    outcome=timeout
    for second in $(seq 1 "$deadline"); do
        if grep -Fq "$fail_marker" "$work/serial.log"; then
            outcome=product-failure
            break
        fi
        if grep -Fq "$pass_marker" "$work/serial.log"; then
            outcome=pass
            break
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            outcome=startup-failure
            break
        fi
        sleep 1
    done
    stop_86box_286 "$pid"
    wait "$pid" 2>/dev/null || true

    result=$(mtype -i "$work/test.img" ::RESULT.TXT 2>/dev/null | tr -d '\r' || true)
    if [[ $outcome == pass && ( $require_result == 0 || $result == *"$pass_marker"* ) ]]; then
        printf '%s' "$result"
        rm -rf "$work"
        return 0
    fi

    failure_dir="$root/out/86box-286-failures/$(date +%Y%m%d-%H%M%S)-$$"
    mkdir -p "$failure_dir"
    cp "$work/86box.cfg" "$work/global.cfg" "$work/test.img" "$work/serial.log" \
        "$work/stderr.log" "$failure_dir/"
    [[ ! -f $work/86box.log ]] || cp "$work/86box.log" "$failure_dir/"
    rm -rf "$work"
    echo "FAIL: 86Box 286 $outcome; diagnostics: $failure_dir" >&2
    printf '%s\n' "$result" >&2
    sed -n '1,200p' "$failure_dir/serial.log" >&2
    return 1
}
