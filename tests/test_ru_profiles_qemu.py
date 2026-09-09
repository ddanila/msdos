#!/usr/bin/env python3
"""Actual VGA font bytes and NLS transitions on production HIGH/UMB and LOW."""
import argparse
import json
import os
from pathlib import Path
import tempfile

from ru_profiles import CONFIG, verify_base
from test_ru_country_qemu import command, compile_probes, run_case as country_case
from test_ru_display_qemu import run_case as display_case, existing_font
from test_ru_cpi import ROOT, CPI, parse_cpi, check_glyphs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', choices=('high','low'), action='append')
    parser.add_argument('--part', choices=('all','display','country'), default='all')
    args = parser.parse_args()
    base = Path(os.environ.get('FLOPPY_IMAGE',ROOT/'out/floppy.img'))
    core = verify_base(base)
    work = Path(tempfile.mkdtemp(prefix='ru-profiles-',dir=ROOT/'out'))
    print(f'Russian profile artifacts: {work}',flush=True)
    fonts = parse_cpi(CPI.read_bytes())
    check_glyphs(fonts)
    report = {'core_sha256':core, 'selection':{'profiles':args.profile or list(CONFIG),
              'part':args.part}, 'status':'running', 'profiles':[]}
    def save():
        (work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    save()
    try:
        for profile in report['selection']['profiles']:
            directory = work/profile
            directory.mkdir()
            compile_probes(directory)
            command('nasm','-f','bin',f'-DHIGH={int(profile == "high")}',
                    str(ROOT/'tests/ru_profile_probe.asm'),'-o',str(directory/'PROFILE.COM'))
            result = {'profile':profile,'display':[],'country':[]}
            report['profiles'].append(result)
            if args.part != 'country':
                cases = [(866,height,fonts[height],False) for height in (16,14,8)]
                cases += [(page,16,existing_font(page,16),False) for page in (437,850,860,863,865)]
                cases += [(866,16,fonts[16],True)]
                for page,height,expected,corrupt in cases:
                    result['display'].append(display_case(directory,base,page,height,expected,
                                             corrupt=corrupt,profile=profile))
                    save()
            if args.part != 'display':
                actions = ['P866.COM','NLSFUNC','MODE CON CP PREPARE=((866) EGA866.CPI)',
                           'MODE CON CP PREPARE=((,437,850) EGA.CPI)']
                for page in (866,437,850,866):
                    actions += [f'CHCP {page}','CPCHK.COM',f'P{page}.COM',
                                'Q850.COM' if page == 866 else 'Q866.COM']
                actions += ['REJECT.COM','CPCHK.COM','P866.COM']
                config = 'COUNTRY=007,866,COUNTRY.SYS\r\n'+CONFIG[profile]
                result['country'].append(country_case(directory,base,'transitions',
                    config+'DEVICE=DISPLAY.SYS CON=(EGA,437,(3,3))\r\n',actions,6,profile=profile))
                save()
                result['country'].append(country_case(directory,base,'wrong-case',
                    config,['P866.COM'],0,corrupt=True,profile=profile))
                save()
    except Exception as error:
        report['status'] = 'failed'
        report['failure'] = str(error)
        save()
        raise
    report['status'] = 'selected-cases-passed'
    save()


if __name__ == '__main__':
    main()
