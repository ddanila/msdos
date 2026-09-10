#!/usr/bin/env python3
"""Exercise country/font rejection and recovery through installed C:\\DOS paths."""
import argparse
import hashlib
import json
import sys
from pathlib import Path
import shutil
import subprocess
import struct
import tempfile

from test_baltic_country_qemu import ROOT, LANGUAGES, compile_probes
from test_baltic_country_resources_qemu import mutations as country_mutations
from test_baltic_font_resources_qemu import mutations as font_mutations
from test_baltic_keyboard_qemu import steps, REFERENCE
from test_ru_cpi import parse_cpi
from test_ru_install_qemu import OFFSET, copy, read, write, run_guest
sys.path.insert(0, str(ROOT/'tools'))
from memory_release import selected_core


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--installed-run', type=Path,
                        help='completed test_baltic_install_qemu.py run; hashes must match current inputs')
    parser.add_argument('--language', choices=list(LANGUAGES), action='append')
    parser.add_argument('--profile', choices=['high', 'low'], action='append')
    args = parser.parse_args()
    core = selected_core()
    assert core, 'MEMORY_CORE_DIR must select the production core'
    work = Path(tempfile.mkdtemp(prefix='baltic-installed-resources-', dir=ROOT/'out'))
    print('Baltic installed resource artifacts:', work, flush=True)
    installed = args.installed_run
    if installed is None:
        log = work/'installation.log'
        with log.open('wb') as stream:
            subprocess.run(['python3', str(ROOT/'tests/test_baltic_install_qemu.py')],
                           stdout=stream, stderr=subprocess.STDOUT, check=True)
        installed = Path(log.read_text().splitlines()[0].split(': ', 1)[1])
    installation = json.loads((installed/'results.json').read_text())
    assert installation['status'] == 'passed'
    assert installation['core_sha256'] == {name: sha(data) for name, data in core.items()}
    expected_files = dict(core)
    for source, name in json.loads((ROOT/'distribution/files.json').read_text())['compressed']:
        expected_files[name] = core[name] if name in core else (ROOT/source).read_bytes()
    expected_hashes = {name: sha(data) for name, data in expected_files.items()}
    assert installation['fresh_hashes'] == installation['upgrade_hashes'] == expected_hashes
    probes = work/'probes'; probes.mkdir(); compile_probes(probes)
    for name, flags in [('FONT', []), ('BADFONT', ['-DINACTIVE_DISPLAY'])]:
        subprocess.run(['nasm', '-f', 'bin', '-DPAGE=775', '-DHEIGHT=16', '-DDUMP_ONLY',
                        *flags, str(ROOT/'tests/ru_font_probe.asm'), '-o', str(probes/(name+'.COM'))], check=True)
    countries = country_mutations(expected_files['COUNTRY.SYS'])
    countries = {name: countries[name] for name in ['missing', 'short-header', 'bad-signature', 'data-info-short-0']}
    fonts = font_mutations(expected_files['EGA775.CPI'])
    expected_font = parse_cpi(expected_files['EGA775.CPI'], 775)[16]
    report = {'status': 'running', 'installation_run': str(installed.resolve()),
              'installation_report_sha256': sha((installed/'results.json').read_bytes()),
              'core_sha256': installation['core_sha256'], 'installed_sha256': expected_hashes, 'cases': []}
    def save():
        (work/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    save()
    try:
        for language in args.language or LANGUAGES:
            country = LANGUAGES[language]; other = 371 if country == 372 else 372
            checks = json.loads(json.dumps(steps(json.loads(REFERENCE.read_text())['profiles'][language])))
            (probes/'expected.bin').write_bytes(b''.join(struct.pack('<H', check['bios_ax']) for check in checks))
            subprocess.run(['nasm', '-f', 'bin', '-DENHANCED_INPUT',
                            f'-DEXPECTED_LANGUAGE={int.from_bytes(language.upper().encode(), "little")}',
                            '-DEXPECTED_PAGE=775', f'-DEXPECTED_ID={dict(et=454, lv=0, lt=221)[language]}',
                            str(ROOT/'tests/ru_keyboard_probe.asm'), '-o', str(probes/'KPROBE.COM')],
                           cwd=probes, check=True)
            for memory in args.profile or ['high', 'low']:
                name = language+'-'+memory
                original = next(c for c in installation['cases'] if c['name'] == name)
                assert original['steps'] == checks
                image = work/(name+'.img'); shutil.copyfile(installed/(name+'.img'), image)
                part = f'{image}@@{OFFSET}'
                def verify_files():
                    for filename, data in expected_files.items():
                        target = filename if filename in ('IO.SYS', 'MSDOS.SYS') else 'DOS/'+filename
                        assert read(part, target) == data, (name, target)
                verify_files()
                config = read(part, 'CONFIG.SYS')
                assert config == ('\r\n'.join(original['config_lines'])+'\r\n').encode('ascii')
                for probe in probes.glob('*.COM'):
                    copy(part, probe, probe.name)
                copy(part, probes/(memory.upper()+'.COM'), 'PROFILE.COM')
                for error in (1, 2):
                    target = probes/f'REJECT{error}.COM'
                    subprocess.run(['nasm', '-f', 'bin', f'-DTARGET={other}', f'-DERROR={error}',
                                    str(ROOT/'tests/baltic_country_resource_probe.asm'), '-o', str(target)], check=True)
                    copy(part, target, target.name)
                write(part, 'GOOD.SYS', expected_files['COUNTRY.SYS'])
                write(part, 'GOOD.CPI', expected_files['EGA775.CPI'])
                actions = ['@ECHO OFF', 'CTTY AUX', 'C:', 'CD \\']
                def accept(command):
                    actions.extend([command, 'IF ERRORLEVEL 1 GOTO FAIL'])
                def reject(command):
                    actions.extend([command, 'IF NOT ERRORLEVEL 1 GOTO FAIL'])
                for command in original['recipe']:
                    accept(command)
                accept('C:\\PROFILE.COM'); accept(f'C:\\P{country}775.COM')
                accept(f'C:\\R{country}.COM')
                variants = []
                for index, (mutation, data) in enumerate(countries.items()):
                    accept(f'C:\\Q{other}775.COM')
                    accept('DEL C:\\DOS\\COUNTRY.SYS')
                    if data is not None:
                        filename = f'C{index:02d}.SYS'; write(part, filename, data)
                        accept(f'COPY /Y C:\\{filename} C:\\DOS\\COUNTRY.SYS >NUL')
                    accept(f'C:\\REJECT{2 if data is None else 1}.COM')
                    accept(f'C:\\P{country}775.COM')
                    accept('COPY /Y C:\\GOOD.SYS C:\\DOS\\COUNTRY.SYS >NUL')
                    for command in [f'Q{other}775.COM', f'S{other}775.COM', f'P{other}775.COM',
                                    f'S{country}775.COM', f'P{country}775.COM']:
                        accept('C:\\'+command)
                    variants.append({'resource': 'COUNTRY.SYS', 'mutation': mutation,
                                     'sha256': None if data is None else sha(data), 'size': None if data is None else len(data)})
                snapshots = []
                def snapshot(filename, inactive=False):
                    if not inactive:
                        accept('C:\\CPCHK.COM')
                    accept(f'C:\\P{country}775.COM')
                    accept('C:\\BADFONT.COM' if inactive else 'C:\\FONT.COM')
                    accept(f'COPY /Y C:\\FONT.BIN C:\\{filename} >NUL')
                    snapshots.append(filename)
                snapshot('BEFORE.BIN')
                for index, (mutation, data) in enumerate(fonts.items()):
                    accept('DEL C:\\DOS\\EGA775.CPI')
                    if data is not None:
                        filename = f'F{index:02d}.CPI'; write(part, 'DOS/'+filename, data)
                        # Rename preserves an empty mutant exactly.
                        accept(f'REN C:\\DOS\\{filename} EGA775.CPI')
                    reject('C:\\DOS\\MODE.COM CON CP PREPARE=((775) C:\\DOS\\EGA775.CPI)')
                    if data is not None:
                        reject('C:\\DOS\\MODE.COM CON CP SELECT=775')
                    snapshot(f'F{index:02d}.BIN', inactive=data is not None)
                    accept('COPY /Y C:\\GOOD.CPI C:\\DOS\\EGA775.CPI >NUL')
                    accept('C:\\DOS\\MODE.COM CON CP PREPARE=((775) C:\\DOS\\EGA775.CPI)')
                    accept('C:\\DOS\\MODE.COM CON CP SELECT=775')
                    snapshot(f'R{index:02d}.BIN')
                    variants.append({'resource': 'EGA775.CPI', 'mutation': mutation,
                                     'sha256': None if data is None else sha(data), 'size': None if data is None else len(data)})
                accept('C:\\KPROBE.COM'); accept('C:\\PROFILE.COM')
                actions += ['ECHO RU_INSTALLED_DONE', 'C:\\QEXIT.COM', ':FAIL', 'ECHO RU_INSTALL_FAIL', 'C:\\QEXIT.COM']
                batch = ('\r\n'.join(actions)+'\r\n').encode('ascii'); write(part, 'AUTOEXEC.BAT', batch)
                result = run_guest(work/name, image, keyboard=True, cases_override=checks,
                                   expected_markers=[b'RU_KEY_PASS', b'KEYB_PROFILE_PASS', b'BALTIC_RESOURCE_REJECTED'])
                log = Path(result['log']).read_bytes()
                assert log.count(b'BALTIC_RESOURCE_REJECTED') == len(countries)
                assert log.count(b'RU_FONT_PASS') == len(snapshots)
                assert log.count(b'RU_COUNTRY_PASS') == 1 + 5*len(countries) + len(snapshots)
                assert log.count(b'RU_QUERY_PASS') == 2*len(countries)
                assert log.count(b'RU_REJECTION_PASS') == 1
                assert log.count(b'RU_CODEPAGE_PASS') == len(snapshots) - sum(data is not None for data in fonts.values())
                assert log.count(b'RU_KEY_PASS') == 1 and log.count(b'KEYB_PROFILE_PASS') == 1
                assert log.count(b'RU_HIGH_UMB_PASS' if memory == 'high' else b'RU_LOW_PASS') == 2
                captures = {}
                for filename in snapshots:
                    data = read(part, filename)
                    assert len(data) == 8192 and all(data[b*32:b*32+16] == expected_font[b] for b in range(256))
                    (work/name/filename).write_bytes(data); captures[filename] = sha(data)
                assert len(set(captures.values())) == 1
                verify_files()
                (work/name/'CONFIG.SYS.cfg').write_bytes(config)
                (work/name/'AUTOEXEC.BAT.cfg').write_bytes(batch)
                result.update(language=language, profile=memory, mutations=variants, snapshots=captures,
                              actions=actions, config=config.decode('ascii'), installed_files_restored=True)
                report['cases'].append(result); save()
    except Exception as error:
        report.update(status='failed', failure=str(error)); save(); raise
    report['status'] = 'passed'; save()


if __name__ == '__main__':
    main()
