#!/usr/bin/env python3
"""Require DOS completion and guest-requested success/failure exits on an IBM AT."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from memory_release import selected_core


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emulator', type=Path, required=True)
    parser.add_argument('--roms', type=Path, required=True)
    parser.add_argument('--qt-platform', help='For example offscreen, if the emulator provides that plugin')
    args = parser.parse_args()
    core = selected_core()
    if not core:
        parser.error('MEMORY_CORE_DIR must select the production core')
    work = Path(tempfile.mkdtemp(prefix='86box-exit-', dir=ROOT/'out'))
    print(f'86Box guest-exit artifacts: {work}', flush=True)
    subprocess.run(['nasm','-f','bin',str(ROOT/'tests/86box_exit.asm'),'-o',str(work/'BXEXIT.COM')],check=True)
    report = {'emulator':str(args.emulator.resolve()),'emulator_sha256':hashlib.sha256(args.emulator.read_bytes()).hexdigest(),
              'core_sha256':{name:hashlib.sha256(data).hexdigest() for name,data in core.items()},
              'status':'running','cases':[]}
    def save():
        (work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    save()
    try:
        for expected in (0,1):
            case = work/str(expected)
            case.mkdir()
            image = case/'test.img'
            subprocess.run(['bash','-c','source "$1/tests/86box_286_lib.sh"\nmake_86box_286_boot_image "$2" "$1"',
                            'bash',str(ROOT),str(image)],check=True,stdout=subprocess.DEVNULL)
            def put(name,data):
                subprocess.run(['mcopy','-o','-i',str(image),'-','::'+name],input=data,check=True)
            put('BXEXIT.COM',(work/'BXEXIT.COM').read_bytes())
            put('CONFIG.SYS',b'DOS=LOW\r\n')
            batch = f'@ECHO OFF\r\nCTTY AUX\r\nECHO RU_EXIT_EXPECT_{expected}\r\nBXEXIT.COM'
            batch += (' FAIL' if expected else '')+'\r\nECHO RU_EXIT_FAIL\r\n'
            put('AUTOEXEC.BAT',batch.encode())
            config = (ROOT/'tests/86box/ibmat-286.cfg').read_text()
            config = config.replace('[Other peripherals]','[Other peripherals]\nunittester_enabled = 1')
            (case/'86box.cfg').write_text(config)
            shutil.copyfile(ROOT/'tests/86box/global.cfg',case/'global.cfg')
            subprocess.run(['python3',str(ROOT/'tests/seed_86box_ibmat_nvram.py'),str(case/'nvr/ibm5170_111585.nvr')],check=True)
            env = dict(os.environ)
            if args.qt_platform:
                env['QT_QPA_PLATFORM'] = args.qt_platform
            with (case/'serial.log').open('wb') as log:
                result = subprocess.run([str(args.emulator.resolve()),'-N','-O',str(case/'global.cfg'),'-P',str(case),
                                         '-R',str(args.roms.resolve()),'-I','a:'+str(image)],stdin=subprocess.DEVNULL,
                                        stdout=log,stderr=subprocess.STDOUT,env=env,timeout=180)
            data = (case/'serial.log').read_bytes()
            assert result.returncode == expected, (result.returncode,case)
            assert f'RU_EXIT_EXPECT_{expected}'.encode() in data and b'RU_EXIT_FAIL' not in data,case
            report['cases'].append({'expected_status':expected,'exit_status':result.returncode,
                                    'log':str((case/'serial.log').relative_to(work)),
                                    'log_sha256':hashlib.sha256(data).hexdigest()})
            save()
            print(f'PASS: guest-requested exit {expected}',flush=True)
    except Exception as error:
        report['status']='failed'
        report['failure']=str(error)
        save()
        raise
    report['status']='passed'
    save()


if __name__ == '__main__':
    main()
