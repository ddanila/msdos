#!/usr/bin/env python3
"""Boot synthetic EXEPACK positive and signature-miss controls below 64 KiB."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

from capture_dos_app_smoke import ROOT, install, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--floppy', type=Path, default=ROOT / 'out/floppy.img')
    parser.add_argument('--expect-unpatched', action='store_true',
                        help='negative control against a pre-fix build')
    args = parser.parse_args()
    output = Path(tempfile.mkdtemp(prefix='exepack-', dir=ROOT / 'out'))
    print('Evidence:', output, flush=True)
    for name, defines in [('PACKED', []), ('NEARMISS', ['-DNEAR_MISS'])]:
        run(['nasm', '-f', 'bin', *defines, ROOT / 'tests/exepack_low_probe.asm',
             '-o', output / (name + '.EXE')])
    run(['nasm', '-f', 'bin', ROOT / 'tests/qemu_exit.asm', '-o', output / 'QEXIT.COM'])
    # Real HIMEM with DOS high keeps A20 on. The synthetic decoder needs no
    # external files, and its payload asserts actual placement below 64 KiB.
    for label, manager in [('xms', ''), ('ems', 'DEVICE=A:\\EMM386.EXE 2048 RAM\r\n')]:
        disk = output / (label + '.img')
        shutil.copyfile(args.floppy, disk)
        config = ('DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF\r\n' + manager +
                  'DOS=HIGH\r\nFILES=30\r\nBUFFERS=15\r\n')
        install(disk, 'CONFIG.SYS', config.encode(), True)
        for name in ('PACKED.EXE', 'NEARMISS.EXE', 'QEXIT.COM'):
            install(disk, name, (output / name).read_bytes(), True)
        install(disk, 'AUTOEXEC.BAT',
                b'@ECHO OFF\r\nCTTY AUX\r\nECHO POSITIVE_BEGIN\r\nPACKED.EXE\r\n'
                b'ECHO NEGATIVE_BEGIN\r\nNEARMISS.EXE\r\nECHO EXEPACK_DONE\r\nQEXIT.COM\r\n', True)
        result = subprocess.run(['qemu-system-i386', '-machine', 'pc', '-cpu', '486',
            '-m', '8', '-d', 'nochain', '-display', 'none', '-monitor', 'none',
            '-serial', 'stdio', '-nic', 'none', '-no-reboot', '-boot', 'a',
            '-drive', f'if=floppy,format=raw,file={disk}',
            '-device', 'isa-debug-exit,iobase=0xf4,iosize=0x04'],
            capture_output=True, timeout=45)
        log = result.stdout + result.stderr
        (output / (label + '.log')).write_bytes(log)
        positive, separator, negative = log.partition(b'NEGATIVE_BEGIN')
        witness = b'EXEPACK_CORRUPT' if args.expect_unpatched else b'EXEPACK_LOW_PASS'
        assert separator and witness in positive, log.decode(errors='replace')
        assert b'EXEPACK_CORRUPT' in negative and b'EXEPACK_LOW_PASS' not in negative, log
        assert b'EXEPACK_DONE' in negative and result.returncode == 33, log
        if not args.expect_unpatched:
            assert b'EXEPACK_CORRUPT' not in positive, log
        print(label, 'PASS: decoder and signature-miss controls', flush=True)


if __name__ == '__main__':
    main()
