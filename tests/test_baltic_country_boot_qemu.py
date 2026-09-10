#!/usr/bin/env python3
"""Compare failed COUNTRY boot state to a clean default boot, then recover."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

from ru_profiles import CONFIG, verify_base, require_profile
from test_baltic_country_qemu import ROOT, COUNTRY, LANGUAGES, compile_probes
from test_baltic_country_resources_qemu import mutations


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--language', choices=list(LANGUAGES), action='append')
    parser.add_argument('--profile', choices=list(CONFIG), action='append')
    parser.add_argument('--case', choices=list(mutations(COUNTRY.read_bytes())), action='append')
    args = parser.parse_args()
    base = Path(os.environ.get('FLOPPY_IMAGE', ROOT/'out/floppy.img'))
    core = verify_base(base)
    work = Path(tempfile.mkdtemp(prefix='baltic-country-boot-', dir=ROOT/'out'))
    print('Baltic country boot artifacts:', work, flush=True)
    compile_probes(work)
    subprocess.run(['nasm', '-f', 'bin', str(ROOT/'tests/country_snapshot.asm'),
                    '-o', str(work/'SNAP.COM')], check=True)
    variants = mutations(COUNTRY.read_bytes())
    names = args.case or [name for name in variants if not name.startswith('valid-')]
    report = {'status': 'running', 'core_sha256': core, 'cases': []}
    def save():
        (work/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    save()
    def boot(memory, name, language=None, mutation=None):
        folder = work/memory/name; folder.mkdir(parents=True)
        image = folder/'boot.img'; shutil.copyfile(base, image)
        def put(filename, data):
            subprocess.run(['mcopy', '-o', '-i', str(image), '-', '::'+filename], input=data, check=True)
        for probe in work.glob('*.COM'):
            put(probe.name, probe.read_bytes())
        for source, target in [(COUNTRY, 'GOOD.SYS'),
                               (ROOT/'src/CMD/NLSFUNC/NLSFUNC.EXE', 'NLSFUNC.EXE'),
                               (ROOT/'src/CMD/MODE/MODE.COM', 'MODE.COM'),
                               (ROOT/'src/DEV/DISPLAY/DISPLAY.SYS', 'DISPLAY.SYS'),
                               (ROOT/'src/DEV/DISPLAY/EGA/EGA775.CPI', 'EGA775.CPI')]:
            put(target, source.read_bytes())
        config = CONFIG[memory]+'DEVICE=DISPLAY.SYS CON=(EGA,437,(1,3))\r\n'
        actions = [memory.upper()+'.COM', 'SNAP.COM']
        if language:
            number = LANGUAGES[language]
            config = f'COUNTRY={number},775,BAD.SYS\r\n'+config
            if mutation is not None:
                put('BAD.SYS', mutation)
            actions += ['COPY /Y GOOD.SYS BAD.SYS >NUL', 'NLSFUNC A:\\BAD.SYS',
                        'MODE CON CP PREPARE=((775) EGA775.CPI)', f'S{number}775.COM',
                        'MODE CON CP SELECT=775', f'P{number}775.COM', memory.upper()+'.COM']
        batch = ['@ECHO OFF', 'CTTY AUX']
        for action in actions:
            batch += [action, 'IF ERRORLEVEL 1 GOTO FAIL']
        batch += ['ECHO BALTIC_BOOT_DONE', 'QEXIT.COM', ':FAIL', 'ECHO BALTIC_BOOT_FAIL', 'QEXIT.COM']
        put('CONFIG.SYS', config.encode('ascii'))
        put('AUTOEXEC.BAT', ('\r\n'.join(batch)+'\r\n').encode('ascii'))
        log = folder/'serial.log'
        with log.open('wb') as stream:
            result = subprocess.run(['qemu-system-i386', '-display', 'none', '-m', '8',
                '-drive', f'if=floppy,format=raw,file={image}', '-boot', 'a', '-serial', 'stdio',
                '-monitor', 'none', '-no-reboot', '-device', 'isa-debug-exit,iobase=0xf4,iosize=0x04'],
                stdin=subprocess.DEVNULL, stdout=stream, stderr=subprocess.STDOUT, timeout=45)
        raw = log.read_bytes(); require_profile(raw, memory)
        snapshot = None
        if b'COUNTRY_SNAPSHOT_PASS' in raw:
            snapshot = subprocess.check_output(['mtype', '-i', str(image), '::SNAP.BIN'])
            (folder/'snapshot.bin').write_bytes(snapshot)
        assert result.returncode == 33 and b'BALTIC_BOOT_DONE' in raw and b'FAIL' not in raw, (folder, raw)
        assert raw.count(b'COUNTRY_SNAPSHOT_PASS') == 1
        assert raw.count(b'RU_COUNTRY_PASS') == (2 if language else 0)
        assert snapshot is not None
        case = {'name': name, 'profile': memory, 'language': language, 'config': config, 'actions': actions,
                'emulator_exit': result.returncode, 'log': str(log.relative_to(work)),
                'log_sha256': hashlib.sha256(raw).hexdigest(), 'snapshot_sha256': hashlib.sha256(snapshot).hexdigest(),
                'mutant_sha256': None if mutation is None else hashlib.sha256(mutation).hexdigest()}
        report['cases'].append(case); save()
        return snapshot
    try:
        for memory in args.profile or CONFIG:
            baseline = boot(memory, 'default')
            assert struct.unpack_from('<4H', baseline) == (1, 1, 437, 437)
            for language in args.language or LANGUAGES:
                for name in names:
                    snapshot = boot(memory, language+'-'+name, language, variants[name])
                    assert snapshot == baseline, (language, memory, name, 'fallback tables differ from default boot')
                    print('PASS:', memory, language, name, flush=True)
    except Exception as error:
        report.update(status='failed', failure=str(error)); save(); raise
    report['status'] = 'passed'; save()


if __name__ == '__main__':
    main()
