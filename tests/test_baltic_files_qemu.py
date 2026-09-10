#!/usr/bin/env python3
"""Baltic CP775 short names, country sorting, recursive copies and reboot."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile

from ru_profiles import CONFIG, verify_base
from test_ru_files_qemu import ROOT, run_case


def language_profile(language):
    manifest=json.loads((ROOT/'locales/baltic/manifest.json').read_text())['languages'][language]
    reference=json.loads((ROOT/'locales/baltic/review/country-expectations.json').read_text())['countries'][language]['775']
    letters=manifest['required_lowercase']
    # ET deliberately exercises FAT's E5/05 first-byte escape in files and directories.
    first={'et':'\u00f5','lv':'\u0137','lt':'\u0105'}[language]
    names={key:first+suffix for key,suffix in [('DIR','dir'),('SUB','sub'),('MAIN','file.txt'),
           ('COPY','copy.dat'),('RENAMED','new.dat'),('DOC','doc.'+first),('STEM','test'),
           ('TREE','tree'),('MOVED','moved'),('CLONE','clone'),('EMPTY','empty')]}
    names['NAMES']=[c+'.txt' for c in letters[::-1]+'za']+[names['STEM']+s+'.txt' for s in ('','1','2','12')]
    names['EXTENSIONS']=['ext.'+c for c in letters[::-1]+'za']
    names['PAYLOAD']=letters+' '+manifest['required_uppercase']
    return dict(names,language=language,encoding='cp775',country={'et':372,'lv':371,'lt':370}[language],
                temporary=first+'temp',weights=bytes.fromhex(reference['collation_hex']))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--language',choices=['et','lv','lt'],action='append')
    parser.add_argument('--profile',choices=list(CONFIG),action='append')
    parser.add_argument('--emulator',type=Path)
    parser.add_argument('--roms',type=Path)
    parser.add_argument('--qt-platform')
    args=parser.parse_args()
    if args.emulator and not args.roms:parser.error('--roms is required with --emulator')
    if args.emulator and args.profile and args.profile!=['low']:parser.error('286 backend requires LOW')
    base=Path(os.environ.get('FLOPPY_IMAGE',ROOT/'out/floppy.img'));core=verify_base(base)
    work=Path(tempfile.mkdtemp(prefix='baltic-files-',dir=ROOT/'out'));print('Baltic filesystem artifacts:',work,flush=True)
    report={'status':'running','core_sha256':core,'backend':'86box-286' if args.emulator else 'qemu','cases':[]}
    if args.emulator:report['emulator_sha256']=hashlib.sha256(args.emulator.read_bytes()).hexdigest()
    def save():(work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    save()
    try:
        for language in args.language or ['et','lv','lt']:
            folder=work/language;folder.mkdir();locale=language_profile(language)
            for profile in args.profile or (['low'] if args.emulator else CONFIG):
                case=run_case(folder,base,profile,args,core,locale);case['language']=language
                report['cases'].append(case);save()
    except Exception as error:
        report.update(status='failed',failure=str(error));save();raise
    report['status']='passed';save()


if __name__=='__main__':main()
