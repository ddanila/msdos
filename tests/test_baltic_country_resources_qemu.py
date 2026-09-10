#!/usr/bin/env python3
"""Validate NLSFUNC country resources, rejection, state and recovery."""
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
    for remaining in (0,1):
        bad=bytearray(data);bad[19:23]=(len(data)-remaining).to_bytes(4,'little')
        cases[f'directory-short-{remaining}']=bytes(bad)
        bad=bytearray(data);directory=int.from_bytes(data[19:23],'little');position=directory+2
        for _ in range(int.from_bytes(data[directory:directory+2],'little')):
            size=int.from_bytes(data[position:position+2],'little')
            country=int.from_bytes(data[position+2:position+4],'little');page=int.from_bytes(data[position+4:position+6],'little')
            if country in LANGUAGES.values() and page==775:
                bad[position+10:position+14]=(len(data)-remaining).to_bytes(4,'little')
            position+=size+2
        cases[f'objects-short-{remaining}']=bytes(bad)
    for kind in ('zero-count','short-record','truncated-list','excess-count','oversize-record','overflow-record'):
        bad=bytearray(data);directory=int.from_bytes(data[19:23],'little');position=directory+2
        for _ in range(int.from_bytes(data[directory:directory+2],'little')):
            size=int.from_bytes(data[position:position+2],'little')
            country=int.from_bytes(data[position+2:position+4],'little');page=int.from_bytes(data[position+4:position+6],'little')
            if country in LANGUAGES.values() and page==775:
                target=int.from_bytes(data[position+10:position+14],'little')
                if kind=='zero-count':bad[target:target+2]=bytes(2)
                elif kind=='excess-count':bad[target:target+2]=b'\xff\xff'
                elif kind in ('short-record','oversize-record','overflow-record'):
                    bad[target+2:target+4]={'short-record':5,'oversize-record':256,'overflow-record':65535}[kind].to_bytes(2,'little')
                else:
                    bad[position+10:position+14]=len(bad).to_bytes(4,'little');bad+=data[target:target+10]
            position+=size+2
        cases['objects-'+kind]=bytes(bad)
    directory=int.from_bytes(data[19:23],'little')
    bad=bytearray(data);bad[directory:directory+2]=bytes(2);cases['scan-zero-count']=bytes(bad)
    bad=bytearray(data);position=directory+2
    for _ in range(int.from_bytes(data[directory:directory+2],'little')):
        size=int.from_bytes(data[position:position+2],'little')
        country=int.from_bytes(data[position+2:position+4],'little');page=int.from_bytes(data[position+4:position+6],'little')
        if country in LANGUAGES.values() and page==775:bad[position:position+2]=(11).to_bytes(2,'little')
        position+=size+2
    cases['scan-short-record']=bytes(bad)
    entries=[];position=directory+2
    for _ in range(int.from_bytes(data[directory:directory+2],'little')):
        size=int.from_bytes(data[position:position+2],'little');entries.append(data[position:position+size+2]);position+=size+2
    def appended(records,count=None):
        bad=bytearray(data);bad[19:23]=len(bad).to_bytes(4,'little')
        return bad+(len(entries) if count is None else count).to_bytes(2,'little')+records
    packed=b''.join(entries)
    cases['scan-truncated-record']=bytes(appended(packed[:-1]))
    cases['scan-excess-count']=bytes(appended(packed,len(entries)+1))
    selected=next(e for e in entries if int.from_bytes(e[2:4],'little')==372 and int.from_bytes(e[4:6],'little')==775)
    cases['scan-truncated-padding']=bytes(appended(b'\xff\xff'+selected[2:],1))
    for length in (14,254,255,65535):
        expanded=[]
        for index,entry in enumerate(entries):
            country=int.from_bytes(entry[2:4],'little');page=int.from_bytes(entry[4:6],'little')
            if (country in LANGUAGES.values() and page==775) or index==len(entries)-1:
                entry=length.to_bytes(2,'little')+entry[2:]+bytes(length-(len(entry)-2))
            expanded.append(entry)
        cases[f'valid-scan-padding-{length}']=bytes(appended(b''.join(expanded)))
    object_pointers={k:[] for k in (1,2,4,5,6,7)}
    for entry in entries:
        country=int.from_bytes(entry[2:4],'little');page=int.from_bytes(entry[4:6],'little')
        if country in LANGUAGES.values() and page==775:
            objects=int.from_bytes(entry[10:14],'little');pointer=objects+2
            for _ in range(int.from_bytes(data[objects:objects+2],'little')):
                size=int.from_bytes(data[pointer:pointer+2],'little');kind=data[pointer+2]
                if kind in object_pointers:object_pointers[kind].append(pointer)
                pointer+=size+2
    def object_variant(kind,block):
        bad=bytearray(data)
        for pointer in object_pointers[kind]:bad[pointer+4:pointer+8]=len(data).to_bytes(4,'little')
        return bytes(bad+block)
    for kind,pointers in object_pointers.items():
        pointer=pointers[0];target=int.from_bytes(data[pointer+4:pointer+8],'little')
        length=int.from_bytes(data[target+8:target+10],'little');block=data[target:target+10+length]
        cases[f'data-{kind}-truncated']=object_variant(kind,block[:-1])
        for offset in (0,7):
            broken=bytearray(block);broken[offset]^=1
            cases[f'data-{kind}-signature-{offset}']=object_variant(kind,broken)
        for size in {1:(37,39),2:(127,129),4:(127,129),5:(7,47),6:(255,257),7:(1,17)}[kind]:
            broken=block[:8]+size.to_bytes(2,'little')+(block[10:]+bytes(size))[:size]
            cases[f'data-{kind}-length-{size}']=object_variant(kind,broken)
    pointer=object_pointers[4][0];target=int.from_bytes(data[pointer+4:pointer+8],'little')
    filecase=b'\xffFUCASE '+data[target+8:target+138]
    cases['valid-data-4-filecase']=object_variant(4,filecase)
    for offset in (0,7):
        broken=bytearray(filecase);broken[offset]^=1
        cases[f'data-4-filecase-signature-{offset}']=object_variant(4,broken)
    pointer=object_pointers[1][0];target=int.from_bytes(data[pointer+4:pointer+8],'little')
    for keep in (0,9,47):cases[f'data-info-short-{keep}']=object_variant(1,data[target:target+keep])
    pointer=object_pointers[5][0];target=int.from_bytes(data[pointer+4:pointer+8],'little')
    broken=bytearray(data[target:target+32]);broken[17]=255
    cases['data-filechar-count']=object_variant(5,broken)
    pointer=object_pointers[7][0];target=int.from_bytes(data[pointer+4:pointer+8],'little')
    cases['data-dbcs-unterminated']=object_variant(7,data[target:target+8]+b'\x04\x00\x81\x9f\xe0\xfc')
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
                    valid=name.startswith('valid-')
                    exercise=[f'Q{other}775.COM',f'S{other}775.COM',f'P{other}775.COM',f'S{number}775.COM'] if valid else ['REJECT.COM']
                    actions=[profile.upper()+'.COM',f'P{number}775.COM','NLSFUNC A:\\BAD.SYS',f'Q{other}775.COM',
                             'DEL BAD.SYS',
                             *([] if data is None else ['REN BROKEN.SYS BAD.SYS']),
                             *exercise,f'P{number}775.COM','COPY /Y COUNTRY.SYS BAD.SYS >NUL',f'Q{other}775.COM',f'S{other}775.COM',f'P{other}775.COM']
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
                    assert output.count(b'BALTIC_RESOURCE_REJECTED')==(0 if valid else 1) and output.count(b'RU_COUNTRY_PASS')==(7 if valid else 4) and output.count(b'RU_QUERY_PASS')==(3 if valid else 2),output
                    report['cases'].append({'language':language,'profile':profile,'mutation':name,'valid_control':valid,'mutant_sha256':None if data is None else hashlib.sha256(data).hexdigest(),'mutant_size':None if data is None else len(data),'actions':actions,'emulator_exit':result.returncode,'log':str(log.relative_to(work)),'log_sha256':hashlib.sha256(output).hexdigest()});save();print('PASS:',language,profile,name,flush=True)
    except Exception as error:
        report.update(status='failed',failure=str(error));save();raise
    report['status']='passed';save()


if __name__=='__main__':main()
