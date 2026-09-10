#!/usr/bin/env python3
"""Check existing nonempty DBCS external queries from Baltic HIGH/LOW boots."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

from test_baltic_country_qemu import ROOT, compile_probes, run_case
from ru_profiles import CONFIG, verify_base


def main():
    base = Path(os.environ.get('FLOPPY_IMAGE', ROOT / 'out/floppy.img'))
    core = verify_base(base)
    work = Path(tempfile.mkdtemp(prefix='nlsfunc-dbcs-query-', dir=ROOT / 'out'))
    print('NLSFUNC DBCS query artifacts:', work, flush=True)
    compile_probes(work)
    subprocess.run(['nasm', '-f', 'bin', str(ROOT / 'tests/nlsfunc_dbcs_query.asm'),
                    '-o', str(work / 'DBQUERY.COM')], check=True)
    report = {'status': 'running', 'core_sha256': core,
              'nlsfunc_sha256': hashlib.sha256((ROOT / 'src/CMD/NLSFUNC/NLSFUNC.EXE').read_bytes()).hexdigest(),
              'cases': []}
    def save():
        (work / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    save()
    try:
        for profile in CONFIG:
            case = run_case(work, base, profile, 'dbcs-query', 372, 775,
                            ['P372775.COM', 'NLSFUNC', 'DBQUERY.COM', 'P372775.COM'])
            output = (work / case['serial_log']).read_bytes()
            assert output.count(b'DBCS_QUERY_PASS') == 4, output
            report['cases'].append(case)
            save()
    except Exception as error:
        report.update(status='failed', failure=str(error))
        save()
        raise
    report['status'] = 'passed'
    save()


if __name__ == '__main__':
    main()
