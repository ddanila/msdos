#!/usr/bin/env python3
"""Cyrillic 8.3 operations, DOS wildcard/order rules and fresh-boot persistence."""
import argparse
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
TREE='\u0438\u0441\u0442\u043e\u043a'
MOVED='\u043f\u0435\u0440\u0435\u043d\u043e\u0441'
CLONE='\u043a\u043e\u043f\u0438\u044f'
EMPTY='\u043f\u0443\u0441\u0442\u043e'
PAYLOAD='\u0434\u0430\u043d\u043d\u044b\u0435 \u0401\u0451'


def short_name(name,encoding='cp866'):
    parts=name.upper().encode(encoding).split(b'.')
    raw=parts[0].ljust(8,b' ')+(parts[1] if len(parts)>1 else b'').ljust(3,b' ')
    # A live FAT short name beginning with byte E5 is stored with byte 05.
    return b'\x05'+raw[1:] if raw[0]==0xe5 else raw


class FAT:
    def __init__(self,image,offset=0):
        self.data=image.read_bytes()[offset:];b=self.data
        sectors=int.from_bytes(b[19:21],'little') or int.from_bytes(b[32:36],'little')
        volume_size=sectors*int.from_bytes(b[11:13],'little')
        assert 0<volume_size<=len(b)
        self.data=b[:volume_size];b=self.data
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


