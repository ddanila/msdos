#!/usr/bin/env python3
"""Independent Russian NLS contract on real IBM AT BIOS and a 286."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from test_ru_country_qemu import compile_probes, read_records

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from memory_release import selected_core


def cases():
    result=[(f'config-{page}',f'COUNTRY=007,{page},COUNTRY.SYS\r\n',[f'P{page}.COM'])
            for page in (866,437,850)]
    result.append(('config-default','COUNTRY=007,,COUNTRY.SYS\r\n',['P866.COM']))
    actions=['P866.COM','NLSFUNC','MODE CON CP PREPARE=((866) EGA866.CPI)',
             'MODE CON CP PREPARE=((,437,850) EGA.CPI)']
    for page in (866,437,850,866):
        actions += [f'CHCP {page}','CPCHK.COM',f'P{page}.COM',
                    'Q850.COM' if page==866 else 'Q866.COM']
    actions += ['REJECT.COM','CPCHK.COM','P866.COM']
    result.append(('transitions','COUNTRY=007,866,COUNTRY.SYS\r\n',actions))
    result.append(('wrong-case','COUNTRY=007,866,COUNTRY.SYS\r\n',['P866.COM']))
    return result


def run_case(work,args,core,name,country_config,actions):
    case=work/name
    case.mkdir()
    image=case/'test.img'
    subprocess.run(['bash','-c','source "$1/tests/86box_286_lib.sh"\nmake_86box_286_boot_image "$2" "$1"',
                    'bash',str(ROOT),str(image)],check=True,stdout=subprocess.DEVNULL)
    def put(name,data):
        subprocess.run(['mcopy','-o','-i',str(image),'-','::'+name],input=data,check=True)
    for filename in ('IO.SYS','MSDOS.SYS','COMMAND.COM'):
        assert subprocess.check_output(['mtype','-i',str(image),'::'+filename])==core[filename],filename
    for filename in ('P866.COM','P437.COM','P850.COM','Q866.COM','Q437.COM','Q850.COM',
                     'CPCHK.COM','REJECT.COM','BXEXIT.COM'):
        put(filename,(work/filename).read_bytes())
    country=bytearray((ROOT/'src/DEV/COUNTRY/COUNTRY.SYS').read_bytes())
    corrupt=name=='wrong-case'
    if corrupt:
        offset=read_records(country)[7,866][2]['offset']+10+0xf1-128
        country[offset]=0xf1
    put('COUNTRY.SYS',country)
    for source,target in [('DEV/DISPLAY/EGA/EGA866.CPI','EGA866.CPI'),
                          ('DEV/DISPLAY/EGA/EGA.CPI','EGA.CPI'),
                          ('DEV/DISPLAY/DISPLAY.SYS','DISPLAY.SYS'),
                          ('CMD/MODE/MODE.COM','MODE.COM'),('CMD/NLSFUNC/NLSFUNC.EXE','NLSFUNC.EXE')]:
        put(target,(ROOT/'src'/source).read_bytes())
    config_sys=country_config+'DOS=LOW\r\n'
    if name=='transitions':
        config_sys+='DEVICE=DISPLAY.SYS CON=(EGA,437,(3,3))\r\n'
    put('CONFIG.SYS',config_sys.encode())
    batch=['@ECHO OFF','CTTY AUX']
    for action in actions:
        batch += ['ECHO RUN '+action,action,'IF ERRORLEVEL 1 GOTO FAIL']
    batch += ['ECHO RU_COUNTRY_DONE','BXEXIT.COM',':FAIL','ECHO RU_CASE_FAIL','BXEXIT.COM FAIL']
    put('AUTOEXEC.BAT',('\r\n'.join(batch)+'\r\n').encode())
    config=(ROOT/'tests/86box/ibmat-286.cfg').read_text()
    config=config.replace('gfxcard = cga','gfxcard = vga').replace('size = 2048','size = 512')
    config=config.replace('[Other peripherals]','[Other peripherals]\nunittester_enabled = 1')
    (case/'startup.cfg').write_text(config)
    (case/'86box.cfg').write_text(config)
    shutil.copyfile(ROOT/'tests/86box/global.cfg',case/'global.cfg')
    subprocess.run(['python3',str(ROOT/'tests/seed_86box_ibmat_nvram.py'),str(case/'nvr/ibm5170_111585.nvr'),
                    '--display','vga','--extended-kib','512'],check=True)
    env=dict(os.environ)
    if args.qt_platform:
        env['QT_QPA_PLATFORM']=args.qt_platform
    log=case/'serial.log'
    with log.open('wb') as output:
        result=subprocess.run([str(args.emulator.resolve()),'-N','-O',str(case/'global.cfg'),'-P',str(case),
                               '-R',str(args.roms.resolve()),'-I','a:'+str(image)],env=env,
                              stdin=subprocess.DEVNULL,stdout=output,stderr=subprocess.STDOUT,timeout=240)
    data=log.read_bytes()
    counts={}
    if corrupt:
        assert result.returncode==1 and data.count(b'RU_COUNTRY_FAIL stage 03')==1,log
        assert b'RU_COUNTRY_DONE' not in data and data.count(b'RU_CASE_FAIL')==1,log
    else:
        assert result.returncode==0 and b'FAIL' not in data and data.count(b'RU_COUNTRY_DONE')==1,(result.returncode,log)
        for marker,count in [(b'RU_COUNTRY_PASS',sum(a in ('P866.COM','P437.COM','P850.COM') for a in actions)),
                             (b'RU_QUERY_PASS',sum(a in ('Q866.COM','Q437.COM','Q850.COM') for a in actions)),
                             (b'RU_CODEPAGE_PASS',actions.count('CPCHK.COM')),
                             (b'RU_REJECTION_PASS',actions.count('REJECT.COM'))]:
            assert data.count(marker)==count,(marker,log)
            counts[marker.decode()]=count
    print(f'PASS: 286 country {name}',flush=True)
    return {'name':name,'negative_control':corrupt,'emulator_exit':result.returncode,
            'config_sys':config_sys,'actions':actions,'markers':counts,
            'country_sha256':hashlib.sha256(country).hexdigest(),
            'config_sha256':hashlib.sha256(config.encode()).hexdigest(),
            'log':str(log.relative_to(work)),'log_sha256':hashlib.sha256(data).hexdigest()}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emulator',type=Path,required=True)
    parser.add_argument('--roms',type=Path,required=True)
    parser.add_argument('--qt-platform')
    parser.add_argument('--case',choices=[c[0] for c in cases()],action='append')
    args=parser.parse_args()
    core=selected_core()
    if not core:
        parser.error('MEMORY_CORE_DIR must select the production core')
    work=Path(tempfile.mkdtemp(prefix='ru-country-286-',dir=ROOT/'out'))
    print(f'Russian 286 country artifacts: {work}',flush=True)
    compile_probes(work)
    subprocess.run(['nasm','-f','bin',str(ROOT/'tests/86box_exit.asm'),'-o',str(work/'BXEXIT.COM')],check=True)
    report={'status':'running','core_sha256':{n:hashlib.sha256(d).hexdigest() for n,d in core.items()},
            'emulator_sha256':hashlib.sha256(args.emulator.read_bytes()).hexdigest(),'cases':[]}
    def save():
        (work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    save()
    try:
        for name,config,actions in cases():
            if not args.case or name in args.case:
                report['cases'].append(run_case(work,args,core,name,config,actions))
                save()
    except Exception as error:
        report['status']='failed';report['failure']=str(error);save();raise
    report['status']='selected-cases-passed';save()


if __name__=='__main__':
    main()
