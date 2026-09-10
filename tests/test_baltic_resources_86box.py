#!/usr/bin/env python3
"""Baltic boot/runtime country and font recovery on the real IBM AT BIOS."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

from test_baltic_country_qemu import ROOT, COUNTRY, LANGUAGES, compile_probes
from test_baltic_country_resources_qemu import mutations as country_mutations
from test_baltic_font_resources_qemu import mutations as font_mutations
from test_ru_country_86box import run_case, selected_core
from test_ru_cpi import parse_cpi


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emulator', type=Path, required=True)
    parser.add_argument('--roms', type=Path, required=True)
    parser.add_argument('--qt-platform')
    parser.add_argument('--language', choices=list(LANGUAGES), action='append')
    parser.add_argument('--family', choices=['boot', 'country', 'font'], action='append')
    parser.add_argument('--height', choices=[8, 14, 16], type=int, action='append')
    parser.add_argument('--jobs', type=int, choices=[1, 2], default=1)
    parser.add_argument('--timeout', type=int, default=600)
    args = parser.parse_args()
    assert args.timeout > 0
    core = selected_core(); assert core, 'MEMORY_CORE_DIR must select a production core'
    work = Path(tempfile.mkdtemp(prefix='baltic-resources-286-', dir=ROOT/'out'))
    print('Baltic 286 resource artifacts:', work, flush=True)
    common = work/'probes'; common.mkdir(); compile_probes(common)
    for source, name in [('86box_exit.asm', 'BXEXIT.COM'), ('country_snapshot.asm', 'SNAP.COM')]:
        subprocess.run(['nasm', '-f', 'bin', str(ROOT/'tests'/source), '-o', str(common/name)], check=True)
    country_data = COUNTRY.read_bytes()
    font_data = (ROOT/'src/DEV/DISPLAY/EGA/EGA775.CPI').read_bytes()
    country_variants = country_mutations(country_data)
    font_variants = font_mutations(font_data)
    report = {'status': 'running', 'memory_profile': 'DOS=LOW',
              'core_sha256': {name: sha(data) for name, data in core.items()},
              'emulator_sha256': sha(args.emulator.read_bytes()),
              'resource_sha256': {name: sha((ROOT/name).read_bytes()) for name in [
                  'src/DEV/COUNTRY/COUNTRY.SYS', 'src/DEV/DISPLAY/EGA/EGA775.CPI',
                  'src/DEV/DISPLAY/DISPLAY.SYS', 'src/CMD/MODE/MODE.COM', 'src/CMD/NLSFUNC/NLSFUNC.EXE']},
              'cases': []}
    def save():
        (work/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    save()

    def execute(language, family, height=16, mutation=None, baseline=None):
        name = 'default' if language is None else language+'-'+family+('-'+mutation if mutation else '-'+str(height) if family == 'font' else '')
        inputs = work/(name+'-inputs'); inputs.mkdir()
        for probe in common.glob('*.COM'):
            shutil.copyfile(probe, inputs/probe.name)
        number = LANGUAGES.get(language, 1); other = 371 if number == 372 else 372
        actions = ['@ECHO OFF']
        def accept(command):
            actions.extend([command, 'IF ERRORLEVEL 1 GOTO FAIL'])
        def reject(command):
            actions.extend([command, 'IF NOT ERRORLEVEL 1 GOTO FAIL'])
        variants = []; snapshots = []
        def variant(resource, label, data, filename):
            if data is not None:
                (inputs/filename).write_bytes(data)
            variants.append({'resource': resource, 'mutation': label, 'filename': filename,
                             'size': None if data is None else len(data), 'sha256': None if data is None else sha(data)})
        config = '' if language is None else f'COUNTRY={number},775,COUNTRY.SYS\r\n'
        config += 'DEVICE=DISPLAY.SYS CON=(EGA,437,(1,3))\r\n'
        accept('LOW.COM')
        if family == 'boot':
            if language:
                data = country_variants[mutation]
                variant('COUNTRY.SYS', mutation, data, 'BROKEN.SYS')
                config = config.replace('775,COUNTRY.SYS', '775,BROKEN.SYS')
            accept('SNAP.COM')
            if language:
                accept('COPY /Y COUNTRY.SYS BROKEN.SYS >NUL')
                accept('NLSFUNC A:\\BROKEN.SYS')
                accept('MODE CON CP PREPARE=((775) EGA775.CPI)')
                accept(f'S{number}775.COM')
                accept('MODE CON CP SELECT=775')
                accept(f'P{number}775.COM')
        elif family == 'country':
            (inputs/'BAD.SYS').write_bytes(country_data)
            for error in [1, 2]:
                subprocess.run(['nasm', '-f', 'bin', f'-DTARGET={other}', f'-DERROR={error}',
                                str(ROOT/'tests/baltic_country_resource_probe.asm'),
                                '-o', str(inputs/f'REJECT{error}.COM')], check=True)
            accept('NLSFUNC A:\\BAD.SYS'); accept(f'P{number}775.COM')
            for index, label in enumerate(['missing', 'empty', 'bad-signature', 'data-6-truncated']):
                data = country_variants[label]; filename = f'C{index:02d}.SYS'
                variant('COUNTRY.SYS', label, data, filename)
                accept(f'Q{other}775.COM'); accept('DEL BAD.SYS')
                if data is not None:
                    accept(f'REN {filename} BAD.SYS')
                accept(f'REJECT{2 if data is None else 1}.COM'); accept(f'P{number}775.COM')
                accept('COPY /Y COUNTRY.SYS BAD.SYS >NUL')
                for command in [f'Q{other}775.COM', f'S{other}775.COM', f'P{other}775.COM', f'S{number}775.COM', f'P{number}775.COM']:
                    accept(command)
            accept(f'R{number}.COM'); accept(f'P{number}775.COM')
        else:
            for target, flags in [('FONT', ['-DDUMP_ONLY']), ('BADFONT', ['-DDUMP_ONLY', '-DINACTIVE_DISPLAY']), ('SETH', ['-DSETUP_ONLY'])]:
                subprocess.run(['nasm', '-f', 'bin', '-DPAGE=775', f'-DHEIGHT={height}', *flags,
                                str(ROOT/'tests/ru_font_probe.asm'), '-o', str(inputs/(target+'.COM'))], check=True)
            def snapshot(filename, inactive=False):
                if not inactive:
                    accept('CPCHK.COM')
                accept(f'P{number}775.COM'); accept('BADFONT.COM' if inactive else 'FONT.COM')
                accept(f'COPY /Y FONT.BIN {filename} >NUL'); snapshots.append(filename)
            accept('NLSFUNC'); accept('SETH.COM')
            accept('MODE CON CP PREPARE=((775) EGA775.CPI)'); accept('MODE CON CP SELECT=775')
            snapshot('BEFORE.BIN')
            for index, (label, data) in enumerate(font_variants.items()):
                filename = f'F{index:02d}.CPI'; variant('EGA775.CPI', label, data, filename)
                reject(f'MODE CON CP PREPARE=((775) {filename})')
                if data is not None:
                    reject('MODE CON CP SELECT=775')
                snapshot(f'F{index:02d}.BIN', inactive=data is not None)
                accept('MODE CON CP PREPARE=((775) EGA775.CPI)'); accept('MODE CON CP SELECT=775')
                snapshot(f'R{index:02d}.BIN')
            accept(f'R{number}.COM'); accept('CPCHK.COM')
        accept('LOW.COM')
        actions += ['ECHO BALTIC_286_RESOURCE_DONE', 'GOTO END', ':FAIL', 'ECHO BALTIC_286_RESOURCE_FAIL', 'BXEXIT.COM FAIL', ':END']
        (inputs/'CASE.BAT').write_bytes(('\r\n'.join(actions)+'\r\n').encode('ascii'))
        markers = [(b'BALTIC_286_RESOURCE_DONE', 1), (b'RU_LOW_PASS', 2),
                   (b'RU_COUNTRY_PASS', sum(a.startswith(('P3', 'S3')) for a in actions)),
                   (b'RU_QUERY_PASS', sum(a.startswith('Q3') for a in actions)),
                   (b'RU_REJECTION_PASS', sum(a.startswith('R3') for a in actions)),
                   (b'RU_CODEPAGE_PASS', actions.count('CPCHK.COM'))]
        if family == 'country':
            markers.append((b'BALTIC_RESOURCE_REJECTED', len(variants)))
        if family == 'font':
            markers.append((b'RU_FONT_PASS', len(snapshots)))
        if family == 'boot':
            markers.append((b'COUNTRY_SNAPSHOT_PASS', 1))
        files = [p.name for p in inputs.iterdir() if p.is_file()]
        case = run_case(inputs, args, core, name, config, ['CALL CASE.BAT'],
                        probe_files=files, font_page=775, expected_markers=markers, timeout=args.timeout)
        output = inputs/name; image = output/'test.img'
        def read(filename):
            return subprocess.check_output(['mtype', '-i', str(image), '::'+filename])
        case.update(language=language, family=family, height=height if family == 'font' else None,
                    mutations=variants, batch_actions=actions, private_artifacts=str(output.relative_to(work)))
        case['log'] = str((inputs/case['log']).relative_to(work))
        if family == 'boot':
            data = read('SNAP.BIN'); (output/'snapshot.bin').write_bytes(data)
            assert struct.unpack_from('<4H', data) == (1, 1, 437, 437)
            if baseline is not None:
                assert data == baseline, (name, 'fallback country tables differ')
            case['snapshot_sha256'] = sha(data)
            if language:
                assert read('BROKEN.SYS') == country_data
        elif family == 'font':
            expected = parse_cpi(font_data, 775)[height]; captures = {}
            for filename in snapshots:
                data = read(filename)
                assert len(data) == 8192 and all(data[b*32:b*32+height] == expected[b] for b in range(256)), (name, filename)
                (output/filename).write_bytes(data); captures[filename] = sha(data)
            assert len(set(captures.values())) == 1
            case['snapshots'] = captures
        else:
            assert read('BAD.SYS') == country_data
        assert read('COUNTRY.SYS') == country_data and read('EGA775.CPI') == font_data
        assert read('NLSFUNC.EXE') == (ROOT/'src/CMD/NLSFUNC/NLSFUNC.EXE').read_bytes()
        (output/'CASE.BAT.cfg').write_bytes(read('CASE.BAT'))
        (output/'CONFIG.SYS.cfg').write_bytes(read('CONFIG.SYS'))
        (output/'AUTOEXEC.BAT.cfg').write_bytes(read('AUTOEXEC.BAT'))
        return case

    try:
        families = args.family or ['boot', 'country', 'font']
        baseline = None
        if 'boot' in families:
            case = execute(None, 'boot'); report['cases'].append(case); save()
            baseline = (work/case['private_artifacts']/'snapshot.bin').read_bytes()
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futures = []
            for language in args.language or LANGUAGES:
                if 'boot' in families:
                    for mutation in ['missing', 'data-6-truncated']:
                        futures.append(pool.submit(execute, language, 'boot', mutation=mutation, baseline=baseline))
                if 'country' in families:
                    futures.append(pool.submit(execute, language, 'country'))
                if 'font' in families:
                    for height in args.height or [8, 14, 16]:
                        futures.append(pool.submit(execute, language, 'font', height=height))
            for future in as_completed(futures):
                report['cases'].append(future.result()); save()
    except Exception as error:
        report.update(status='failed', failure=str(error)); save(); raise
    report['status'] = 'passed'; save()


if __name__ == '__main__':
    main()
