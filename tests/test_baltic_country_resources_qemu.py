#!/usr/bin/env python3
"""Reject missing or malformed NLSFUNC country headers without changing locale."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from ru_profiles import CONFIG,verify_base,require_profile
from test_baltic_country_qemu import ROOT,COUNTRY,LANGUAGES,compile_probes


def mutations(data):
    bad=bytearray(data);bad[0]^=1
    cases={'missing':None,'empty':b'','short-signature':data[:7],
           'short-header':data[:22],'bad-signature':bytes(bad)}
    for offset in range(1,8):
        bad=bytearray(data);bad[offset]^=1;cases[f'bad-signature-{offset}']=bytes(bad)
    bad=bytearray(data);bad[18]=0;cases['bad-info-type']=bytes(bad)
    return cases


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--language',choices=list(LANGUAGES),action='append')
    parser.add_argument('--profile',choices=list(CONFIG),action='append')
    parser.add_argument('--case',choices=list(mutations(COUNTRY.read_bytes())),action='append')
    parser.add_argument('--nlsfunc',type=Path,default=ROOT/'src/CMD/NLSFUNC/NLSFUNC.EXE')
    args=parser.parse_args()
    base=Path(os.environ.get('FLOPPY_IMAGE',ROOT/'out/floppy.img'));core=verify_base(base)
    work=Path(tempfile.mkdtemp(prefix='baltic-country-resources-',dir=ROOT/'out'));print('Baltic country resource artifacts:',work,flush=True)
    compile_probes(work)
    report={'status':'running','core_sha256':core,'nlsfunc_sha256':hashlib.sha256(args.nlsfunc.read_bytes()).hexdigest(),'cases':[]}
    def save():(work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    save()
    try:
        for language in args.language or LANGUAGES:
            number=LANGUAGES[language];other=371 if number==372 else 372
            for profile in args.profile or CONFIG:
                for name,data in mutations(COUNTRY.read_bytes()).items():
                    if args.case and name not in args.case:continue
                    folder=work/language/profile/name;folder.mkdir(parents=True);image=folder/'boot.img';shutil.copyfile(base,image)
                    def put(name,value):subprocess.run(['mcopy','-o','-i',str(image),'-','::'+name],input=value,check=True)
                    for probe in work.glob('*.COM'):put(probe.name,probe.read_bytes())
                    for source,target in [(COUNTRY,'COUNTRY.SYS'),(COUNTRY,'BAD.SYS'),(args.nlsfunc,'NLSFUNC.EXE')]:put(target,source.read_bytes())
                    if data is not None:put('BROKEN.SYS',data)
                    subprocess.run(['nasm','-f','bin',f'-DTARGET={other}',f'-DERROR={2 if data is None else 1}',str(ROOT/'tests/baltic_country_resource_probe.asm'),'-o',str(folder/'REJECT.COM')],check=True);put('REJECT.COM',(folder/'REJECT.COM').read_bytes())
                    actions=[profile.upper()+'.COM',f'P{number}775.COM','NLSFUNC A:\\BAD.SYS',f'Q{other}775.COM',
                             'DEL BAD.SYS',
                             *([] if data is None else ['REN BROKEN.SYS BAD.SYS']),
                             'REJECT.COM',f'P{number}775.COM','COPY /Y COUNTRY.SYS BAD.SYS >NUL',f'Q{other}775.COM',f'S{other}775.COM',f'P{other}775.COM']
                    batch=['@ECHO OFF','CTTY AUX']
                    for action in actions:batch += [action,'IF ERRORLEVEL 1 GOTO FAIL']
                    batch+=['ECHO BALTIC_RESOURCE_DONE','QEXIT.COM',':FAIL','ECHO BALTIC_RESOURCE_CASE_FAIL','QEXIT.COM']
                    put('CONFIG.SYS',(f'COUNTRY={number},775,COUNTRY.SYS\r\n'+CONFIG[profile]).encode())
                    put('AUTOEXEC.BAT',('\r\n'.join(batch)+'\r\n').encode())
                    log=folder/'serial.log'
                    with log.open('wb') as out:
                        result=subprocess.run(['qemu-system-i386','-display','none','-m','8','-drive',f'if=floppy,format=raw,file={image}','-boot','a','-serial','stdio','-monitor','none','-no-reboot','-device','isa-debug-exit,iobase=0xf4,iosize=0x04'],stdin=subprocess.DEVNULL,stdout=out,stderr=subprocess.STDOUT,timeout=45)
                    output=log.read_bytes();require_profile(output,profile)
                    assert result.returncode==33 and b'BALTIC_RESOURCE_DONE' in output and b'FAIL' not in output,(folder,output)
                    assert output.count(b'BALTIC_RESOURCE_REJECTED')==1 and output.count(b'RU_COUNTRY_PASS')==4 and output.count(b'RU_QUERY_PASS')==2,output
                    report['cases'].append({'language':language,'profile':profile,'mutation':name,'mutant_sha256':None if data is None else hashlib.sha256(data).hexdigest(),'mutant_size':None if data is None else len(data),'actions':actions,'emulator_exit':result.returncode,'log':str(log.relative_to(work)),'log_sha256':hashlib.sha256(output).hexdigest()});save();print('PASS:',language,profile,name,flush=True)
    except Exception as error:
        report.update(status='failed',failure=str(error));save();raise
    report['status']='passed';save()


if __name__=='__main__':main()
