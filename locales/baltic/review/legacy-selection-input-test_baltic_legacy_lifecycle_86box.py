#!/usr/bin/env python3
"""Baltic layout reload, rejected resources and pending accents on legacy BIOS."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

from test_baltic_country_qemu import ROOT, compile_probes
from test_baltic_keyboard_selection_qemu import phases as selection_phases
from test_baltic_keyboard_pending_qemu import scenarios, phases as pending_phases
from test_baltic_keyboard_resources_qemu import mutations
from test_baltic_keyboard_lifecycle_qemu import steps as mode_steps
from test_baltic_keyboard_qemu import REFERENCE, tap
from test_ru_keyboard_qemu import encode_expected
from test_ru_legacy_keyboard_86box import run_case, selected_core


def legacy_cases(cases):
    result = []
    for original in cases:
        step = dict(original)
        step['bios_words'] = list(step.get('bios_words', [step.get('bios_ax')]))
        step.pop('bios_ax', None)
        keys = []
        for key, down in step['keys']:
            assert key not in ('ctrl_r', 'less'), key
            if key == 'left':
                if down:
                    keys.extend(tap('num_lock')+tap('kp_4')+tap('num_lock'))
                step['bios_words'] = [0x4b00 if word == 0x4be0 else word for word in step['bios_words']]
            elif key == 'alt_r':
                keys.extend([('ctrl', True), ('alt', True)] if down else [('alt', False), ('ctrl', False)])
            else:
                keys.append((key, down))
        step['keys'] = keys
        if 'ack_after' in step:
            # The final Caps-off (or German Shift) stroke stays after the barrier.
            step['ack_after'] = len(keys)-2
        result.append(step)
    return result


def plans(families, languages, selected_scenarios):
    library = (ROOT/'src/DEV/KEYBOARD/KEYBRD2.SYS').read_bytes()
    if 'modes' in families:
        profiles = json.loads(REFERENCE.read_text())['profiles']
        for language in ('et', 'lv', 'lt'):
            code = language.upper()
            yield 'modes-'+language, code, [dict(command=None, status_code=code, status_page=775,
                                                cases=mode_steps(language, profiles[language]))], {}
    if 'selection' in families:
        yield 'selection', 'ET', selection_phases(), {'BAD.SYS': b'X'+library[1:], 'SHORT.SYS': library[:20]}
    if 'resources' in families:
        for language in languages:
            checks = next(p['cases'] for p in selection_phases() if p['status_code'] == language)
            plan = [dict(command=None, status_code=language, status_page=775, cases=checks)]
            files = {}
            for index, (label, data) in enumerate(mutations(library, language).items()):
                filename = f'B{index:02d}.SYS'; files[filename] = data
                before, after = checks, checks
                if language in ('ET', 'EE', 'LV'):
                    source = 'ET' if language == 'EE' else language
                    scenario = next(s for s in scenarios() if s[1] == source)
                    pending = pending_phases(*scenario[1:])
                    before, after = pending[-2]['cases'], pending[-1]['cases']
                plan += [dict(command=f'KEYB {language},775,KEYBRD2.SYS', status_code=language, status_page=775, cases=before),
                         dict(command=f'KEYB {language},775,{filename}', reject=True, mutation=label,
                              status_code=language, status_page=775, cases=after),
                         dict(command=f'KEYB {language},775,KEYBRD2.SYS', status_code=language, status_page=775, cases=checks)]
            yield 'resources-'+language.lower(), language, plan, files
    if 'pending' in families:
        for name, source, trigger, literal, events, composed in scenarios():
            if selected_scenarios and name not in selected_scenarios:
                continue
            yield 'pending-'+name, 'ET', pending_phases(source, trigger, literal, events, composed), {}


def prepare(plan, files):
    def build(case, kind, put):
        for name, data in files.items():
            put(name, data)
        if any('KEYBOARD.SYS' in (phase.get('command') or '') for phase in plan):
            put('KEYBOARD.SYS', (ROOT/'src/DEV/KEYBOARD/KEYBOARD.SYS').read_bytes())
        steps, actions, programs = [], [], {}
        for index, phase in enumerate(plan):
            selected = legacy_cases(phase['cases'])
            expected = encode_expected(selected, grouped=True)
            if expected not in programs:
                name = f'L{len(programs):02d}.COM'
                (case/'expected.bin').write_bytes(expected)
                subprocess.run(['nasm', '-f', 'bin', '-DGROUPED_INPUT', '-DCAPACITY_PROOF',
                                '-DINDEX_FROM_ARG', *(['-DDOS_INPUT'] if kind == 'dos' else []),
                                str(ROOT/'tests/ru_keyboard_probe.asm'), '-o', str(case/name)], cwd=case, check=True)
                put(name, (case/name).read_bytes())
                programs[expected] = name
            name = programs[expected]
            actions.append((f'ECHO BALTIC_PHASE_{index:02d}', False))
            if phase.get('command'):
                actions.append((phase['command'], phase.get('reject', False)))
            actions.extend([('TYPECHK.COM', False), ('KEYB', False), (f'{name} {len(steps):04X}', False)])
            steps.extend(selected)
        return steps, actions, len(plan)
    return build


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emulator', type=Path, required=True)
    parser.add_argument('--roms', type=Path, required=True)
    parser.add_argument('--qt-platform')
    parser.add_argument('--machine', choices=['at84', 'xt83'], default='at84')
    parser.add_argument('--family', choices=['modes', 'selection', 'resources', 'pending'], action='append')
    parser.add_argument('--language', choices=['ET', 'EE', 'LV', 'LT'], action='append',
                        help='resource-family layout; selection and pending families retain their cross-layout checks')
    parser.add_argument('--scenario', choices=[s[0] for s in scenarios()], action='append')
    parser.add_argument('--input', choices=['bios', 'dos'], action='append')
    args = parser.parse_args(); args.suite = 'lifecycle'
    core = selected_core(); assert core, 'MEMORY_CORE_DIR must select the production core'
    work = Path(tempfile.mkdtemp(prefix='baltic-legacy-lifecycle-', dir=ROOT/'out'))
    print('Baltic legacy lifecycle artifacts:', work, flush=True)
    report = {'status': 'running', 'machine': args.machine, 'memory_profile': 'DOS=LOW',
              'core_sha256': {name: hashlib.sha256(data).hexdigest() for name, data in core.items()},
              'emulator_sha256': hashlib.sha256(args.emulator.read_bytes()).hexdigest(),
              'resource_sha256': {name:hashlib.sha256((ROOT/'src'/name).read_bytes()).hexdigest() for name in [
                  'CMD/KEYB/KEYB.COM', 'DEV/KEYBOARD/KEYBRD2.SYS', 'DEV/KEYBOARD/KEYBOARD.SYS',
                  'DEV/COUNTRY/COUNTRY.SYS', 'DEV/DISPLAY/DISPLAY.SYS', 'DEV/DISPLAY/EGA/EGA775.CPI',
                  'DEV/DISPLAY/EGA/EGA866.CPI',
                  'CMD/MODE/MODE.COM', 'CMD/NLSFUNC/NLSFUNC.EXE']}, 'cases': []}
    def save():
        (work/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    save()
    try:
        for name, initial, plan, files in plans(args.family or ['modes', 'selection', 'resources', 'pending'],
                                              args.language or ['ET', 'EE', 'LV', 'LT'], args.scenario):
            folder = work/name; folder.mkdir()
            country = {'ET':372, 'EE':372, 'LV':371, 'LT':370}[initial]
            locale = {'page':775, 'country':country, 'country_probe':f'P{country}775.COM',
                      'selection':initial+',775,KEYBRD2.SYS', 'compile_probes':compile_probes,
                      'steps':lambda kind: [{'name':'unused initial probe', 'keys':[], 'bios_ax':0}],
                      'extra_pages':sorted({phase['status_page'] for phase in plan} - {437,775}),
                      'compact_batch':True, 'lifecycle':prepare(plan, files)}
            for kind in args.input or ['bios', 'dos']:
                result = run_case(folder, args, core, kind, locale=locale)
                log = folder/result['log']; data = log.read_bytes()
                for index, phase in enumerate(plan):
                    section = data.split(f'\r\nBALTIC_PHASE_{index:02d}\r\n'.encode(), 1)[1]
                    if index+1 < len(plan):
                        section = section.split(f'\r\nBALTIC_PHASE_{index+1:02d}\r\n'.encode(), 1)[0]
                    assert ('Current keyboard code: '+phase['status_code']).encode() in section, (name, index, log)
                    assert ('code page: '+str(phase['status_page'])).encode() in section, (name, index, log)
                assert data.count(b'RU_KEY_ARMED') == sum('ack_after' in s for s in result['steps'])
                result.update(name=name, plan=plan, grouped_input=True, enhanced_bios_input=False,
                              prepared_pages=[775]+locale['extra_pages'],
                              mutations={filename:hashlib.sha256(value).hexdigest() for filename, value in files.items()})
                result['log'] = str(log.relative_to(work))
                report['cases'].append(result); save()
    except Exception as error:
        report.update(status='failed', failure=str(error)); save(); raise
    assert report['cases']
    report['status'] = 'passed'; save()


if __name__ == '__main__':
    main()
