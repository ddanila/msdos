#!/usr/bin/env python3
"""Opt-in Win95 setup reproduction using external user-supplied media.

Requires pycdlib, mtools, QEMU, and Tesseract. Never modifies the source ISO or reuses a
VM disk. Outputs (including extracted Microsoft files) must remain untracked.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iso', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--floppy', type=Path, default=ROOT/'out/floppy.img')
    parser.add_argument('--mode', choices=('normal', 'skip-scandisk', 'fork-smartdrv'), default='normal')
    parser.add_argument('--seconds', type=int, default=30)
    args = parser.parse_args()
    if not 1 <= args.seconds <= 300:
        parser.error('--seconds must be between 1 and 300')
    import pycdlib
    out = args.output.resolve()
    # Keep proprietary artifacts within the repository's ignored output tree.
    if not out.is_relative_to(ROOT / 'out') or out == ROOT / 'out':
        parser.error('--output must be a new subdirectory under out/')
    out.mkdir(parents=True, exist_ok=False)
    iso = pycdlib.PyCdlib()
    iso.open(str(args.iso.resolve()))
    source = out / 'WIN95'
    source.mkdir()
    for parent, dirs, files in iso.walk(iso_path='/WIN95'):
        if dirs:
            raise RuntimeError('Expected flat WIN95 source directory')
        for name in files:
            iso.get_file_from_iso(str(source / name.split(';')[0]), iso_path=parent+'/'+name)
    iso.close()
    sectors = 1024 * 16 * 63
    def chs(lba):
        c, rem = divmod(lba, 16 * 63)
        h, s = divmod(rem, 63)
        return bytes((h, (s+1) | ((c >> 2) & 0xc0), c & 255))
    mbr = bytearray(512)
    code = (ROOT/'src/CMD/FDISK/FDBOOT.BIN').read_bytes()[0x600:0x600+446]
    assert len(code) == 446
    mbr[:446] = code
    mbr[446:462] = b'\x80'+chs(63)+b'\x06'+chs(sectors-1)+struct.pack('<II',63,sectors-63)
    mbr[510:] = b'\x55\xaa'
    disk = out/'disk.img'
    with disk.open('xb') as f:
        f.write(mbr)
        f.truncate(sectors*512)
    volume = str(disk)+'@@32256'
    run('mformat','-i',volume,'-t','1024','-h','16','-n','63','-H','63','-c','16','::')
    run('mcopy','-s','-i',volume,str(source),'::')
    boot = out/'boot.img'
    shutil.copyfile(args.floppy,boot)
    def put(name, text):
        run('mcopy','-o','-i',str(boot),'-','::'+name,input=text.replace('\n','\r\n').encode('ascii'))
    put('CONFIG.SYS','FILES=60\nBUFFERS=30\n')
    cache = 'A:\\SMARTDRV.EXE\n' if args.mode == 'fork-smartdrv' else ''
    switch = ' /IS' if args.mode == 'skip-scandisk' else ''
    put('AUTOEXEC.BAT','@ECHO OFF\nVER\n'+cache+
        'ECHO PROBE_CACHE_RETURNED\nC:\nECHO PROBE_DRIVE_SELECTED\n'
        'CD \\WIN95\nECHO PROBE_SETUP_START\nSETUP'+switch+'\n'
        'ECHO PROBE_SETUP_RETURNED\n')
    command = ['qemu-system-i386','-machine','pc','-accel','tcg','-cpu','pentium',
               '-m','32','-icount','shift=5,align=off,sleep=on','-nic','none',
               '-drive','file='+str(disk)+',format=raw,if=ide,index=0',
               '-drive','file='+str(boot)+',format=raw,if=floppy,index=0',
               '-boot','a','-vga','cirrus','-display','none',
               '-qmp','unix:'+str(out/'qmp.sock')+',server=on,wait=off',
               '-rtc','base=1996-01-01,clock=vm']
    with args.iso.open('rb') as media:
        iso_hash = hashlib.file_digest(media,'sha256').hexdigest()
    report = {'mode':args.mode,'command':command,
              'revision':run('git','rev-parse','HEAD',cwd=ROOT,capture_output=True,text=True).stdout.strip(),
              'boot_sha256':hashlib.sha256(boot.read_bytes()).hexdigest(),
              'base_floppy_path':str(args.floppy.resolve()),
              'base_floppy_sha256':hashlib.sha256(args.floppy.read_bytes()).hexdigest(),
              'source_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(source.iterdir())},
              'iso_sha256':iso_hash}
    with (out/'qemu.log').open('wb') as log:
        process = subprocess.Popen(command,stdout=log,stderr=log)
        sock = socket.socket(socket.AF_UNIX)
        try:
            deadline = time.monotonic()+10
            while True:
                try:
                    sock.connect(str(out/'qmp.sock'))
                    break
                except (FileNotFoundError,ConnectionRefusedError):
                    if process.poll() is not None or time.monotonic()>deadline:
                        raise RuntimeError('QEMU did not start')
                    time.sleep(.1)
            sock.settimeout(10)
            stream=sock.makefile('rwb',buffering=0)
            stream.readline()
            def qmp(cmd, **arguments):
                stream.write((json.dumps({'execute':cmd,'arguments':arguments})+'\n').encode())
                while True:
                    response=json.loads(stream.readline())
                    if 'error' in response:
                        raise RuntimeError(response)
                    if 'return' in response:
                        return response['return']
            qmp('qmp_capabilities')
            # Boot latency varies with host load. Do not send a blind early
            # Enter that the BIOS consumes before Setup starts.
            deadline = time.monotonic()+120
            while True:
                qmp('screendump',filename=str(out/'before-enter.ppm'))
                text = run('tesseract',str(out/'before-enter.ppm'),'stdout',
                           capture_output=True,text=True).stdout
                if 'press ENTER' in text or 'Welcome to Windows 95' in text:
                    report['before_enter_text'] = text
                    break
                if time.monotonic()>deadline:
                    raise RuntimeError('Setup did not reach its initial prompt: '+text)
                time.sleep(2)
            qmp('human-monitor-command',**{'command-line':'sendkey ret 30'})
            time.sleep(args.seconds)
            qmp('screendump',filename=str(out/'after.ppm'))
            report['after_text'] = run('tesseract',str(out/'after.ppm'),'stdout',
                                       capture_output=True,text=True).stdout
            qmp('quit')
            process.wait(timeout=10)
        except Exception as error:
            report['error'] = str(error)
            try:
                report['registers'] = qmp('human-monitor-command',
                    **{'command-line':'info registers'})
            except Exception:
                pass
        finally:
            sock.close()
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
    changes=[]
    for original in sorted(source.iterdir()):
        result=subprocess.run(['mtype','-i',volume,'::WIN95/'+original.name],capture_output=True)
        if result.returncode or result.stdout != original.read_bytes():
            changes.append({'file':original.name,'read_error':result.stderr.decode(errors='replace'),
                            'returned_bytes':len(result.stdout)})
    report['changed_source_files']=changes
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'output':str(out),'mode':args.mode,'changed_source_files':len(changes)}),flush=True)
    if 'error' in report:
        raise SystemExit(report['error'])


if __name__ == '__main__':
    main()
