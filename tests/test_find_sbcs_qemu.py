#!/usr/bin/env python3
"""FIND must not cross a line ending in a non-DBCS high byte."""
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


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--find',type=Path,default=ROOT/'src/CMD/FIND/FIND.EXE')
    args=parser.parse_args()
    base=Path(os.environ.get('FLOPPY_IMAGE',ROOT/'out/floppy.img'));core=verify_base(base)
    work=Path(tempfile.mkdtemp(prefix='find-sbcs-',dir=ROOT/'out'));print('FIND SBCS artifacts:',work,flush=True)
    report={'status':'running','core_sha256':core,'find_sha256':hashlib.sha256(args.find.read_bytes()).hexdigest(),'cases':[]}
    def save():(work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    save()
    try:
        for profile in CONFIG:
            folder=work/profile;folder.mkdir();image=folder/'boot.img';shutil.copyfile(base,image)
            def put(name,data):subprocess.run(['mcopy','-o','-i',str(image),'-','::'+name],input=data,check=True)
            for source,target in [(args.find,'FIND.EXE'),(ROOT/'src/DEV/COUNTRY/COUNTRY.SYS','COUNTRY.SYS')]:put(target,source.read_bytes())
            for source,target,flags in [('qemu_exit.asm','QEXIT.COM',[]),('ru_profile_probe.asm','PROFILE.COM',[f'-DHIGH={int(profile=="high")}'])]:
                subprocess.run(['nasm','-f','bin',*flags,str(ROOT/'tests'/source),'-o',str(folder/target)],check=True);put(target,(folder/target).read_bytes())
            batch=[b'@ECHO OFF',b'CTTY AUX',b'PROFILE.COM',b'IF ERRORLEVEL 1 GOTO FAIL'];expected={};inputs={}
            for prefix,needle in [('ASCII',b'needle'),('BALTIC',b'\xe5un')]:
                lines=[b'prefix'+bytes([byte]) for byte in range(128,256)]
                data=b''.join(line+b'\r\n'+needle+b'\r\n' for line in lines)
                put(prefix+'.TXT',data);inputs[prefix+'.TXT']=data.hex()
                for suffix,option,want in [('YES',b'',(needle+b'\r\n')*128),('NO',b'/V ',b''.join(line+b'\r\n' for line in lines))]:
                    # Keep all file names within DOS 8.3.
                    name=('A' if prefix=='ASCII' else 'B')+suffix+'.OUT'
                    batch += [b'FIND '+option+b'"'+needle+b'" <'+prefix.encode()+b'.TXT >'+name.encode(),b'IF ERRORLEVEL 1 GOTO FAIL']
                    expected[name]=want
            batch += [b'PROFILE.COM',b'IF ERRORLEVEL 1 GOTO FAIL',b'ECHO FIND_SBCS_DONE',b'QEXIT.COM',b':FAIL',b'ECHO FIND_SBCS_FAIL',b'QEXIT.COM']
            put('CONFIG.SYS',('COUNTRY=372,775,COUNTRY.SYS\r\n'+CONFIG[profile]).encode())
            put('AUTOEXEC.BAT',b'\r\n'.join(batch)+b'\r\n')
            log=folder/'serial.log'
            with log.open('wb') as out:
                proc=subprocess.run(['qemu-system-i386','-display','none','-m','8','-drive',f'if=floppy,format=raw,file={image}','-boot','a','-serial','stdio','-monitor','none','-no-reboot','-device','isa-debug-exit,iobase=0xf4,iosize=0x04'],stdin=subprocess.DEVNULL,stdout=out,stderr=subprocess.STDOUT,timeout=45)
            output=log.read_bytes();assert proc.returncode==33 and b'FIND_SBCS_DONE' in output and b'FIND_SBCS_FAIL' not in output,(log,output)
            require_profile(output,profile);files={}
            for name,want in expected.items():
                data=subprocess.check_output(['mtype','-i',str(image),'::'+name]);(folder/name).write_bytes(data)
                assert data==want,(folder,name,'line boundary mismatch',len(data),len(want))
                files[name]={'sha256':hashlib.sha256(data).hexdigest(),'size':len(data)}
            report['cases'].append({'profile':profile,'emulator_exit':proc.returncode,'files':files,'inputs_hex':inputs,'log':str(log.relative_to(work)),'log_sha256':hashlib.sha256(output).hexdigest()});save();print('PASS:',profile,flush=True)
    except Exception as error:
        report.update(status='failed',failure=str(error));save();raise
    report['status']='passed';save()


if __name__=='__main__':main()
