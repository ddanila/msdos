#!/usr/bin/env python3
"""Physical Baltic CP775 input on real IBM AT-84 and XT-83 BIOS keyboards."""
import argparse
import hashlib
import json
from pathlib import Path
import tempfile

from test_baltic_country_qemu import compile_probes, LANGUAGES
from test_baltic_keyboard_qemu import steps, tap, REFERENCE
from test_ru_legacy_keyboard_86box import run_case, selected_core, ROOT


def legacy_steps(language, kind):
    profiles = json.loads(REFERENCE.read_text())['profiles']
    source = steps(profiles[language], dos=kind == 'dos')
    result = []
    for original in source:
        if any(key in ('alt_r', 'ctrl_r', 'less') for key, down in original['keys']):
            continue
        item = dict(original)
        events = []
        for key, down in item['keys']:
            pad = {'up': 'kp_8', 'left': 'kp_4', 'delete': 'kp_decimal'}.get(key)
            if pad:
                if down:
                    events += tap('num_lock') + tap(pad) + tap('num_lock')
                # Legacy BIOS navigation has AL=00; literal CP775 E0 stays E0.
                item['bios_ax'] &= 0xff00
            else:
                events.append((key, down))
        item['keys'] = events
        result.append(item)

    manifest = json.loads((ROOT/'locales/baltic/manifest.json').read_text())
    letters = manifest['languages'][language]
    required = letters['required_lowercase'] + letters['required_uppercase']
    mapping = manifest['unicode_mapping']
    expected = {mapping.index(ord(char)) for char in required}
    actual = {item['bios_ax'] & 255 for item in result}
    assert expected <= actual, (language, 'unreachable national letters', expected - actual)
    # Filtering unavailable modifier variants must retain every dead-key pair.
    pairs = lambda items: {item['name'].split(' via ')[0] + ' + ' + item['name'].rsplit(' + ', 1)[1]
                           for item in items if item['name'].startswith('dead ')}
    assert pairs(source) == pairs(result), (language, 'lost dead-key pair')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emulator', type=Path, required=True,
                        help='VNC-enabled 86Box with loopback-only listeners')
    parser.add_argument('--roms', type=Path, required=True)
    parser.add_argument('--qt-platform')
    parser.add_argument('--machine', choices=('at84', 'xt83'), default='at84')
    parser.add_argument('--language', choices=tuple(LANGUAGES), action='append')
    parser.add_argument('--input', choices=('bios', 'dos'), action='append')
    args = parser.parse_args()
    args.suite = 'physical'
    core = selected_core()
    if not core:
        parser.error('MEMORY_CORE_DIR must select the production core')
    work = Path(tempfile.mkdtemp(prefix='baltic-legacy-keyboard-', dir=ROOT/'out'))
    print(f'Baltic legacy keyboard artifacts: {work}', flush=True)
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    resources = [ROOT/'src'/name for name in (
        'CMD/KEYB/KEYB.COM', 'DEV/KEYBOARD/KEYBRD2.SYS', 'DEV/COUNTRY/COUNTRY.SYS',
        'DEV/DISPLAY/EGA/EGA775.CPI', 'DEV/DISPLAY/DISPLAY.SYS',
        'CMD/NLSFUNC/NLSFUNC.EXE', 'CMD/MODE/MODE.COM')]
    report = {'status': 'running', 'machine': args.machine, 'suite': args.suite,
              'memory_profile': 'DOS=LOW', 'bios_api': 'INT 16h AH=00h',
              'dos_api': 'INT 21h AH=07h',
              'core_sha256': {name: hashlib.sha256(data).hexdigest() for name, data in core.items()},
              'emulator_sha256': digest(args.emulator),
              'resource_sha256': {str(path.relative_to(ROOT)): digest(path) for path in resources},
              'reference_sha256': digest(REFERENCE), 'cases': []}
    def save():
        (work/'results.json').write_text(json.dumps(report, indent=2) + '\n')
    save()
    try:
        for language in args.language or LANGUAGES:
            folder = work/language
            folder.mkdir()
            locale = {'page': 775, 'country': LANGUAGES[language],
                      'country_probe': f'P{LANGUAGES[language]}775.COM',
                      'selection': f'{language.upper()},775,KEYBRD2.SYS',
                      'compile_probes': compile_probes,
                      'steps': lambda kind: legacy_steps(language, kind)}
            for kind in args.input or ('bios', 'dos'):
                result = run_case(folder, args, core, kind, locale=locale)
                result['language'] = language
                result['log'] = str(Path(language)/result['log'])
                report['cases'].append(result)
                save()
    except Exception as error:
        report.update(status='failed', failure=str(error))
        save()
        raise
    report['status'] = 'selected-cases-passed'
    save()


if __name__ == '__main__':
    main()
