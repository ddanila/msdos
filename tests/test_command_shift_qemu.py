#!/usr/bin/env python3
"""Require a child shell to reload its transient after its allocation end changes."""
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
    parser.add_argument('--command', type=Path, default=ROOT/'src/CMD/COMMAND/COMMAND.COM')
    parser.add_argument('--floppy', type=Path, default=ROOT/'out/floppy.img')
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix='command-shift-', dir=ROOT/'out'))
    print(f'Artifacts: {work}', flush=True)
    for source, target in (('command_shift_probe.asm','ZSHIFT.COM'),('qemu_exit.asm','QEXIT.COM')):
        subprocess.run(['nasm','-f','bin',ROOT/'tests'/source,'-o',work/target],check=True)
    report = dict(command_sha256=hashlib.sha256(args.command.read_bytes()).hexdigest(),
                  floppy_sha256=hashlib.sha256(args.floppy.read_bytes()).hexdigest(), results={})
    for mode in ('LOW','HIGH'):
        disk = work/(mode+'.img')
        shutil.copyfile(args.floppy,disk)
        def install(name, data):
            subprocess.run(['mcopy','-o','-i',disk,'-','::'+name],input=data,check=True)
        for name in ('ZSHIFT.COM','QEXIT.COM'):
            install(name,(work/name).read_bytes())
        install('COMMAND.COM',args.command.read_bytes())
        install('CONFIG.SYS', ('DEVICE=A:\\HIMEM.SYS\r\nDOS='+mode+'\r\nBUFFERS=15\r\n').encode())
        install('AUTOEXEC.BAT', b'@ECHO OFF\r\nCTTY AUX\r\nZSHIFT.COM\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
                b'ECHO SHIFT_PARENT_PASS\r\nQEXIT\r\n:FAIL\r\nECHO SHIFT_PARENT_FAIL\r\nQEXIT\r\n')
        command = ['qemu-system-i386','-display','none','-monitor','none','-cpu','486','-m','8',
                   '-boot','a','-serial','stdio','-no-reboot','-nic','none',
                   '-drive',f'if=floppy,format=raw,file={disk}',
                   '-device','isa-debug-exit,iobase=0xf4,iosize=0x04']
        try:
            result = subprocess.run(command,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT,timeout=30)
            output, code = result.stdout, result.returncode
        except subprocess.TimeoutExpired as error:
            output, code = error.stdout or b'', None
        (work/(mode+'.log')).write_bytes(output)
        passed = (code==33 and all(marker in output for marker in
                  (b'SHIFT_RECOVERED', b'SHIFT_QUERY_EXERCISED', b'SHIFT_PARENT_PASS'))
                  and b'SHIFT_PARENT_FAIL' not in output)
        report['results'][mode] = dict(passed=passed,exit_code=code,command=command)
        (work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
        assert passed, output
        print(mode,'PASS',flush=True)
    assert hashlib.sha256(args.floppy.read_bytes()).hexdigest()==report['floppy_sha256']

if __name__ == '__main__':
    main()
