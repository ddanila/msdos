#!/usr/bin/env python3
"""Install/upgrade private media and boot the shipped RU recipe from C:\\DOS."""
import hashlib
import json
import os
from pathlib import Path
import select
import shutil
import struct
import subprocess
import tempfile
import time

from screen_expect import QMPConnection
from test_ru_country_qemu import compile_probes
from test_ru_keyboard_qemu import steps

ROOT = Path(__file__).resolve().parents[1]
OFFSET = 63 * 512


def command(*args, **kwargs):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)


def copy(image, source, target):
    command('mcopy', '-o', '-i', str(image), str(source), '::'+target)


def write(image, target, data):
    command('mcopy', '-o', '-i', str(image), '-', '::'+target, input=data)


def read(image, target):
    return command('mtype', '-i', str(image), '::'+target).stdout


def run_guest(work, hdd, disk1=None, disk2=None, keyboard=False,
              cases_override=None, expected_markers=None, capture_font=False):
    work.mkdir()
    log = work/'serial.log'
    args = [os.environ.get('QEMU', 'qemu-system-i386'), '-display', 'none', '-m', '8',
            '-drive', f'if=ide,index=0,format=raw,file={hdd},cache=writethrough',
            '-boot', 'a' if disk1 else 'c', '-serial', 'stdio', '-no-reboot',
            '-device', 'isa-debug-exit,iobase=0xf4,iosize=0x04']
    if disk1:
        args += ['-drive', f'if=floppy,index=0,format=raw,file={disk1},cache=writethrough']
    output = bytearray()
    answered = set()
    key_index = 0
    cases = cases_override if cases_override is not None else steps() if keyboard else []
    font_captured = False
    with tempfile.TemporaryDirectory(prefix='rui-') as sockets, log.open('wb') as stream:
        proc = subprocess.Popen(args+['-qmp', f'unix:{sockets}/q,server=on,wait=off'],
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        qmp = None
        try:
            qmp = QMPConnection(sockets+'/q')
            deadline = time.monotonic()+120
            while proc.poll() is None:
                if time.monotonic() > deadline:
                    raise AssertionError(f'guest timeout: {log}')
                ready, _, _ = select.select([proc.stdout], [], [], .05)
                if ready:
                    chunk = os.read(proc.stdout.fileno(), 8192)
                    output += chunk
                    stream.write(chunk)
                    stream.flush()
                if capture_font and not font_captured and b'RU_FONT_READY' in output:
                    qmp.human_cmd(f'screendump "{work / "font.ppm"}"')
                    qmp.send_key('ret')
                    font_captured = True
                for prompt, response in [(b'Continue (Y/N)?', b'Y\r'),
                                         (b'Configure HIMEM', b'Y\r'),
                                         (b'Load SMARTDrive', b'N\r'),
                                         (b'Enable UNDELETE Delete Sentry', b'N\r'),
                                         (b'Insert MS-DOS 6.22 Disk 2', b'\r')]:
                    if prompt in output and prompt not in answered:
                        if prompt.startswith(b'Insert'):
                            if disk2 is None:
                                raise AssertionError('unexpected media prompt')
                            result = qmp.human_cmd(f'change floppy0 {disk2} raw')
                            if result.strip():
                                raise AssertionError(result)
                        proc.stdin.write(response)
                        proc.stdin.flush()
                        answered.add(prompt)
                if key_index < len(cases) and f'RU_KEY_READY {key_index:04X}\r\n'.encode() in output:
                    for key, down in cases[key_index]['keys']:
                        qmp._send({'execute':'input-send-event', 'arguments':{'events':[
                            {'type':'key','data':{'down':down,'key':{'type':'qcode','data':key}}}]}})
                        response = qmp._recv_response()
                        if 'error' in response:
                            raise AssertionError(response)
                        time.sleep(.005)
                    key_index += 1
            tail = proc.stdout.read()
            output += tail
            stream.write(tail)
            if proc.returncode != 33:
                raise AssertionError(f'emulator exit {proc.returncode}: {log}')
        finally:
            if qmp:
                qmp.close()
            if proc.poll() is None:
                proc.kill()
                proc.wait()
    if b'RU_INSTALL_FAIL' in output or b'RU_INSTALLED_DONE' not in output:
        raise AssertionError(f'missing completion: {log}\n{output[-2000:]!r}')
    if keyboard:
        marker = b'RU_LOW_PASS' if work.name.endswith('low') else b'RU_HIGH_UMB_PASS'
        if marker not in output:
            raise AssertionError(f'missing memory profile proof: {log}')
    if disk1:
        expected = b'Fresh installation to C:\\DOS' if work.name == 'fresh' else b'Upgrade installation in C:\\DOS'
        if expected not in output:
            raise AssertionError(f'wrong installation mode: {log}')
        if b'Setup completed successfully' not in output or b'Insert MS-DOS' not in output:
            raise AssertionError(f'incomplete installer: {log}')
    else:
        for marker in expected_markers or (b'RU_KEY_PASS', b'RU_COUNTRY_PASS', b'RU_CODEPAGE_PASS',
                       b'Current keyboard code: RU', b'Current keyboard ID: 441'):
            if marker not in output:
                raise AssertionError(f'missing {marker!r}: {log}')
        if key_index != len(cases) or b'FAIL' in output:
            raise AssertionError(f'input failure: {log}')
    if capture_font:
        assert font_captured and output.count(b'RU_FONT_PASS') == 1, log
    print(f'PASS: {work.name}', flush=True)
    return {'name':work.name, 'emulator_exit':proc.returncode, 'physical_reads':key_index,
            'log':str(log), 'log_sha256':hashlib.sha256(output).hexdigest()}


def verify_files(partition):
    files = json.loads((ROOT/'distribution/files.json').read_text())
    hashes = {}
    for source, name in files['compressed']:
        if name in {'COUNTRY.SYS','KEYB.COM','KEYBRD2.SYS','EGA866.CPI','RUSSIAN.TXT','RUFONT1.TXT','RUFONT2.TXT','DISPLAY.SYS','NLSFUNC.EXE','MODE.COM'}:
            data = read(partition, 'DOS/'+name)
            if data != (ROOT/source).read_bytes():
                raise AssertionError('installed payload mismatch: '+name)
            hashes[name] = hashlib.sha256(data).hexdigest()
    core = json.loads((Path(os.environ['MEMORY_CORE_DIR']).parent/'build.json').read_text())['sha256']
    for name, expected in core.items():
        target = name if name in ('IO.SYS','MSDOS.SYS') else 'DOS/'+name
        digest = hashlib.sha256(read(partition,target)).hexdigest()
        if digest != expected:
            raise AssertionError('installed production core mismatch: '+name)
        hashes[name] = digest
    return hashes


def prepare_install_disk(work):
    hdd = work/'hdd.img'
    with hdd.open('wb') as output:
        output.truncate(64512*512)
    mbr = bytearray(512)
    mbr[:446] = (ROOT/'src/CMD/FDISK/FDBOOT.BIN').read_bytes()[0x600:0x600+446]
    mbr[446:462] = bytes((0x80,1,1,0,4,15,63,63))+struct.pack('<II',63,64449)
    mbr[510:512] = b'\x55\xaa'
    with hdd.open('r+b') as output:
        output.write(mbr)
    partition = f'{hdd}@@{OFFSET}'
    command('mformat', '-i', partition, '-t','64','-h','16','-n','63','-H','63','-c','4','::')
    return hdd, partition


def main():
    if not os.environ.get('MEMORY_CORE_DIR'):
        raise SystemExit('Run make test-ru-install-qemu to select the production memory core.')
    work = Path(tempfile.mkdtemp(prefix='ru-install-', dir=ROOT/'out'))
    print(f'Russian installation artifacts: {work}', flush=True)
    media = work/'media'
    command('python3', str(ROOT/'tools/build_distribution.py'), '--output', str(media))
    hdd, partition = prepare_install_disk(work)
    probes = work/'probes'
    probes.mkdir()
    compile_probes(probes)
    copy(partition, probes/'QEXIT.COM', 'QEXIT.COM')
    keep = b'preserve Russian installation sentinel\r\n'
    write(partition, 'KEEP.TXT', keep)
    batch = b'@ECHO OFF\r\nCTTY AUX\r\nSETUP C:\\DOS\r\nIF ERRORLEVEL 1 GOTO FAIL\r\nECHO RU_INSTALLED_DONE\r\nC:\\QEXIT.COM\r\n:FAIL\r\nECHO RU_INSTALL_FAIL\r\nC:\\QEXIT.COM\r\n'
    # COMMAND continues reading AUTOEXEC after the media swap.
    for name in ('disk1.img','disk2.img'):
        write(media/name, 'AUTOEXEC.BAT', batch)
    results = [run_guest(work/'fresh',hdd,media/'disk1.img',media/'disk2.img')]
    fresh = verify_files(partition)
    config, autoexec = read(partition,'CONFIG.SYS'), read(partition,'AUTOEXEC.BAT')
    if b'COUNTRY=007' in config.upper() or b'KEYBRD2' in autoexec.upper():
        raise AssertionError('fresh install activated optional Russian support')
    # Mark an existing optional file as stale; upgrade must replace it.
    write(partition,'DOS/EGA866.CPI',b'stale optional font')
    results.append(run_guest(work/'upgrade',hdd,media/'disk1.img',media/'disk2.img'))
    upgraded = verify_files(partition)
    assert read(partition,'CONFIG.SYS') == config
    assert read(partition,'AUTOEXEC.BAT') == autoexec
    assert read(partition,'KEEP.TXT') == keep
    doc = read(partition,'DOS/RUSSIAN.TXT').decode('ascii').replace('\r\n','\n')
    def section(name):
        return doc.split('['+name+']\n',1)[1].split('[END]',1)[0].splitlines()
    country, *devices = section('CONFIG')
    write(partition,'CONFIG.SYS', (country+'\r\n').encode()+config+b'\r\n'+('\r\n'.join(devices)+'\r\nNUMLOCK=ON\r\n').encode())
    actions = ['@ECHO OFF','CTTY AUX']
    for line in section('AUTOEXEC'):
        actions += [line,'IF ERRORLEVEL 1 GOTO FAIL']
    for line in ['C:\\PROFILE.COM','C:\\DOS\\KEYB.COM','C:\\CPCHK.COM','C:\\P866.COM','C:\\KPROBE.COM']:
        actions += [line,'IF ERRORLEVEL 1 GOTO FAIL']
    actions += ['ECHO RU_INSTALLED_DONE','C:\\QEXIT.COM',':FAIL','ECHO RU_INSTALL_FAIL','C:\\QEXIT.COM']
    write(partition,'AUTOEXEC.BAT',('\r\n'.join(actions)+'\r\n').encode())
    for name in ('CPCHK.COM','P866.COM'):
        copy(partition,probes/name,name)
    (probes/'expected.bin').write_bytes(b''.join(struct.pack('<H',s['bios_ax']) for s in steps()))
    command('nasm','-f','bin',str(ROOT/'tests/ru_keyboard_probe.asm'),'-o',str(probes/'KPROBE.COM'),cwd=probes)
    copy(partition,probes/'KPROBE.COM','KPROBE.COM')
    command('nasm','-f','bin','-DHIGH=1',str(ROOT/'tests/ru_profile_probe.asm'),'-o',str(probes/'PROFILE.COM'))
    copy(partition,probes/'PROFILE.COM','PROFILE.COM')
    results.append(run_guest(work/'installed-recipe-high',hdd,keyboard=True))
    low_hdd=work/'low-hdd.img'
    shutil.copyfile(hdd,low_hdd)
    low_partition=f'{low_hdd}@@{OFFSET}'
    low_config=(country+'\r\nDOS=LOW\r\nFILES=30\r\nBUFFERS=20\r\n'+
                '\r\n'.join(devices)+'\r\nNUMLOCK=ON\r\n').encode()
    write(low_partition,'CONFIG.SYS',low_config)
    command('nasm','-f','bin','-DHIGH=0',str(ROOT/'tests/ru_profile_probe.asm'),'-o',str(probes/'PROFILE.COM'))
    copy(low_partition,probes/'PROFILE.COM','PROFILE.COM')
    results.append(run_guest(work/'installed-recipe-low',low_hdd,keyboard=True))
    report = {'selected_memory_core':os.environ['MEMORY_CORE_DIR'], 'fresh_hashes':fresh,'upgrade_hashes':upgraded,'startup_preserved_on_upgrade':True,
              'unrelated_file_preserved':True,'cases':results,'config':read(partition,'CONFIG.SYS').decode('ascii')}
    (work/'results.json').write_text(json.dumps(report,indent=2)+'\n')


if __name__ == '__main__':
    main()
