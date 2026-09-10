#!/usr/bin/env python3
"""Reject malformed Baltic library directories and sections without losing input."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import tempfile

from baltic_keyboard_records import validate
from ru_profiles import verify_base
from test_baltic_keyboard_qemu import ROOT
from test_baltic_keyboard_selection_qemu import phases as selection_phases
from test_baltic_keyboard_pending_qemu import scenarios, phases as pending_phases
from test_ru_keyboard_qemu import run_case


def mutations(original, language):
    logic, page, end = validate(original)['ET' if language == 'EE' else language]
    common = logic + struct.unpack_from('<H', original, logic)[0]
    index = ['RU', 'ET', 'EE', 'LV', 'LT'].index(language)
    entry = 88 + index * 16
    def replace(offset, value, fmt='<I'):
        data = bytearray(original)
        struct.pack_into(fmt, data, offset, value)
        return bytes(data)
    return {
        'directory-pointer': replace(28 + index * 6 + 2, len(original) + 256),
        'logic-pointer': replace(entry + 4, len(original) + 256),
        'page-pointer': replace(entry + 12, len(original) + 256),
        'logic-header': original[:logic + 3],
        'logic-body': original[:common - 1],
        'common-header': original[:common + 3],
        'common-body': original[:page - 1],
        'page-header': original[:page + 3],
        'page-body': original[:end - 1],
        'logic-underflow': replace(logic, 3, '<H'),
        'logic-overflow': replace(logic, 65535, '<H'),
        'common-underflow': replace(common, 3, '<H'),
        'common-overflow': replace(common, 65535, '<H'),
        'common-state-underflow': replace(common + 4, 6, '<H'),
        'common-state-overflow': replace(common + 4, 65535, '<H'),
        'page-underflow': replace(page, 3, '<H'),
        'page-overflow': replace(page, 65535, '<H'),
        'page-state-underflow': replace(page + 4, 6, '<H'),
        'page-state-overflow': replace(page + 4, 65535, '<H'),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--language', choices=['ET', 'EE', 'LV', 'LT'], action='append')
    parser.add_argument('--profile', choices=['high', 'low'], action='append')
    parser.add_argument('--case', action='append')
    parser.add_argument('--dos', action='store_true')
    args = parser.parse_args()
    base = Path(os.environ.get('FLOPPY_IMAGE', ROOT/'out/floppy.img'))
    core = verify_base(base)
    work = Path(tempfile.mkdtemp(prefix='baltic-key-resources-', dir=ROOT/'out'))
    print(f'Baltic keyboard resource artifacts: {work}', flush=True)
    original = (ROOT/'src/DEV/KEYBOARD/KEYBRD2.SYS').read_bytes()
    report = {'status': 'running', 'core_sha256': core, 'cases': []}
    def save():
        (work/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    save()
    try:
        for language in args.language or ['ET', 'EE', 'LV', 'LT']:
            checks = next(p['cases'] for p in selection_phases() if p['status_code'] == language)
            checks = [dict(name=c['name'], keys=c['keys'], bios_words=[c['bios_ax']]) for c in checks]
            plan = [dict(command=None, status_code=language, status_page=775, cases=checks)]
            files, variants = {}, []
            for index, (mutation, data) in enumerate(mutations(original, language).items()):
                if args.case and mutation not in args.case:
                    continue
                filename = f'BAD{index:02d}.SYS'
                bad = work/(language+'-'+mutation+'.sys'); bad.write_bytes(data)
                files[filename] = bad
                before, after = checks, checks
                if language in ('ET', 'EE', 'LV'):
                    source = 'ET' if language == 'EE' else language
                    scenario = next(s for s in scenarios() if s[1] == source)
                    pending = pending_phases(*scenario[1:])
                    before, after = pending[-2]['cases'], pending[-1]['cases']
                plan += [dict(command=f'KEYB {language},775,KEYBRD2.SYS',
                              status_code=language, status_page=775, cases=before),
                         dict(command=f'KEYB {language},775,{filename}', reject=True,
                              status_code=language, status_page=775, cases=after),
                         dict(command=f'KEYB {language},775,KEYBRD2.SYS',
                              status_code=language, status_page=775, cases=checks)]
                variants.append(dict(name=mutation, filename=filename,
                                     sha256=hashlib.sha256(data).hexdigest(), size=len(data)))
            assert variants, 'no mutations selected'
            for memory in args.profile or ['high', 'low']:
                result = run_case(work, base, language.lower()+'-'+memory,
                                  enhanced=True, dos=args.dos, grouped=True,
                                  country={'ET':372,'EE':372,'LV':371,'LT':370}[language],
                                  keyb_selection=language+',775,KEYBRD2.SYS',
                                  memory_profile=memory, layout_phases=plan, extra_files=files)
                result.update(language=language, mutations=variants)
                report['cases'].append(result); save()
    except Exception as error:
        report.update(status='failed', failure=str(error)); save(); raise
    assert report['cases'], 'no cases selected'
    report['status'] = 'selected-cases-passed'; save()


if __name__ == '__main__':
    main()
