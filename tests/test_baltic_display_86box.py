#!/usr/bin/env python3
"""CP775 font-plane and rendered-pixel checks on real IBM AT BIOS."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
from pathlib import Path
import tempfile

from test_baltic_cpi import CPI, ROOT, check_fonts
from test_ru_cpi import parse_cpi
from test_ru_display_86box import run_case, selected_core


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emulator', type=Path, required=True)
    parser.add_argument('--roms', type=Path, required=True)
    parser.add_argument('--qt-platform')
    parser.add_argument('--jobs', type=int, choices=(1, 2), default=1)
    parser.add_argument('--case', choices=('775-8', '775-14', '775-16', '775-16-corrupt'), action='append')
    args = parser.parse_args()
    core = selected_core()
    if not core:
        parser.error('MEMORY_CORE_DIR must select the production core')
    fonts = parse_cpi(CPI.read_bytes(), 775)
    check_fonts(fonts)
    work = Path(tempfile.mkdtemp(prefix='baltic-display-286-', dir=ROOT/'out'))
    print(f'Baltic 286 display artifacts: {work}', flush=True)
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    resources = [CPI, *(ROOT/'src'/name for name in (
        'DEV/COUNTRY/COUNTRY.SYS', 'DEV/DISPLAY/DISPLAY.SYS',
        'CMD/MODE/MODE.COM', 'CMD/NLSFUNC/NLSFUNC.EXE'))]
    report = {'schema_version': 1, 'status': 'running',
              'scope': 'Shared CP775 font on real IBM AT BIOS, DOS LOW, with Estonian COUNTRY setup and rendered samples for all three languages. Every loaded glyph byte and grid pixel is checked. Separate gates qualify country transitions, keyboard input and installed workflows.',
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
            for height, corrupt in ((8, False), (14, False), (16, False), (16, True)):
                name = f'775-{height}' + ('-corrupt' if corrupt else '')
                if args.case and name not in args.case:
                    continue
                futures.append(pool.submit(run_case, work, args, core, 775, height,
                                           fonts[height], corrupt, cpi_source=CPI,
                                           corrupt_slot=0xe4, country=372, country_page=775))
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