def run_case(work,base,profile,args,core,locale=None,installed=None):
    encoding=locale['encoding'] if locale else 'cp866'
    fields='DIR SUB MAIN COPY RENAMED DOC STEM NAMES EXTENSIONS TREE MOVED CLONE EMPTY PAYLOAD'.split()
    DIR,SUB,MAIN,COPY,RENAMED,DOC,STEM,NAMES,EXTENSIONS,TREE,MOVED,CLONE,EMPTY,PAYLOAD=[
        locale[key] if locale else globals()[key] for key in fields]
    temporary=locale['temporary'] if locale else '\u0432\u0440\u0435\u043c'
    short=lambda name:short_name(name,encoding)
    case=work/profile;case.mkdir();image=case/'test.img'
    assert not (installed and args.emulator), 'installed workflows use QEMU'
    if args.emulator:
        subprocess.run(['bash','-c','source "$1/tests/86box_286_lib.sh"\nmake_86box_286_boot_image "$2" "$1"',
                        'bash',str(ROOT),str(image)],check=True,stdout=subprocess.DEVNULL)
    else:
        shutil.copyfile(installed['image'] if installed else base,image)
    partition=f'{image}@@{installed["offset"]}' if installed else str(image)
    def read(name):return subprocess.check_output(['mtype','-i',partition,'::'+name])
    def put(name,data):subprocess.run(['mcopy','-o','-i',partition,'-','::'+name],input=data,check=True)
    for name in ('IO.SYS','MSDOS.SYS','COMMAND.COM'):
        data=read(name)
        assert hashlib.sha256(data).hexdigest()==core[name],name
    for name in ('MOVE','XCOPY'):
        data=(ROOT/f'src/CMD/{name}/{name}.EXE').read_bytes()
        if installed:assert read('DOS/'+name+'.EXE')==data,name
        else:put(name+'.EXE',data)
    country=(ROOT/'src/DEV/COUNTRY/COUNTRY.SYS').read_bytes()
    if installed:assert read('DOS/COUNTRY.SYS')==country
    else:put('COUNTRY.SYS',country)
    if args.emulator:
        config=(ROOT/'tests/86box/ibmat-286.cfg').read_text().replace('size = 2048','size = 512')
        config=config.replace('[Other peripherals]','[Other peripherals]\nunittester_enabled = 1')
        (case/'startup.cfg').write_text(config);(case/'86box.cfg').write_text(config)
        shutil.copyfile(ROOT/'tests/86box/global.cfg',case/'global.cfg')
        subprocess.run(['python3',str(ROOT/'tests/seed_86box_ibmat_nvram.py'),str(case/'nvr/ibm5170_111585.nvr'),'--extended-kib','512'],check=True)
    for source,name,defines in [('ru_profile_probe.asm','PROFILE.COM',[f'-DHIGH={int(profile=="high")}']),('86box_exit.asm' if args.emulator else 'qemu_exit.asm','QEXIT.COM',[])]:
        subprocess.run(['nasm','-f','bin',*defines,str(ROOT/'tests'/source),'-o',str(case/name)],check=True);put(name,(case/name).read_bytes())
    if installed:assert read('CONFIG.SYS')==installed['config']
    else:put('CONFIG.SYS',(f'COUNTRY={locale["country"] if locale else 7:03d},{775 if locale else 866},COUNTRY.SYS\r\n'+CONFIG[profile]).encode())
    def batch(actions,end):
        lines=['@ECHO OFF','CTTY AUX','PROFILE.COM','IF ERRORLEVEL 1 GOTO FAIL']
        if installed:
            lines=['@ECHO OFF','CTTY AUX','C:','CD \\','PATH C:\\DOS']
            for action in [*installed['recipe'],'C:\\PROFILE.COM']:
                lines += [action,'IF ERRORLEVEL 1 GOTO FAIL']
        for action in actions:lines += [action,'IF ERRORLEVEL 1 GOTO FAIL']
        lines += ['ECHO '+end,'QEXIT.COM',':FAIL','ECHO RU_FILES_FAIL','QEXIT.COM']
        return ('\r\n'.join(lines)+'\r\n').encode(encoding)
    first=[f'MD {DIR}',f'CD {DIR.upper()}',f'ECHO {PAYLOAD}>{MAIN}',
           f'TYPE {MAIN.upper()} > A:\\LOOKUP.TXT',f'COPY {MAIN} {COPY} >NUL',
           f'REN {COPY.upper()} {RENAMED}',f'TYPE {RENAMED.upper()} > A:\\RENAMED.TXT',
           f'DEL {RENAMED.upper()}',f'MD {SUB}',f'COPY {MAIN.upper()} {SUB}\\{DOC} >NUL',
           f'TYPE {SUB.upper()}\\{DOC.upper()} > A:\\NESTED.TXT',
           f'MD {temporary}',f'RD {temporary.upper()}']
    first += [f'ECHO {PAYLOAD}>{SUB}\\{name}' for name in EXTENSIONS]
    first += [f'ECHO {PAYLOAD}>{name}' for name in NAMES]
    first += [f'DIR /B /A:-D /O:E {SUB}\\*.* > A:\\EXTORD.TXT',
              'DIR /B /O:-N *.TXT > A:\\REVERSE.TXT','DIR /B /O:N *.TXT > A:\\ORDER.TXT','DIR /B ?.TXT > A:\\ONE.TXT',
              f'DIR /B {STEM}?.TXT > A:\\WILD.TXT','CD \\',
              f'MD {TREE}',f'MD {TREE}\\{SUB}',f'MD {TREE}\\{EMPTY}',
              f'ECHO {PAYLOAD}>{TREE}\\{SUB}\\{DOC}',f'A:\\MOVE {TREE.upper()} {MOVED}',
              f'MD {CLONE}',f'A:\\XCOPY {MOVED.upper()} {CLONE.upper()} /S /E >NUL',
              'ECHO CREATED>STAGE.TAG']
    second=[f'CD {DIR.upper()}',f'TYPE {MAIN.upper()} > A:\\REBOOT.TXT',
            f'TYPE {SUB.upper()}\\{DOC.upper()} > A:\\REBNEST.TXT',
            'DIR /B /O:N *.TXT > A:\\REORDER.TXT',f'DEL {SUB.upper()}\\{DOC.upper()}',
            f'DEL {SUB.upper()}\\EXT.*',f'RD {SUB.upper()}','DEL *.TXT','CD \\',f'RD {DIR.upper()}']
    for index,name in enumerate((MOVED,CLONE),1):
        second += [f'TYPE {name.upper()}\\{SUB.upper()}\\{DOC.upper()} > A:\\TREE{index}.TXT',
                   f'DEL {name.upper()}\\{SUB.upper()}\\{DOC.upper()}',
                   f'RD {name.upper()}\\{SUB.upper()}',f'RD {name.upper()}\\{EMPTY.upper()}',f'RD {name.upper()}']
    if installed:
        def installed_command(command):
            return command.replace('A:\\MOVE ', 'C:\\DOS\\MOVE.EXE ').replace('A:\\XCOPY ', 'C:\\DOS\\XCOPY.EXE ').replace('A:\\', 'C:\\')
        first=[installed_command(command) for command in first]
        second=[installed_command(command) for command in second]
    put('AUTOEXEC.BAT',b'@ECHO OFF\r\nIF EXIST STAGE.TAG GOTO SECOND\r\n'+batch(first,'RU_FILES_CREATED')+b':SECOND\r\nNEXT.BAT\r\n')
    put('NEXT.BAT',batch(second,'RU_FILES_REBOOTED'))
    phases=[]
    for phase,marker in [('create',b'RU_FILES_CREATED'),('reboot',b'RU_FILES_REBOOTED')]:
        log=case/(phase+'.log')
        env=dict(os.environ)
        if args.qt_platform:env['QT_QPA_PLATFORM']=args.qt_platform
        command=([str(args.emulator.resolve()),'-N','-O',str(case/'global.cfg'),'-P',str(case),
                  '-R',str(args.roms.resolve()),'-I','a:'+str(image)] if args.emulator else
                 ['qemu-system-i386','-display','none','-m','8',
                  '-drive',f'if={"ide,index=0" if installed else "floppy"},format=raw,file={image},cache=writethrough',
                  '-boot','c' if installed else 'a','-serial','stdio',
                  '-monitor','none','-no-reboot','-device','isa-debug-exit,iobase=0xf4,iosize=0x04'])
        with log.open('wb') as output:
            result=subprocess.run(command,env=env,stdin=subprocess.DEVNULL,stdout=output,
                                  stderr=subprocess.STDOUT,timeout=240 if args.emulator else 30)
        data=log.read_bytes();assert result.returncode==(0 if args.emulator else 33) and marker in data and b'RU_FILES_FAIL' not in data,(phase,log)
        require_profile(data,profile);fat=FAT(image,installed['offset'] if installed else 0);root=fat.entries();payload=(PAYLOAD+'\r\n').encode(encoding)
        if phase=='create':
            entry=root[short(DIR)];assert entry[11]&16
            directory=fat.entries(int.from_bytes(entry[26:28],'little'))
            expected={short(n) for n in [MAIN,*NAMES]}
            actual={n for n,e in directory.items() if not e[11]&16}
            assert actual==expected,(actual,expected)
            for n in expected:assert fat.read(directory[n])==payload,n
            nested=fat.entries(int.from_bytes(directory[short(SUB)][26:28],'little'))
            assert fat.read(nested[short(DOC)])==payload
            for n in EXTENSIONS:assert fat.read(nested[short(n)])==payload
            assert short(RENAMED) not in directory and short(COPY) not in directory
            assert short(temporary) not in directory
            raw=b''.join(directory.values());(case/'directory.bin').write_bytes(raw)
            (case/'nested.bin').write_bytes(b''.join(nested.values()))
            assert short(TREE) not in root
            for name in (MOVED,CLONE):
                tree_entry=root[short(name)];assert tree_entry[11]&16
                tree_cluster=int.from_bytes(tree_entry[26:28],'little')
                tree=fat.entries(tree_cluster)
                assert set(tree)=={b'.          ',b'..         ',short(SUB),short(EMPTY)},tree
                assert int.from_bytes(tree[b'..         '][26:28],'little')==0
                for child in (SUB,EMPTY):
                    entry=tree[short(child)];assert entry[11]&16
                    children=fat.entries(int.from_bytes(entry[26:28],'little'))
                    assert int.from_bytes(children[b'..         '][26:28],'little')==tree_cluster
                    expected_children={b'.          ',b'..         '}
                    if child==SUB:
                        expected_children.add(short(DOC));assert fat.read(children[short(DOC)])==payload
                    assert set(children)==expected_children,children
                    (case/(name.encode(encoding).hex()+'-'+child.encode(encoding).hex()+'.bin')).write_bytes(b''.join(children.values()))
                (case/(name.encode(encoding).hex()+'.bin')).write_bytes(b''.join(tree.values()))
            checks=['LOOKUP.TXT','RENAMED.TXT','NESTED.TXT']
        else:
            assert all(short(n) not in root for n in (DIR,TREE,MOVED,CLONE));checks=['REBOOT.TXT','REBNEST.TXT','TREE1.TXT','TREE2.TXT']
        files={}
        for n in checks:
            value=fat.read(root[short(n)]);assert value==payload,(n,value);files[n]=value.hex()
        for n in (['ORDER.TXT','ONE.TXT','WILD.TXT','REVERSE.TXT','EXTORD.TXT'] if phase=='create' else ['REORDER.TXT']):
            value=fat.read(root[short(n)]);(case/n).write_bytes(value);files[n]=value.hex()
        phases.append({'phase':phase,'emulator_exit':result.returncode,'files_hex':files,
                       'log_sha256':hashlib.sha256(data).hexdigest(),'image_sha256':hashlib.sha256(image.read_bytes()).hexdigest()})
    weights=locale['weights'] if locale else bytes.fromhex(json.loads((ROOT/'locales/ru/dos622-reference.json').read_text())['country_records']['866']['objects']['6']['payload'])
    names=[n.upper().encode(encoding) for n in [MAIN,*NAMES]]
    ordered=sorted(names,key=lambda name:bytes(weights[b] for b in name))
    expected_order=b''.join(n+b'\r\n' for n in ordered)
    assert (case/'ORDER.TXT').read_bytes()==expected_order,((case/'ORDER.TXT').read_bytes(),expected_order)
    assert (case/'REORDER.TXT').read_bytes()==expected_order
    assert (case/'REVERSE.TXT').read_bytes()==b''.join(n+b'\r\n' for n in reversed(ordered))
    ext_names=[n.upper().encode(encoding) for n in [DOC,*EXTENSIONS]]
    ext_names.sort(key=lambda n:bytes(weights[b] for b in n.split(b'.')[1]))
    assert (case/'EXTORD.TXT').read_bytes()==b''.join(n+b'\r\n' for n in ext_names)
    assert (case/'ONE.TXT').read_bytes()==b''.join(n.upper().encode(encoding)+b'\r\n' for n in NAMES[:len(NAMES)-4])
    assert (case/'WILD.TXT').read_bytes()==b''.join((STEM+s+'.txt').upper().encode(encoding)+b'\r\n' for s in ('','1','2'))
    print('PASS: '+(locale['language'] if locale else 'Russian')+' filenames '+profile,flush=True)
    return {'profile':profile,'phases':phases,'create_commands':first,'reboot_commands':second,
            'directory_sha256':hashlib.sha256((case/'directory.bin').read_bytes()).hexdigest(),
            'nested_sha256':hashlib.sha256((case/'nested.bin').read_bytes()).hexdigest(),
            'expected_order_hex':expected_order.hex()}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emulator',type=Path,help='Select real-BIOS IBM AT 286 testing')
    parser.add_argument('--roms',type=Path);parser.add_argument('--qt-platform')
    args=parser.parse_args()
    if args.emulator and not args.roms:parser.error('--roms is required with --emulator')
    base=Path(os.environ.get('FLOPPY_IMAGE',ROOT/'out/floppy.img'));core=verify_base(base)
    work=Path(tempfile.mkdtemp(prefix='ru-files-',dir=ROOT/'out'));print('Russian filesystem artifacts:',work,flush=True)
    r={'status':'running','core_sha256':core,'backend':'86box-286' if args.emulator else 'qemu','cases':[]}
    if args.emulator:r['emulator_sha256']=hashlib.sha256(args.emulator.read_bytes()).hexdigest()
    def save():(work/'results.json').write_text(json.dumps(r,indent=2)+'\n')
    save()
    try:
        for profile in (['low'] if args.emulator else CONFIG):r['cases'].append(run_case(work,base,profile,args,core));save()
    except Exception as error:r['status']='failed';r['failure']=str(error);save();raise
    r['status']='selected-cases-passed';save()


if __name__=='__main__':main()
