#!/usr/bin/env python3
"""Physical CP775 shell/editor workflows, persisted bytes and rendered glyphs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile

from test_baltic_keyboard_qemu import REFERENCE, SCANS
from test_ru_text_qemu import ROOT, run_case
from ru_profiles import CONFIG, verify_base

SAMPLES = {
    'et': ('Tere, \u00f5un ja \u00f6\u00f6! \u00c4\u00d6\u00d5\u00dc \u0160\u017d \u00e4\u00f6\u00f5\u00fc \u0161\u017e', '\u00d5un'),
    'lv': ('Labr\u012bt, R\u012bga! \u0100\u010c\u0112\u0122\u012a\u0136\u013b\u0145\u0160\u016a\u017d \u0101\u010d\u0113\u0123\u012b\u0137\u013c\u0146\u0161\u016b\u017e / ET: \u00f5', '\u0136irsis'),
    'lt': ('Labas, \u0105\u017euolas! \u0104\u010c\u0118\u0116\u012e\u0160\u0172\u016a\u017d \u0105\u010d\u0119\u0117\u012f\u0161\u0173\u016b\u017e', '\u0104\u017euolas'),
}


def ascii_keys(char):
    if char.isascii() and char.isalpha():
        return ('shift',char.lower()) if char.isupper() else (char,)
    if char.isdigit(): return (char,)
    plain={' ':'spc','.':'dot',',':'comma','/':'slash','-':'minus'}
    shifted={'_':'minus','>':'dot','|':'backslash','"':'apostrophe',':':'semicolon','!':'1'}
    if char in plain:return (plain[char],)
    return ('shift',shifted[char])


def language_profile(language):
    source=json.loads(REFERENCE.read_text())['profiles'][language]
    modifiers={'normal':(), 'shift':('shift',), 'AltGr | Shift':('ctrl','alt'),
               'Shift AltGr':('shift','ctrl','alt')}
    direct={};dead={}
    for scan,cells in source['keys'].items():
        for plane,cell in zip(source['planes'],cells):
            if not cell or plane not in modifiers:continue
            stroke=modifiers[plane]+(SCANS[int(scan)],)
            if cell['kind']=='character':direct.setdefault(cell['byte'],[stroke])
            elif cell['kind']=='dead':dead.setdefault(str(cell['id']),stroke)
    composed={}
    for identifier,trigger in dead.items():
        for base,value in source['dead_keys'][identifier]['pairs'].items():
            if int(base)<128 and chr(int(base)).isalpha():
                composed.setdefault(value,[trigger,ascii_keys(chr(int(base)))])
    # Prefer real composition when available, so application input exercises it.
    direct.update(composed)
    sample,second=SAMPLES[language]
    contract=json.loads((ROOT/'locales/baltic/manifest.json').read_text())['languages'][language]
    assert set(contract['required_lowercase']+contract['required_uppercase'])<=set(sample)
    if source['dead_keys']:
        assert any(ord(c)>127 and len(direct[c.encode('cp775')[0]])>1 for c in sample)
    for char in sample+second:
        if ord(char)>127:assert char.encode('cp775')[0] in direct,char
    def type_text(value,tap,national):
        for char in value:
            target=ord(char)>127
            if target!=national:
                tap('ctrl','alt','f2' if target else 'f1');national=target
            for stroke in direct[char.encode('cp775')[0]] if target else [ascii_keys(char)]:
                tap(*stroke)
        return national
    return {'language':language,'page':775,'country':{'et':372,'lv':371,'lt':370}[language],
            'keyb':f'KEYB {language.upper()},775,KEYBRD2.SYS /ID:'+str({'et':454,'lv':0,'lt':221}[language]),
            'sample':sample,'second':second,'first':'Draft','error':'Wrong','type':type_text,
            'national_sequences':{str(b):v for b,v in direct.items() if b>=128}}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--language',choices=list(SAMPLES),action='append')
    parser.add_argument('--profile',choices=list(CONFIG),action='append')
    parser.add_argument('--emulator',type=Path)
    parser.add_argument('--roms',type=Path)
    parser.add_argument('--qt-platform')
    args=parser.parse_args()
    if args.emulator and not args.roms:parser.error('--roms is required with --emulator')
    if args.emulator and args.profile and args.profile!=['low']:parser.error('286 backend requires LOW')
    base=Path(os.environ.get('FLOPPY_IMAGE',ROOT/'out/floppy.img'));core=verify_base(base)
    work=Path(tempfile.mkdtemp(prefix='baltic-text-',dir=ROOT/'out'))
    print('Baltic text artifacts:',work,flush=True)
    report={'status':'running','core_sha256':core,'backend':'86box-286' if args.emulator else 'qemu','cases':[]}
    if args.emulator:report['emulator_sha256']=hashlib.sha256(args.emulator.read_bytes()).hexdigest()
    def save():(work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    save()
    try:
        for language in args.language or SAMPLES:
            folder=work/language;folder.mkdir();locale=language_profile(language)
            for profile in args.profile or (['low'] if args.emulator else CONFIG):
                result=run_case(folder,base,profile,args,core,locale)
                result.update(language=language,national_sequences=locale['national_sequences'])
                report['cases'].append(result);save()
    except Exception as error:
        report.update(status='failed',failure=str(error));save();raise
    report['status']='passed';save()


if __name__=='__main__':main()
