#!/usr/bin/env python3
"""Library selection, aliases, IDs, reloads and rejection on HIGH/LOW boots."""
import argparse
import json
import os
from pathlib import Path
import tempfile

from ru_profiles import verify_base
from test_baltic_keyboard_qemu import ROOT, tap
from test_ru_keyboard_qemu import run_case


def phases():
    result=[]
    def checks(code):
        if code in ('ET','EE'):
            items=[('Estonian lower',tap('bracket_right'),0x1be4),
                   ('Estonian upper',tap('shift','bracket_right'),0x1be5)]
        elif code == 'LV':
            items=[('Latvian lower',tap('alt_r','g'),0x2285),
                   ('Latvian upper',tap('shift','alt_r','g'),0x2295)]
        elif code == 'LT':
            items=[('Lithuanian lower',tap('q'),0x10d0),
                   ('Lithuanian upper',tap('shift','q'),0x10b5)]
        elif code == 'RU':
            items=[('Russian initial Latin',tap('q'),0x1071),
                   ('Russian selected',tap('alt','shift_r')+tap('q'),0x00a9)]
        else:
            items=[('German y',tap('y'),0x157a),('German z',tap('z'),0x2c79)]
        return [{'name':name,'keys':events,'bios_ax':word} for name,events,word in items]
    def add(code, command=None, reject=False):
        result.append({'command':command,'reject':reject,'status_code':code,
                       'status_page':866 if code=='RU' else 437 if code=='GR' else 775,
                       'cases':checks(code)})
    add('ET')
    for code, identifier in [('ET',454),('EE',454),('LV',0),('LT',221)]:
        add(code,f'KEYB {code},775,KEYBRD2.SYS')
        add(code,f'KEYB {code},775,KEYBRD2.SYS /ID:{identifier}')
        for command in [f'KEYB {code},866,KEYBRD2.SYS',
                        f'KEYB {code},775,KEYBRD2.SYS /ID:999',
                        f'KEYB {code},775,KEYBRD2.SYS /ID:{221 if code in ("ET","EE") else 454}',
                        f'KEYB {code},775,MISSING.SYS',
                        f'KEYB {code},775,BAD.SYS',
                        f'KEYB {code},775,SHORT.SYS']:
            add(code, command, reject=True)
    add('LT','KEYB ZZ,775,KEYBRD2.SYS',reject=True)
    add('RU','KEYB RU,866,KEYBRD2.SYS /ID:441')
    add('ET','KEYB ET,775,KEYBRD2.SYS /ID:454')
    add('GR','KEYB GR,437,KEYBOARD.SYS')
    add('LV','KEYB LV,775,KEYBRD2.SYS')
    add('LT','KEYB LT,775,KEYBRD2.SYS /ID:221')
    add('EE','KEYB EE,775,KEYBRD2.SYS')
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', choices=['high','low'], action='append')
    args=parser.parse_args()
    base=Path(os.environ.get('FLOPPY_IMAGE',ROOT/'out/floppy.img'))
    core=verify_base(base)
    work=Path(tempfile.mkdtemp(prefix='baltic-key-selection-',dir=ROOT/'out'))
    print(f'Baltic keyboard selection artifacts: {work}',flush=True)
    original=(ROOT/'src/DEV/KEYBOARD/KEYBRD2.SYS').read_bytes()
    (work/'BAD.SYS').write_bytes(bytes(1)+original[1:])
    (work/'SHORT.SYS').write_bytes(original[:20])
    report={'status':'running','core_sha256':core,'cases':[]}
    def save():
        (work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    save()
    try:
        for profile in args.profile or ['high','low']:
            report['cases'].append(run_case(work,base,profile,enhanced=True,
                keyb_selection='ET,775,KEYBRD2.SYS',country=372,
                memory_profile=profile,layout_phases=phases(),
                extra_files={name:work/name for name in ['BAD.SYS','SHORT.SYS']}))
            save()
    except Exception as error:
        report.update(status='failed',failure=str(error));save();raise
    report['status']='selected-cases-passed';save()


if __name__ == '__main__':
    main()
