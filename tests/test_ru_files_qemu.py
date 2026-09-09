#!/usr/bin/env python3
"""Cyrillic 8.3 operations, DOS wildcard/order rules and fresh-boot persistence."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from ru_profiles import CONFIG, verify_base, require_profile

ROOT=Path(__file__).resolve().parents[1]
DIR='\u043f\u0430\u043f\u043a\u0430'
SUB='\u0432\u043b\u043e\u0436\u0435\u043d'
MAIN='\u0451\u0436\u0438\u043a.txt'
COPY='\u043a\u043e\u043f\u0438\u044f.dat'
RENAMED='\u043d\u043e\u0432\u043e\u0435.dat'
DOC='\u0434\u043e\u043a\u0443\u043c\u0435\u043d\u0442.\u0442\u0441\u0442'
STEM='\u0442\u0435\u0441\u0442'
NAMES=[c+'.txt' for c in '\u044f\u0430\u0451\u0435\u0431\u0445']+[STEM+s+'.txt' for s in ('','1','2','12')]
EXTENSIONS=['ext.'+c for c in '\u044f\u0430\u0451\u0435']
PAYLOAD='\u0434\u0430\u043d\u043d\u044b\u0435 \u0401\u0451'


def short_name(name):
    parts=name.upper().encode('cp866').split(b'.')
    return parts[0].ljust(8,b' ')+(parts[1] if len(parts)>1 else b'').ljust(3,b' ')


class FAT:
    def __init__(self,image):
        self.data=image.read_bytes();b=self.data
        self.sector=int.from_bytes(b[11:13],'little');self.cluster=b[13]*self.sector
        reserved=int.from_bytes(b[14:16],'little');fat_sectors=int.from_bytes(b[22:24],'little')
        self.fat=b[reserved*self.sector:(reserved+fat_sectors)*self.sector]
        self.root=(reserved+b[16]*fat_sectors)*self.sector
        self.root_size=int.from_bytes(b[17:19],'little')*32
        self.start=self.root+((self.root_size+self.sector-1)//self.sector)*self.sector
        self.fat12=(len(b)-self.start)//self.cluster<4085
    def chain(self,cluster):
        result=b'';seen=set()
        while cluster>=2 and cluster<(0xff8 if self.fat12 else 0xfff8):
            assert cluster not in seen;seen.add(cluster)
            start=self.start+(cluster-2)*self.cluster;result+=self.data[start:start+self.cluster]
            if self.fat12:
                pos=cluster*3//2;word=int.from_bytes(self.fat[pos:pos+2],'little')
                cluster=(word>>4) if cluster&1 else word&0xfff
            else:cluster=int.from_bytes(self.fat[cluster*2:cluster*2+2],'little')
        return result
    def entries(self,cluster=0):
        b=self.chain(cluster) if cluster else self.data[self.root:self.root+self.root_size]
        result={}
        for off in range(0,len(b),32):
            entry=b[off:off+32]
            if entry[0]==0:break
            if entry[0]!=0xe5 and entry[11]!=15:result[entry[:11]]=entry
        return result
    def read(self,entry):return self.chain(int.from_bytes(entry[26:28],'little'))[:int.from_bytes(entry[28:32],'little')]


def run_case(work,base,profile):
    case=work/profile;case.mkdir();image=case/'test.img';shutil.copyfile(base,image)
    def put(name,data):subprocess.run(['mcopy','-o','-i',str(image),'-','::'+name],input=data,check=True)
    for source,name,defines in [('ru_profile_probe.asm','PROFILE.COM',[f'-DHIGH={int(profile=="high")}']),('qemu_exit.asm','QEXIT.COM',[])]:
        subprocess.run(['nasm','-f','bin',*defines,str(ROOT/'tests'/source),'-o',str(case/name)],check=True);put(name,(case/name).read_bytes())
    put('CONFIG.SYS',('COUNTRY=007,866,COUNTRY.SYS\r\n'+CONFIG[profile]).encode())
    def batch(actions,end):
        lines=['@ECHO OFF','CTTY AUX','PROFILE.COM','IF ERRORLEVEL 1 GOTO FAIL']
        for action in actions:lines += [action,'IF ERRORLEVEL 1 GOTO FAIL']
        lines += ['ECHO '+end,'QEXIT.COM',':FAIL','ECHO RU_FILES_FAIL','QEXIT.COM']
        return ('\r\n'.join(lines)+'\r\n').encode('cp866')
    first=[f'MD {DIR}',f'CD {DIR.upper()}',f'ECHO {PAYLOAD}>{MAIN}',
           f'TYPE {MAIN.upper()} > A:\\LOOKUP.TXT',f'COPY {MAIN} {COPY} >NUL',
           f'REN {COPY.upper()} {RENAMED}',f'TYPE {RENAMED.upper()} > A:\\RENAMED.TXT',
           f'DEL {RENAMED.upper()}',f'MD {SUB}',f'COPY {MAIN.upper()} {SUB}\\{DOC} >NUL',
           f'TYPE {SUB.upper()}\\{DOC.upper()} > A:\\NESTED.TXT',
           'MD \u0432\u0440\u0435\u043c','RD \u0412\u0420\u0415\u041c']
    first += [f'ECHO {PAYLOAD}>{SUB}\\{name}' for name in EXTENSIONS]
    first += [f'ECHO {PAYLOAD}>{name}' for name in NAMES]
    first += [f'DIR /B /A:-D /O:E {SUB}\\*.* > A:\\EXTORD.TXT',
              'DIR /B /O:-N *.TXT > A:\\REVERSE.TXT','DIR /B /O:N *.TXT > A:\\ORDER.TXT','DIR /B ?.TXT > A:\\ONE.TXT',
              f'DIR /B {STEM}?.TXT > A:\\WILD.TXT','CD \\',
              'ECHO CREATED>STAGE.TAG']
    second=[f'CD {DIR.upper()}',f'TYPE {MAIN.upper()} > A:\\REBOOT.TXT',
            f'TYPE {SUB.upper()}\\{DOC.upper()} > A:\\REBNEST.TXT',
            'DIR /B /O:N *.TXT > A:\\REORDER.TXT',f'DEL {SUB.upper()}\\{DOC.upper()}',
            f'DEL {SUB.upper()}\\EXT.*',f'RD {SUB.upper()}','DEL *.TXT','CD \\',f'RD {DIR.upper()}']
    put('AUTOEXEC.BAT',b'@ECHO OFF\r\nIF EXIST STAGE.TAG GOTO SECOND\r\n'+batch(first,'RU_FILES_CREATED')+b':SECOND\r\nNEXT.BAT\r\n')
    put('NEXT.BAT',batch(second,'RU_FILES_REBOOTED'))
    phases=[]
    for phase,marker in [('create',b'RU_FILES_CREATED'),('reboot',b'RU_FILES_REBOOTED')]:
        log=case/(phase+'.log')
        with log.open('wb') as output:
            result=subprocess.run(['qemu-system-i386','-display','none','-m','8',
                '-drive',f'if=floppy,format=raw,file={image},cache=writethrough','-boot','a','-serial','stdio',
                '-monitor','none','-no-reboot','-device','isa-debug-exit,iobase=0xf4,iosize=0x04'],
                stdin=subprocess.DEVNULL,stdout=output,stderr=subprocess.STDOUT,timeout=30)
        data=log.read_bytes();assert result.returncode==33 and marker in data and b'RU_FILES_FAIL' not in data,(phase,log)
        require_profile(data,profile);fat=FAT(image);root=fat.entries();payload=(PAYLOAD+'\r\n').encode('cp866')
        if phase=='create':
            entry=root[short_name(DIR)];assert entry[11]&16
            directory=fat.entries(int.from_bytes(entry[26:28],'little'))
            expected={short_name(n) for n in [MAIN,*NAMES]}
            actual={n for n,e in directory.items() if not e[11]&16}
            assert actual==expected,(actual,expected)
            for n in expected:assert fat.read(directory[n])==payload,n
            nested=fat.entries(int.from_bytes(directory[short_name(SUB)][26:28],'little'))
            assert fat.read(nested[short_name(DOC)])==payload
            for n in EXTENSIONS:assert fat.read(nested[short_name(n)])==payload
            assert short_name(RENAMED) not in directory and short_name(COPY) not in directory
            assert short_name('\u0432\u0440\u0435\u043c') not in directory
            raw=b''.join(directory.values());(case/'directory.bin').write_bytes(raw)
            (case/'nested.bin').write_bytes(b''.join(nested.values()))
            checks=['LOOKUP.TXT','RENAMED.TXT','NESTED.TXT']
        else:
            assert short_name(DIR) not in root;checks=['REBOOT.TXT','REBNEST.TXT']
        files={}
        for n in checks:
            value=fat.read(root[short_name(n)]);assert value==payload,(n,value);files[n]=value.hex()
        for n in (['ORDER.TXT','ONE.TXT','WILD.TXT','REVERSE.TXT','EXTORD.TXT'] if phase=='create' else ['REORDER.TXT']):
            value=fat.read(root[short_name(n)]);(case/n).write_bytes(value);files[n]=value.hex()
        phases.append({'phase':phase,'emulator_exit':result.returncode,'files_hex':files,
                       'log_sha256':hashlib.sha256(data).hexdigest(),'image_sha256':hashlib.sha256(image.read_bytes()).hexdigest()})
    ref=json.loads((ROOT/'locales/ru/dos622-reference.json').read_text())['country_records']['866']['objects']['6']
    weights=bytes.fromhex(ref['payload']);names=[n.upper().encode('cp866') for n in [MAIN,*NAMES]]
    ordered=sorted(names,key=lambda name:bytes(weights[b] for b in name))
    expected_order=b''.join(n+b'\r\n' for n in ordered)
    assert (case/'ORDER.TXT').read_bytes()==expected_order,((case/'ORDER.TXT').read_bytes(),expected_order)
    assert (case/'REORDER.TXT').read_bytes()==expected_order
    assert (case/'REVERSE.TXT').read_bytes()==b''.join(n+b'\r\n' for n in reversed(ordered))
    ext_names=[n.upper().encode('cp866') for n in [DOC,*EXTENSIONS]]
    ext_names.sort(key=lambda n:bytes(weights[b] for b in n.split(b'.')[1]))
    assert (case/'EXTORD.TXT').read_bytes()==b''.join(n+b'\r\n' for n in ext_names)
    assert (case/'ONE.TXT').read_bytes()==b''.join(n.upper().encode('cp866')+b'\r\n' for n in NAMES[:6])
    assert (case/'WILD.TXT').read_bytes()==b''.join((STEM+s+'.txt').upper().encode('cp866')+b'\r\n' for s in ('','1','2'))
    print('PASS: Russian filenames '+profile,flush=True)
    return {'profile':profile,'phases':phases,'create_commands':first,'reboot_commands':second,
            'directory_sha256':hashlib.sha256((case/'directory.bin').read_bytes()).hexdigest(),
            'nested_sha256':hashlib.sha256((case/'nested.bin').read_bytes()).hexdigest(),
            'expected_order_hex':expected_order.hex()}


def main():
    base=Path(os.environ.get('FLOPPY_IMAGE',ROOT/'out/floppy.img'));core=verify_base(base)
    work=Path(tempfile.mkdtemp(prefix='ru-files-',dir=ROOT/'out'));print('Russian filesystem artifacts:',work,flush=True)
    r={'status':'running','core_sha256':core,'cases':[]}
    def save():(work/'results.json').write_text(json.dumps(r,indent=2)+'\n')
    save()
    try:
        for profile in CONFIG:r['cases'].append(run_case(work,base,profile));save()
    except Exception as error:r['status']='failed';r['failure']=str(error);save();raise
    r['status']='selected-cases-passed';save()


if __name__=='__main__':main()
