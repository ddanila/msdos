#!/usr/bin/env python3
"""Install the Baltic pack and boot each shipped HIGH/LOW recipe from C:\\DOS."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import tempfile

from PIL import Image
from test_ru_install_qemu import command, copy, write, read, run_guest, prepare_install_disk, OFFSET, ROOT
from test_baltic_country_qemu import compile_probes, LANGUAGES
from test_baltic_keyboard_qemu import steps, REFERENCE
from test_ru_display_86box import verify_grid
from test_ru_cpi import parse_cpi
from memory_release import selected_core


def main():
    core = selected_core()
    if not core:
        raise SystemExit('MEMORY_CORE_DIR must select the production core')
    work = Path(tempfile.mkdtemp(prefix='baltic-install-', dir=ROOT/'out'))
    print(f'Baltic installation artifacts: {work}', flush=True)
    media = work/'media'
    command('python3', str(ROOT/'tools/build_distribution.py'), '--output', str(media))
    hdd, partition = prepare_install_disk(work)
    probes = work/'probes'; probes.mkdir(); compile_probes(probes)
    copy(partition, probes/'QEXIT.COM', 'QEXIT.COM')
    sentinel = b'preserve unrelated Baltic installation file\r\n'
    write(partition, 'KEEP.TXT', sentinel)
    batch = b'@ECHO OFF\r\nCTTY AUX\r\nSETUP C:\\DOS\r\nIF ERRORLEVEL 1 GOTO FAIL\r\nECHO RU_INSTALLED_DONE\r\nC:\\QEXIT.COM\r\n:FAIL\r\nECHO RU_INSTALL_FAIL\r\nC:\\QEXIT.COM\r\n'
    for name in ('disk1.img', 'disk2.img'):
        write(media/name, 'AUTOEXEC.BAT', batch)
    inventory = json.loads((ROOT/'distribution/files.json').read_text())
    def verify(part):
        hashes = {}
        for source, name in inventory['compressed']:
            data = read(part, 'DOS/'+name)
            assert data == (core[name] if name in core else (ROOT/source).read_bytes()), name
            hashes[name] = hashlib.sha256(data).hexdigest()
        for name, data in core.items():
            target = name if name in ('IO.SYS', 'MSDOS.SYS') else 'DOS/'+name
            assert read(part, target) == data, name
            hashes[name] = hashlib.sha256(data).hexdigest()
        return hashes
    report = {'status': 'running', 'cases': [], 'core_sha256':
              {name: hashlib.sha256(data).hexdigest() for name, data in core.items()}}
    def save():
        (work/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    save()
    try:
        report['cases'].append(run_guest(work/'fresh', hdd, media/'disk1.img', media/'disk2.img'))
        report['fresh_hashes'] = verify(partition)
        config, autoexec = read(partition, 'CONFIG.SYS'), read(partition, 'AUTOEXEC.BAT')
        assert b'COUNTRY=' not in config.upper() and b'KEYBRD2' not in autoexec.upper()
        report['english_default_config'] = config.decode('ascii')
        report['english_default_autoexec'] = autoexec.decode('ascii')
        # Every newly shipped Baltic payload and the shared library is stale.
        for source, name in inventory['compressed']:
            if name in ('EGA775.CPI','BALTIC.TXT','BAKEYS.TXT','BAKBDGPL.TXT','BAMAPLIC.TXT','BACLDLIC.TXT','KEYBRD2.SYS'):
                write(partition, 'DOS/'+name, b'stale optional payload')
        report['cases'].append(run_guest(work/'upgrade', hdd, media/'disk1.img', media/'disk2.img'))
        report['upgrade_hashes'] = verify(partition)
        assert read(partition, 'CONFIG.SYS') == config and read(partition, 'AUTOEXEC.BAT') == autoexec
        assert read(partition, 'KEEP.TXT') == sentinel
        save()
        doc = read(partition, 'DOS/BALTIC.TXT').decode('ascii').replace('\r\n', '\n')
        def section(name):
            return doc.split('['+name+']\n', 1)[1].split('[END]', 1)[0].splitlines()
        profiles = json.loads(REFERENCE.read_text())['profiles']
        for language, country in LANGUAGES.items():
            for memory in ('high', 'low'):
                name = language+'-'+memory
                image = work/(name+'.img'); shutil.copyfile(hdd, image)
                part = f'{image}@@{OFFSET}'
                country_line, *devices = section('CONFIG-'+language.upper())
                config_lines = [country_line] + section('MEMORY-'+memory.upper()) + devices + ['NUMLOCK=ON']
                write(part, 'CONFIG.SYS', ('\r\n'.join(config_lines)+'\r\n').encode('ascii'))
                cases = steps(profiles[language])
                (probes/'expected.bin').write_bytes(b''.join(struct.pack('<H', s['bios_ax']) for s in cases))
                command('nasm','-f','bin','-DENHANCED_INPUT',f'-DEXPECTED_LANGUAGE={int.from_bytes(language.upper().encode(), "little")}', '-DEXPECTED_PAGE=775', f'-DEXPECTED_ID={dict(et=454,lv=0,lt=221)[language]}',str(ROOT/'tests/ru_keyboard_probe.asm'),'-o',str(probes/'KPROBE.COM'),cwd=probes)
                command('nasm','-f','bin','-DPAGE=775','-DHEIGHT=16','-DHIDE_CURSOR',str(ROOT/'tests/ru_font_probe.asm'),'-o',str(probes/'FONT.COM'))
                probe = f'P{country}775.COM'
                for filename in ('KPROBE.COM','CPCHK.COM',probe,'FONT.COM'):
                    copy(part, probes/filename, filename)
                copy(part, probes/(memory.upper()+'.COM'), 'PROFILE.COM')
                actions = ['@ECHO OFF','CTTY AUX']
                for action in section('AUTOEXEC-'+language.upper()) + ['C:\\PROFILE.COM','C:\\DOS\\KEYB.COM','C:\\CPCHK.COM','C:\\'+probe,'C:\\KPROBE.COM','C:\\FONT.COM','C:\\PROFILE.COM']:
                    actions += [action,'IF ERRORLEVEL 1 GOTO FAIL']
                actions += ['ECHO RU_INSTALLED_DONE','C:\\QEXIT.COM',':FAIL','ECHO RU_INSTALL_FAIL','C:\\QEXIT.COM']
                write(part, 'AUTOEXEC.BAT', ('\r\n'.join(actions)+'\r\n').encode('ascii'))
                markers = [b'RU_KEY_PASS',b'KEYB_PROFILE_PASS',b'RU_COUNTRY_PASS',b'RU_CODEPAGE_PASS',
                           ('Current keyboard code: '+language.upper()).encode()]
                if language != 'lv':
                    markers.append(('Current keyboard ID: '+str({'et':454,'lt':221}[language])).encode())
                result = run_guest(work/name, image, keyboard=True, cases_override=cases,
                                   expected_markers=markers, capture_font=True)
                log = Path(result['log']).read_bytes()
                if language == 'lv':
                    assert b'Current keyboard ID:' not in log
                assert log.count(b'RU_HIGH_UMB_PASS' if memory=='high' else b'RU_LOW_PASS') == 2
                plane = read(part, 'FONT.BIN'); assert len(plane) == 8192
                expected = parse_cpi(read(part, 'DOS/EGA775.CPI'), 775)[16]
                assert all(plane[b*32:b*32+16] == expected[b] for b in range(256))
                # QEMU duplicates column nine for B0-DF; the 86Box check uses C0-DF.
                screen = Image.open(work/name/'font.ppm'); verify_grid(screen, plane, 16, line_graphics_start=0xb0)
                screen.save(work/name/'screen.png'); (work/name/'font-plane.bin').write_bytes(plane)
                result.update(language=language, memory_profile=memory, config_lines=config_lines,
                              recipe=section('AUTOEXEC-'+language.upper()), steps=cases,
                              font_plane_sha256=hashlib.sha256(plane).hexdigest(),
                              screen_sha256=hashlib.sha256((work/name/'screen.png').read_bytes()).hexdigest(),
                              installed_hashes=verify(part))
                report['cases'].append(result); save()
    except Exception as error:
        report.update(status='failed', failure=str(error)); save(); raise
    report['status'] = 'passed'; save()


if __name__ == '__main__':
    main()
