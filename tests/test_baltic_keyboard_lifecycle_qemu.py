#!/usr/bin/env python3
"""Pending composition and language hotkeys with strict grouped BIOS/DOS reads."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile

from ru_profiles import verify_base
from test_baltic_keyboard_qemu import ROOT, REFERENCE, SCANS, tap
from test_ru_keyboard_qemu import run_case


def steps(language, profile, dos=False):
    cases = []
    def add(name, events, *words):
        cases.append({'name': name, 'keys': events, 'bios_words': list(words)})
    witness = {'et': (tap('bracket_right'),0x1be4),
               'lv': (tap('alt_r','g'),0x2285),
               'lt': (tap('q'),0x10d0)}[language]
    add('initial national', *witness)
    add('US hotkey', tap('ctrl','alt','f1')+tap('q'), 0x1071)
    add('national hotkey', tap('ctrl','alt','f2')+witness[0], witness[1])
    add('Alt Shift keeps national', tap('alt','shift')+witness[0], witness[1])
    modifiers = {'normal': (), 'shift': ('shift',), 'AltGr | Shift': ('alt_r',),
                 'Shift AltGr': ('shift','alt_r'), 'Ctrl': ('ctrl',), 'Alt': ('alt',)}
    triggers = {}
    for scan, cells in profile['keys'].items():
        for plane, cell in zip(profile['planes'], cells):
            if cell and cell['kind'] == 'dead':
                triggers.setdefault(str(cell['id']), tap(*modifiers[plane], SCANS[int(scan)]))
    for dead_id, trigger in triggers.items():
        dead = profile['dead_keys'][dead_id]
        literal = dead['literal']
        add('unmatched '+dead_id, trigger+tap('q'), literal, 0x1071)
        add('cleared after unmatched '+dead_id, tap('a'), 0x1e61)
        add('repeated '+dead_id, trigger+trigger+tap('spc'), literal, literal)
        add('cleared after repeated '+dead_id, tap('a'), 0x1e61)
        for key, value in [('tab',0x0f09), ('backspace',0x0e08), ('ret',0x1c0d),
                           ('esc',0x011b), ('f3',0x3d00),
                           ('left',0x4b00 if dos else 0x4be0)]:
            add('pending '+dead_id+' control '+key, trigger+tap(key), literal, value)
            add('cleared after control '+dead_id+' '+key, tap('a'), 0x1e61)
        base = next(int(byte) for byte in dead['pairs'] if 97 <= int(byte) <= 122)
        key = chr(base)
        scan = next(scan for scan, qcode in SCANS.items() if qcode == key)
        byte = dead['pairs'][str(base)]
        add('US selection cancels pending '+dead_id,
            trigger+tap('ctrl','alt','f1')+tap('q')+tap('ctrl','alt','f2')+tap(key),
            0x1071, scan*256+base)
        add('national reselection cancels pending '+dead_id,
            trigger+tap('ctrl','alt','f2')+tap(key), scan*256+base)
        add('modifier release preserves pending '+dead_id,
            trigger+tap('shift')+tap('ctrl')+tap(key), (0 if byte == 224 else scan)*256+byte)
        for other_id, other in triggers.items():
            if other_id != dead_id:
                add('change accent '+dead_id+' to '+other_id,
                    trigger+other+tap('spc'), literal, profile['dead_keys'][other_id]['literal'])
    return cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--language', choices=['et','lv','lt'], action='append')
    parser.add_argument('--profile', choices=['high','low'], action='append')
    parser.add_argument('--dos', action='store_true')
    args = parser.parse_args()
    base = Path(os.environ.get('FLOPPY_IMAGE', ROOT/'out/floppy.img'))
    core = verify_base(base)
    profiles = json.loads(REFERENCE.read_text())['profiles']
    work = Path(tempfile.mkdtemp(prefix='baltic-key-lifecycle-', dir=ROOT/'out'))
    print(f'Baltic keyboard lifecycle artifacts: {work}', flush=True)
    report = {'status':'running', 'core_sha256':core, 'cases':[],
              'resources': {name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in
                            ['src/CMD/KEYB/KEYB.COM','src/DEV/KEYBOARD/KEYBRD2.SYS']}}
    def save():
        (work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    save()
    try:
        for memory in args.profile or ['high','low']:
            for language in args.language or profiles:
                report['cases'].append(run_case(
                    work, base, memory+'-'+language, dos=args.dos, enhanced=True, grouped=True,
                    cases=steps(language, profiles[language], args.dos), memory_profile=memory,
                    keyb_selection=language.upper()+',775,KEYBRD2.SYS',
                    country={'et':372,'lv':371,'lt':370}[language]))
                save()
    except Exception as error:
        report.update(status='failed', failure=str(error)); save(); raise
    report['status']='selected-cases-passed'; save()


if __name__ == '__main__':
    main()
