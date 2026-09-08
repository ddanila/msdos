#!/usr/bin/env python3
"""Audit ordinary boot profiles without rebuilding the frozen composition.

This records observed failures as promotion blockers; it does not treat a
recognized diagnostic halt as a successful boot.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from capture_vc_memory_comparison import ROOT, image_file
from test_dos_char_retirement_qemu import install


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('composition', type=Path)
    parser.add_argument('--record', type=Path)
    args = parser.parse_args()
    source = args.composition.resolve()
    image = source/'candidate.img'
    build = json.loads((source/'build.json').read_text())
    assert sha(image) == build['image_sha256']
    for name, value in build['installed_sha256'].items():
        assert hashlib.sha256(image_file(image, '::'+name)).hexdigest() == value, name
    original = image_file(image, '::CONFIG.SYS')
    profiles = {
        'existing': original,
        'dos-low': original.replace(b'DOS=HIGH,UMB', b'DOS=LOW,UMB'),
        'bare-low': b'\r\n'.join(line for line in original.replace(b'DOS=HIGH,UMB', b'DOS=LOW').splitlines()
                                  if b'HIMEM.SYS' not in line.upper() and b'EMM386.EXE' not in line.upper())+b'\r\n',
        'himem-high': b'\r\n'.join(line for line in original.splitlines()
                                    if b'EMM386.EXE' not in line.upper())+b'\r\n',
    }
    work = Path(tempfile.mkdtemp(prefix='promotion-profiles-', dir=ROOT/'out'))
    print(f'Artifacts: {work}', flush=True)
    subprocess.run(['nasm', '-f', 'bin', ROOT/'tests/qemu_exit.asm', '-o', work/'QEXIT.COM'], check=True)
    report = dict(schema=1, candidate_sha256=sha(image), build_record_sha256=sha(source/'build.json'),
                  runner_sha256=sha(Path(__file__)), results={}, all_profiles_boot=False)
    for label, config in profiles.items():
        directory = work/label
        directory.mkdir()
        disk = directory/'boot.img'
        shutil.copyfile(image, disk)
        install(disk, 'CONFIG.SYS', config)
        install(disk, 'AUTOEXEC.BAT', b'@ECHO OFF\r\nCTTY AUX\r\nECHO PROFILE_BOOT_PASS\r\nQEXIT.COM\r\n')
        install(disk, 'QEXIT.COM', (work/'QEXIT.COM').read_bytes())
        (directory/'CONFIG.SYS').write_bytes(config)
        command = ['qemu-system-i386', '-machine', 'pc', '-cpu', '486', '-m', '8',
                   '-display', 'none', '-monitor', 'none', '-serial', f'file:{directory}/serial.log',
                   '-debugcon', f'file:{directory}/debug.log', '-no-reboot', '-nic', 'none', '-boot', 'c',
                   '-drive', f'if=ide,format=raw,file={disk}',
                   '-device', 'isa-debug-exit,iobase=0xf4,iosize=0x04']
        with (directory/'qemu.log').open('wb') as log:
            try:
                exit_code = subprocess.run(command, stdout=log, stderr=log, timeout=60).returncode
            except subprocess.TimeoutExpired:
                exit_code = 124
        serial = (directory/'serial.log').read_bytes()
        debug = (directory/'debug.log').read_bytes()
        booted = exit_code == 33 and b'PROFILE_BOOT_PASS' in serial
        report['results'][label] = dict(booted=booted, exit_code=exit_code,
            hma_expectation_diagnostic=exit_code == 35 and debug.endswith(b'XF\x0a'),
            config=config.decode(), command=command, directory=str(directory.relative_to(ROOT)),
            serial_sha256=sha(directory/'serial.log'), debug_sha256=sha(directory/'debug.log'),
            preserved_core_sha256={name:hashlib.sha256(image_file(disk, '::'+name)).hexdigest()
                                   for name in build['installed_sha256']})
        assert report['results'][label]['preserved_core_sha256'] == build['installed_sha256']
        (work/'results.json').write_text(json.dumps(report, indent=2)+'\n')
        print(label, 'BOOTED' if booted else f'BLOCKED (exit {exit_code})', flush=True)
    assert sha(image) == report['candidate_sha256']
    report['all_profiles_boot'] = all(row['booted'] for row in report['results'].values())
    text = json.dumps(report, indent=2)+'\n'
    (work/'results.json').write_text(text)
    if args.record:
        args.record.write_text(text)
    raise SystemExit(0 if report['all_profiles_boot'] else 1)


if __name__ == '__main__':
    main()
