#!/usr/bin/env python3
"""Physically arm dead keys, reload or reject a layout, then check pending state."""
import argparse
import json
import os
import re
import struct

from baltic_keyboard_records import validate
from pathlib import Path
import tempfile

from ru_profiles import verify_base
from test_baltic_keyboard_qemu import ROOT, REFERENCE, SCANS, tap
from test_ru_keyboard_qemu import run_case


def scenarios():
    profiles=json.loads(REFERENCE.read_text())['profiles']
    modifiers={'normal':(), 'shift':('shift',), 'AltGr | Shift':('alt_r',),
               'Shift AltGr':('shift','alt_r'), 'Ctrl':('ctrl',), 'Alt':('alt',)}
    for language in ('et','lv'):
        profile=profiles[language]; triggers={}
        for scan, cells in profile['keys'].items():
            for plane, cell in zip(profile['planes'],cells):
                if cell and cell['kind']=='dead':
                    triggers.setdefault(str(cell['id']),tap(*modifiers[plane],SCANS[int(scan)]))
        for dead_id, trigger in triggers.items():
            dead=profile['dead_keys'][dead_id]
            base=next(int(byte) for byte in dead['pairs'] if 97<=int(byte)<=122)
            scan=next(scan for scan,key in SCANS.items() if key==chr(base))
            byte=dead['pairs'][str(base)]
            yield language+'-'+dead_id, language.upper(), trigger, dead['literal'], tap(chr(base)), (0 if byte==224 else scan)*256+byte
    # German has no Baltic selection-reset feature. Entering Baltic must still
    # clear this foreign pending flag after the newly selected tables are copied.
    yield 'gr-acute','GR',tap('equal'),39,tap('a'),0x00a0


def phases(source, trigger, literal, base_events, composed):
    def step(name,events,*words):
        result={'name':name,'keys':events,'bios_words':list(words)}
        if not words: result['ack_after']=len(events)-2
        return result
    def phase(code,command,cases,reject=False):
        return {'status_code':code,'status_page':437 if code=='GR' else 775,
                'command':command,'reject':reject,'cases':cases}
    select=lambda code: f'KEYB {code},{437 if code=="GR" else 775},{"KEYBOARD.SYS" if code=="GR" else "KEYBRD2.SYS"}'
    def arm():
        return [step('literal confirms trigger',trigger+tap('spc'),literal),
                step('arm pending; physical Caps on/off barrier',trigger+tap('caps_lock')+tap('shift' if source=='GR' else 'caps_lock'))]
    result=[]
    for target in ('ET','EE','LV','LT')+((source,) if source!='GR' else ()):
        result.append(phase(source,select(source),arm()))
        result.append(phase(target,select(target),[
            step('fresh target input',tap('q'),0x10d0 if target=='LT' else 0x1071)]))
        result.append(phase('ET',select('ET'),[step('no stale state after return',tap('q'),0x1071)]))
    if source=='GR':
        result.append(phase(source,select(source),arm()))
        result.append(phase(source,select(source),[
            step('legacy self-reload retains pending',base_events,composed),
            step('legacy composition consumed once',tap('q'),0x1071)]))
    for command in [f'KEYB {source},775,MISSING.SYS',
                    f'KEYB {source},775,KEYBRD2.SYS /ID:999']:
        result.append(phase(source,select(source),arm()))
        result.append(phase(source,command,[
            step('rejection retains pending composition',base_events,composed),
            step('composition consumed once',tap('q'),0x1071)],reject=True))
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile',choices=['high','low'],action='append')
    parser.add_argument('--case',choices=[item[0] for item in scenarios()],action='append')
    parser.add_argument('--dos',action='store_true')
    controls=parser.add_mutually_exclusive_group()
    controls.add_argument('--no-reset-control',action='store_true')
    controls.add_argument('--capacity-control',action='store_true')
    controls.add_argument('--small-allocation',action='store_true')
    args=parser.parse_args()
    base=Path(os.environ.get('FLOPPY_IMAGE',ROOT/'out/floppy.img'))
    core=verify_base(base)
    work=Path(tempfile.mkdtemp(prefix='baltic-key-pending-',dir=ROOT/'out'))
    print(f'Baltic pending-key artifacts: {work}',flush=True)
    library=ROOT/'src/DEV/KEYBOARD/KEYBRD2.SYS'
    extra={}; failure=None
    if args.no_reset_control:
        data=bytearray(library.read_bytes())
        for code,(logic,_,_) in validate(data).items():
            if code!='RU': struct.pack_into('<H',data,logic+2,0)
        library=work/'NO_RESET.SYS'; library.write_bytes(data)
        failure=b'RU_KEY_FAIL actual=0060'
    if args.capacity_control:
        data=bytearray((ROOT/'src/CMD/KEYB/KEYB.COM').read_bytes())
        # Restore the old omission in DONT_REPLACE, keeping code offsets fixed.
        matches=list(re.finditer(rb'\x26\x8b\x46\x20\x0e\x07\xbd..\x26\x89\x46\x20',data,re.DOTALL))
        assert len(matches)==1, 'allocation-preservation instruction signature'
        start=matches[0].end()-4; data[start:start+4]=b'\x90'*4
        program=work/'NO_CAP.COM'; program.write_bytes(data);extra['KEYB.COM']=program
        failure=b'RU_KEY_FAIL actual=FFFF'
    report={'status':'running','core_sha256':core,'cases':[]}
    def save(): (work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    save()
    try:
        for memory in args.profile or ['high','low']:
            for name,source,trigger,literal,events,composed in scenarios():
                if args.case and name not in args.case: continue
                if (failure or args.small_allocation) and name!='gr-acute': continue
                plan=phases(source,trigger,literal,events,composed)
                if args.small_allocation:
                    # Use the already built arm and rejected-load oracle, but
                    # start with the smaller original KEYBOARD.SYS allocation.
                    plan=[plan[0],plan[-1]]
                    plan[0]['command']=None
                    plan[1]['command']='KEYB ET,775,KEYBRD2.SYS'
                    plan[1]['cases'][0]['name']='oversize rejection retains pending composition'
                report['cases'].append(run_case(work,base,memory+'-'+name,
                    dos=args.dos,enhanced=True,grouped=True,memory_profile=memory,
                    keyb_selection='GR,437,KEYBOARD.SYS' if args.small_allocation else 'ET,775,KEYBRD2.SYS',country=372,
                    layout_phases=plan,
                    library_source=library,extra_files=extra,expected_failure=failure))
                save()
    except Exception as error:
        report.update(status='failed',failure=str(error));save();raise
    if not report['cases']: raise AssertionError('no pending-state cases selected')
    report['status']='selected-cases-passed';save()


if __name__=='__main__': main()
