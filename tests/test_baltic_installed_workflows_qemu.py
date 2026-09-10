#!/usr/bin/env python3
"""Physical text editing and national filenames through installed C:\\DOS paths."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

from test_baltic_country_qemu import ROOT, LANGUAGES
from test_baltic_text_qemu import language_profile as text_profile
from test_baltic_files_qemu import language_profile as file_profile
from test_ru_text_qemu import run_case as text_case
from test_ru_files_qemu import FAT, run_case as file_case
from test_ru_install_qemu import OFFSET, read
from memory_release import selected_core


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--installed-run', type=Path,
                        help='completed Baltic installation run with matching current payload hashes')
    parser.add_argument('--language', choices=list(LANGUAGES), action='append')
    parser.add_argument('--profile', choices=['high', 'low'], action='append')
    parser.add_argument('--family', choices=['text', 'files'], action='append')
    args = parser.parse_args()
    args.emulator = None
    args.qt_platform = None
    core = selected_core()
    assert core, 'MEMORY_CORE_DIR must select the production core'
    work = Path(tempfile.mkdtemp(prefix='baltic-installed-workflows-', dir=ROOT/'out'))
    print('Baltic installed workflow artifacts:', work, flush=True)
    installed = args.installed_run
    if installed is None:
        log = work/'installation.log'
        with log.open('wb') as stream:
            subprocess.run(['python3', str(ROOT/'tests/test_baltic_install_qemu.py')],
                           stdout=stream, stderr=subprocess.STDOUT, check=True)
        installed = Path(log.read_text().splitlines()[0].split(': ', 1)[1])
    installation = json.loads((installed/'results.json').read_text())
    core_hashes = {name: sha(data) for name, data in core.items()}
    assert installation['status'] == 'passed' and installation['core_sha256'] == core_hashes
    expected_files = dict(core)
    for source, name in json.loads((ROOT/'distribution/files.json').read_text())['compressed']:
        expected_files[name] = core[name] if name in core else (ROOT/source).read_bytes()
    expected_hashes = {name: sha(data) for name, data in expected_files.items()}
    assert installation['fresh_hashes'] == installation['upgrade_hashes'] == expected_hashes

    def verify_files(image):
        part = f'{image}@@{OFFSET}'
        for name, data in expected_files.items():
            target = name if name in ('IO.SYS', 'MSDOS.SYS') else 'DOS/'+name
            assert read(part, target) == data, (image, target)
        # The unchanged recipe uses the default root shell at boot.
        assert read(part, 'COMMAND.COM') == core['COMMAND.COM'], image
        # Interactive commands must resolve through PATH to the installed utilities.
        entries = FAT(image, OFFSET).entries()
        for stem in ('EDLIN', 'FIND'):
            for extension in ('COM', 'EXE', 'BAT'):
                assert (stem.ljust(8)+extension).encode('ascii') not in entries, (image, stem, extension)

    report = {'status': 'running', 'backend': 'qemu-ide', 'partition_offset': OFFSET,
              'installation_run': str(installed.resolve()),
              'installation_report_sha256': sha((installed/'results.json').read_bytes()),
              'core_sha256': core_hashes, 'installed_sha256': expected_hashes, 'cases': []}
    def save():
        (work/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    save()
    try:
        for language in args.language or LANGUAGES:
            for profile in args.profile or ['high', 'low']:
                name = language+'-'+profile
                original = next(c for c in installation['cases'] if c['name'] == name)
                image = installed/(name+'.img'); verify_files(image)
                part = f'{image}@@{OFFSET}'
                config = read(part, 'CONFIG.SYS')
                assert config == ('\r\n'.join(original['config_lines'])+'\r\n').encode('ascii')
                doc = read(part, 'DOS/BALTIC.TXT').decode('ascii').replace('\r\n', '\n')
                recipe = doc.split('[AUTOEXEC-'+language.upper()+']\n', 1)[1].split('[END]', 1)[0].splitlines()
                assert recipe == original['recipe']
                baseline_hash = sha(image.read_bytes())
                context = {'image': image, 'offset': OFFSET, 'config': config, 'recipe': recipe}
                for family in args.family or ['text', 'files']:
                    folder = work/(family+'-'+language); folder.mkdir(exist_ok=True)
                    run_case, locale = (text_case, text_profile(language)) if family == 'text' else (file_case, file_profile(language))
                    result = run_case(folder, None, profile, args, core_hashes, locale, installed=context)
                    output = folder/profile; final_image = output/'test.img'
                    verify_files(final_image)
                    final_part = f'{final_image}@@{OFFSET}'
                    assert read(final_part, 'CONFIG.SYS') == config
                    for filename in ['CONFIG.SYS', 'AUTOEXEC.BAT'] + (['NEXT.BAT'] if family == 'files' else []):
                        (output/(filename+'.cfg')).write_bytes(read(final_part, filename))
                    result.update(language=language, family=family, installed_files_preserved=True,
                                  baseline_image_sha256=baseline_hash,
                                  private_artifacts=str(output.relative_to(work)))
                    if family == 'text':
                        result['national_sequences'] = locale['national_sequences']
                    report['cases'].append(result); save()
                assert sha(image.read_bytes()) == baseline_hash, 'workflow modified its installation baseline'
    except Exception as error:
        report.update(status='failed', failure=str(error)); save(); raise
    report['status'] = 'passed'; save()


if __name__ == '__main__':
    main()
