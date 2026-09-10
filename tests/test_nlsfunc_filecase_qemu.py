#!/usr/bin/env python3
"""Preserve both shipped UCASE and FUCASE filename-uppercase signatures."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

from country_records import read_records
from test_country_records import EXPECTED, OBJECT_LENGTH, short_hash
from test_baltic_country_qemu import ROOT, COUNTRY, compile_probes, run_case
from ru_profiles import CONFIG, verify_base


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--nlsfunc', type=Path, default=ROOT/'src/CMD/NLSFUNC/NLSFUNC.EXE')
    args = parser.parse_args()
    base = Path(os.environ.get('FLOPPY_IMAGE', ROOT/'out/floppy.img'))
    core = verify_base(base)
    work = Path(tempfile.mkdtemp(prefix='nlsfunc-filecase-', dir=ROOT/'out'))
    print('NLSFUNC filename-case artifacts:', work, flush=True)
    compile_probes(work)
    data = COUNTRY.read_bytes(); records = read_records(data); actions = []
    for (country, page), hashes in EXPECTED.items():
        obj = records[country, page][4]
        assert short_hash(data[obj['offset']:obj['offset']+OBJECT_LENGTH[4]]) == hashes[3]
        folder = work/f'{country}-{page}'; folder.mkdir()
        (folder/'fileupper.bin').write_bytes(obj['payload'])
        name = f'L{country}{page}.COM'
        subprocess.run(['nasm', '-f', 'bin', f'-DCOUNTRY={country}', f'-DPAGE={page}',
                        str(ROOT/'tests/nlsfunc_filecase_query.asm'), '-o', str(work/name)], cwd=folder, check=True)
        actions.append(name)
    report = {'status': 'running', 'core_sha256': core,
              'nlsfunc_sha256': hashlib.sha256(args.nlsfunc.read_bytes()).hexdigest(), 'cases': []}
    def save():
        (work/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    save()
    try:
        for profile in CONFIG:
            case = run_case(work, base, profile, 'filecase', 372, 775,
                            ['P372775.COM', 'NLSFUNC', 'Q371775.COM', *actions, 'P372775.COM'],
                            nlsfunc=args.nlsfunc)
            raw = (work/case['serial_log']).read_bytes()
            assert raw.count(b'FILECASE_QUERY_PASS') == len(EXPECTED)
            report['cases'].append(case); save()
    except Exception as error:
        report.update(status='failed', failure=str(error)); save(); raise
    report['status'] = 'passed'; save()


if __name__ == '__main__':
    main()
