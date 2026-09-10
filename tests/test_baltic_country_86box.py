#!/usr/bin/env python3
"""Baltic country APIs and code-page transitions on real IBM AT BIOS."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

from test_baltic_country_qemu import compile_probes, country_cases, COUNTRY
from test_ru_country_86box import ROOT, run_case, selected_core, read_records


def main():
    plans = country_cases()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emulator', type=Path, required=True)
    parser.add_argument('--roms', type=Path, required=True)
    parser.add_argument('--qt-platform')
    parser.add_argument('--jobs', type=int, choices=(1, 2), default=1)
    parser.add_argument('--case', choices=[p[0] for p in plans], action='append')
    args = parser.parse_args()
    core = selected_core()
    if not core:
        parser.error('MEMORY_CORE_DIR must select the production core')
    work = Path(tempfile.mkdtemp(prefix='baltic-country-286-', dir=ROOT/'out'))
    print(f'Baltic 286 country artifacts: {work}', flush=True)
    compile_probes(work)
    subprocess.run(['nasm', '-f', 'bin', str(ROOT/'tests/86box_exit.asm'),
                    '-o', str(work/'BXEXIT.COM')], check=True)
    probes = [path.name for path in work.glob('*.COM')]
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    resources = [COUNTRY, *(ROOT/'src'/name for name in (
        'DEV/DISPLAY/EGA/EGA775.CPI', 'DEV/DISPLAY/EGA/EGA.CPI',
        'DEV/DISPLAY/DISPLAY.SYS', 'CMD/MODE/MODE.COM', 'CMD/NLSFUNC/NLSFUNC.EXE'))]
    report = {'schema_version': 1, 'status': 'running', 'memory_profile': 'DOS=LOW',
              'core_sha256': {name: hashlib.sha256(data).hexdigest() for name, data in core.items()},
              'emulator_sha256': digest(args.emulator),
              'resource_sha256': {str(path.relative_to(ROOT)): digest(path) for path in resources},
              'cases': []}
    def save():
        (work/'results.json').write_text(json.dumps(report, indent=2) + '\n')
    save()
    try:
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futures = []
            for name, number, page, actions, corruption in plans:
                if args.case and name not in args.case:
                    continue
                country = COUNTRY
                stage = None
                if corruption:
                    kind, index, stage = (2, 0xe4-128, '03') if corruption == 'case' else (6, 0xe4, '08')
                    data = bytearray(COUNTRY.read_bytes())
                    data[read_records(data)[number, 775][kind]['offset'] + 10 + index] ^= 1
                    country = work/(name+'.sys')
                    country.write_bytes(data)
                markers = [(b'RU_COUNTRY_PASS', sum(a.startswith(('P3', 'S3')) for a in actions)),
                           (b'RU_QUERY_PASS', sum(a.startswith('Q3') for a in actions)),
                           (b'RU_REJECTION_PASS', sum(a.startswith('R3') for a in actions)),
                           (b'RU_CODEPAGE_PASS', actions.count('CPCHK.COM'))]
                futures.append(pool.submit(run_case, work, args, core, name,
                    f'COUNTRY={number},{page},COUNTRY.SYS\r\n', actions,
                    probe_files=probes, font_page=775, country_source=country,
                    expected_failure=stage, expected_markers=markers))
            for future in as_completed(futures):
                report['cases'].append(future.result())
                save()
    except Exception as error:
        report.update(status='failed', failure=str(error))
        save()
        raise
    report['status'] = 'selected-cases-passed'
    save()


if __name__ == '__main__':
    main()
