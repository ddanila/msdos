#!/usr/bin/env python3
"""Physical Baltic key/plane and composition checks from retained KEY facts.

This focused gate uses private floppy media and the existing BIOS/DOS probe.
Legacy keyboards, installation, reload failures and complete text workflows
have separate acceptance requirements in BALTIC.md.
"""
import argparse
import json
import hashlib
import os
from pathlib import Path
import tempfile
import struct

from baltic_keyboard_records import validate
from ru_profiles import verify_base
from test_ru_keyboard_qemu import run_case

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / 'locales/baltic/review/keyboard-expectations.json'
SCANS = {}
for first, names in [(2, '1 2 3 4 5 6 7 8 9 0 minus equal'),
                     (16, 'q w e r t y u i o p bracket_left bracket_right'),
                     (30, 'a s d f g h j k l semicolon apostrophe grave_accent'),
                     (43, 'backslash z x c v b n m comma dot slash'),
                     (57, 'spc'), (86, 'less')]:
    SCANS.update(enumerate(names.split(), first))


def tap(*keys):
    return [(key, True) for key in keys] + [(key, False) for key in reversed(keys)]


def steps(profile, dos=False):
    cases = []
    def add(name, events, byte, scan):
        cases.append({'name': name, 'keys': events, 'bios_ax': (0 if byte == 224 and not name.startswith('control/navigation') else scan) * 256 + byte})

    # Walk reference planes directly, without importing the table generator.
    modifiers = {'normal': [()], 'shift': [('shift',)],
                 'AltGr | Shift': [('alt_r',), ('ctrl', 'alt')],
                 'Shift AltGr': [('shift', 'alt_r'), ('shift', 'ctrl', 'alt')],
                 'Ctrl': [('ctrl',), ('ctrl_r',)], 'Alt': [('alt',)]}
    reachable = {}
    dead_triggers = {}
    for index, plane in enumerate(profile['planes']):
        for scan_text, cells in profile['keys'].items():
            item = cells[index]
            if not item:
                continue
            scan = int(scan_text)
            for mods in modifiers[plane]:
                events = tap(*mods, SCANS[scan])
                if item['kind'] == 'dead':
                    dead_triggers.setdefault(str(item['id']), []).append((plane, events))
                else:
                    add(f'{plane} {mods} scan {scan}', events, item['byte'], item['scan'])
                    reachable.setdefault(item['byte'], (events, item['scan']))
            if index < 2 and cells[1-index] and cells[1-index]['kind'] == 'character':
                expected = cells[1-index] if item['caps'] else item
                if expected['kind'] == 'character':
                    add(f'Caps {plane} scan {scan}',
                        tap('caps_lock') + tap(*modifiers[plane][0], SCANS[scan]) + tap('caps_lock'),
                        expected['byte'], expected['scan'])

    # BIOS letters omitted by the national table remain available for accents.
    for scan, key in SCANS.items():
        if len(key) == 1 and key.isalpha():
            row = profile['keys'].get(str(scan), [None, None])
            for index, char in enumerate((key, key.upper())):
                if row[index] is None:
                    reachable.setdefault(ord(char), (tap(*(['shift'] if index else []), key), scan))
    reachable[32] = (tap('spc'), 57)
    for dead_id, dead in profile['dead_keys'].items():
        for plane, trigger in dead_triggers[dead_id]:
            for base, result in dead['pairs'].items():
                events, scan = reachable[int(base)]
                add(f'dead {dead_id} via {plane} + {base}', trigger + events,
                    result, 0 if int(base) == 32 else scan)
    for key, value in [('esc', 0x011b), ('ret', 0x1c0d), ('backspace', 0x0e08),
                       ('tab', 0x0f09), ('spc', 0x3920), ('f1', 0x3b00),
                       ('up', 0x48e0), ('left', 0x4be0), ('delete', 0x53e0)]:
        add('control/navigation ' + key, tap(key), 0 if dos and value & 255 == 224 else value & 255, value >> 8)
    return cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--language', choices=['et', 'lv', 'lt'], action='append')
    parser.add_argument('--dos', action='store_true')
    parser.add_argument('--controls-only', action='store_true')
    parser.add_argument('--library', type=Path, default=ROOT/'src/DEV/KEYBOARD/KEYBRD2.SYS')
    args = parser.parse_args()
    base = Path(os.environ.get('FLOPPY_IMAGE', ROOT/'out/floppy.img'))
    core = verify_base(base)
    work = Path(tempfile.mkdtemp(prefix='baltic-keyboard-', dir=ROOT/'out'))
    print(f'Baltic keyboard artifacts: {work}', flush=True)
    profiles = json.loads(REFERENCE.read_text())['profiles']
    report = {'status': 'running', 'core_sha256': core, 'cases': [],
              'resource_sha256': {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                                  for path in (args.library.resolve(), ROOT/'src/CMD/KEYB/KEYB.COM', REFERENCE)},
              'bios_api': 'INT 16h AH=10h', 'dos_api': 'INT 21h AH=07h'}
    def save():
        (work/'results.json').write_text(json.dumps(report, indent=2) + '\n')
    save()
    try:
        for language in ([] if args.controls_only else args.language or profiles):
            report['cases'].append(run_case(
                work, base, language, dos=args.dos, enhanced=True, cases=steps(profiles[language], dos=args.dos),
                library_source=args.library.resolve(),
                keyb_selection=language.upper()+',775,KEYBRD2.SYS',
                country={'et': 372, 'lv': 371, 'lt': 370}[language]))
            save()
        if args.controls_only:
            original = args.library.read_bytes()
            sections = validate(original)
            for name, language, dos, events, expected, failure in [
                    ('wrong-tilde', 'et', False, tap('bracket_right'), 0x1be4, b'actual=1BE5'),
                    ('suppressed-ff', 'lv', False, tap('alt_r','1')+tap('a'), 0x02ff, b'actual=1E61'),
                    ('nonzero-e0-scan', 'et', True, tap('equal')+tap('shift','o'), 0x00e0, b'actual=0700')]:
                data = bytearray(original)
                _, pos, end = sections[language.upper()]
                pos += 4
                mutations = 0
                while pos < end-2:
                    size = struct.unpack_from('<H', data, pos)[0]
                    table = pos+7
                    length = struct.unpack_from('<H', data, table)[0]
                    if length:
                        for index in range(data[table+3]):
                            entry = table+4+3*index
                            scan, byte, output_scan = data[entry:entry+3]
                            if name == 'wrong-tilde' and scan == 27 and byte == 228:
                                data[entry+1] = 229
                                mutations += 1
                            elif name == 'suppressed-ff' and byte == 255:
                                data[table+2] &= ~16
                                mutations += 1
                            elif name == 'nonzero-e0-scan' and byte == 224:
                                assert output_scan == 0
                                data[entry+2] = scan
                                mutations += 1
                    pos += size
                assert mutations
                mutated = work/(name+'.sys')
                mutated.write_bytes(data)
                report['cases'].append(run_case(
                    work, base, name, dos=dos, enhanced=True,
                    cases=[{'name': name, 'keys': events, 'bios_ax': expected}],
                    library_source=mutated, keyb_selection=language.upper()+',775,KEYBRD2.SYS',
                    country={'et':372,'lv':371}[language], expected_failure=b'RU_KEY_FAIL '+failure))
                save()
    except Exception as error:
        report.update(status='failed', failure=str(error))
        save()
        raise
    report['status'] = 'selected-cases-passed'
    save()


if __name__ == '__main__':
    main()
