#!/usr/bin/env python3
"""Require FC to compare files on the DOS 6.22 kernel, LOW and HIGH."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--floppy', type=Path, default=ROOT/'out/floppy.img')
    parser.add_argument('--binary', type=Path, default=ROOT/'src/CMD/FC/FC.EXE')
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix='fc-qemu-', dir=ROOT/'out'))
    print(f'Artifacts: {work}', flush=True)
    subprocess.run(['nasm','-f','bin',ROOT/'tests/qemu_exit.asm','-o',work/'QEXIT.COM'],check=True)
    report = dict(floppy_sha256=hashlib.sha256(args.floppy.read_bytes()).hexdigest(),
                  fc_sha256=hashlib.sha256(args.binary.read_bytes()).hexdigest(), results={})
    for mode in ('LOW', 'HIGH'):
        disk = work/(mode+'.img')
        shutil.copyfile(args.floppy,disk)

        def install(name, data):
            subprocess.run(['mcopy','-o','-i',disk,'-','::'+name],input=data,check=True)

        install('FC.EXE', args.binary.read_bytes())
        install('QEXIT.COM', (work/'QEXIT.COM').read_bytes())
        install('LEFT.BIN', bytes(range(256)))
        install('RIGHT.BIN', bytes(range(256)))
        install('DIFF.BIN', bytes(range(255))+b'\0')
        install('LEFT.TXT', b'alpha\r\nbeta\r\n')
        install('RIGHT.TXT', b'alpha\r\nBETA\r\n')
        install('CONFIG.SYS', (('DEVICE=HIMEM.SYS\r\n' if mode=='HIGH' else '')+
                              f'DOS={mode}\r\nFILES=20\r\nBUFFERS=15\r\n').encode())
        install('AUTOEXEC.BAT', b'@ECHO OFF\r\nCTTY AUX\r\n'
            b'FC /B LEFT.BIN RIGHT.BIN\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
            b'FC /B LEFT.BIN DIFF.BIN\r\nIF ERRORLEVEL 2 GOTO FAIL\r\nIF NOT ERRORLEVEL 1 GOTO FAIL\r\n'
            b'FC /C LEFT.TXT RIGHT.TXT\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
            b'FC /N LEFT.TXT RIGHT.TXT\r\nIF ERRORLEVEL 2 GOTO FAIL\r\nIF NOT ERRORLEVEL 1 GOTO FAIL\r\n'
            b'ECHO FC_COMPARE_PASS\r\nQEXIT\r\n:FAIL\r\nECHO FC_COMPARE_FAIL\r\nQEXIT\r\n')
        command = ['qemu-system-i386','-display','none','-monitor','none','-cpu','486','-m','8',
                   '-boot','a','-serial','stdio','-no-reboot','-nic','none',
                   '-drive',f'if=floppy,format=raw,file={disk}',
                   '-device','isa-debug-exit,iobase=0xf4,iosize=0x04']
        with (work/(mode+'.log')).open('wb') as log:
            result = subprocess.run(command,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,timeout=30)
        data = (work/(mode+'.log')).read_bytes()
        passed = (result.returncode==33 and b'FC_COMPARE_PASS' in data and b'FC_COMPARE_FAIL' not in data
                  and b'000000FF: FF 00' in data and b'2:  beta' in data and b'2:  BETA' in data)
        report['results'][mode] = dict(passed=passed,exit_code=result.returncode,command=command,
                                      log_sha256=hashlib.sha256(data).hexdigest())
        (work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
        assert passed, data
        print(mode, 'PASS',flush=True)
    assert hashlib.sha256(args.floppy.read_bytes()).hexdigest()==report['floppy_sha256']


if __name__ == '__main__':
    main()
