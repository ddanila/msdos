#!/usr/bin/env python3
"""Physical Russian shell/EDLIN editing, reload, pipes and saved-byte checks."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

from screen_expect import QMPConnection
from ru_profiles import CONFIG, verify_base, require_profile

ROOT=Path(__file__).resolve().parents[1]
SAMPLE='\u041f\u0440\u0438\u0432\u0435\u0442 \u043c\u0438\u0440 \u0401\u0451 DOS'
SECOND='\u0422\u0435\u043a\u0441\u0442'
RUSSIAN={chr(code):key for keys,codes in [
 ('q w e r t y u i o p bracket_left bracket_right',[0x439,0x446,0x443,0x43a,0x435,0x43d,0x433,0x448,0x449,0x437,0x445,0x44a]),
 ('a s d f g h j k l semicolon apostrophe',[0x444,0x44b,0x432,0x430,0x43f,0x440,0x43e,0x43b,0x434,0x436,0x44d]),
 ('z x c v b n m comma dot grave_accent',[0x44f,0x447,0x441,0x43c,0x438,0x442,0x44c,0x431,0x44e,0x451])]
 for key,code in zip(keys.split(),codes)}


def run_case(work,base,profile):
    case=work/profile;case.mkdir();image=case/'test.img';shutil.copyfile(base,image)
    def put(name,data):subprocess.run(['mcopy','-o','-i',str(image),'-','::'+name],input=data,check=True)
    for source,name in [('CMD/EDLIN/EDLIN.COM','EDLIN.COM'),('CMD/FIND/FIND.EXE','FIND.EXE')]:
        put(name,(ROOT/'src'/source).read_bytes())
    for source,name,defines in [('ru_profile_probe.asm','PROFILE.COM',[f'-DHIGH={int(profile=="high")}']),
                                ('qemu_exit.asm','QEXIT.COM',[])]:
        subprocess.run(['nasm','-f','bin',*defines,str(ROOT/'tests'/source),'-o',str(case/name)],check=True)
        put(name,(case/name).read_bytes())
    put('CONFIG.SYS',('COUNTRY=007,866,COUNTRY.SYS\r\n'+CONFIG[profile]+
                     'DEVICE=DISPLAY.SYS CON=(EGA,437,(1,3))\r\n').encode())
    actions=['PROFILE.COM > AUX','NLSFUNC','MODE CON CP PREPARE=((866) EGA866.CPI)',
             'MODE CON CP SELECT=866','KEYB RU,866,KEYBRD2.SYS /ID:441']
    batch=['@ECHO OFF']
    for action in actions:batch += [action,'IF ERRORLEVEL 1 GOTO FAIL']
    batch += ['ECHO RU_TEXT_READY > AUX','GOTO END',':FAIL','ECHO RU_TEXT_FAIL > AUX','QEXIT.COM',':END']
    put('AUTOEXEC.BAT',('\r\n'.join(batch)+'\r\n').encode())
    log=case/'serial.log';events=[];captures=[]
    with tempfile.TemporaryDirectory(prefix='rut-') as sockets,log.open('wb') as output:
        proc=subprocess.Popen(['qemu-system-i386','-display','none','-m','8',
            '-drive',f'if=floppy,format=raw,file={image},cache=writethrough','-boot','a','-serial','stdio',
            '-qmp',f'unix:{sockets}/q,server=on,wait=off','-no-reboot',
            '-device','isa-debug-exit,iobase=0xf4,iosize=0x04'],stdin=subprocess.DEVNULL,stdout=output,stderr=subprocess.STDOUT)
        qmp=None
        try:
            qmp=QMPConnection(sockets+'/q');national=False
            def wait(marker):
                deadline=time.monotonic()+30
                while marker not in log.read_bytes():
                    assert proc.poll() is None and time.monotonic()<deadline,(marker,log)
                    time.sleep(.03)
            def tap(*keys):
                sequence=[(k,True) for k in keys]+[(k,False) for k in reversed(keys)]
                events.extend(sequence)
                for key,down in sequence:
                    qmp._send({'execute':'input-send-event','arguments':{'events':[{'type':'key','data':{'down':down,'key':{'type':'qcode','data':key}}}]}})
                    assert 'error' not in qmp._recv_response()
                    time.sleep(.01)
            def text(value):
                nonlocal national
                for char in value:
                    lower=char.lower();ru=lower in RUSSIAN
                    if char!=' ' and ru!=national:
                        tap('alt','shift_r' if ru else 'shift');national=ru
                    if ru:
                        tap(*(['shift'] if char!=lower else []),RUSSIAN[lower])
                    elif char.isalpha():tap(*(['shift'] if char!=lower else []),lower)
                    elif char.isdigit():tap(char)
                    else:
                        plain={' ':'spc','.':'dot',',':'comma','/':'slash','-':'minus'}
                        shifted={'_':'minus','>':'dot','|':'backslash','"':'apostrophe',':':'semicolon'}
                        if char in plain:tap(plain[char])
                        else:tap('shift',shifted[char])
            def line(value):text(value);tap('ret');time.sleep(.25)
            def checkpoint(name):line('echo '+name+' >aux');wait(name.encode())
            def capture(name,expected):
                path=case/(name+'.bin');qmp.human_cmd(f'pmemsave 0xb8000 4000 "{path}"')
                data=path.read_bytes();chars=data[::2]
                for value in expected:assert value.encode('cp866') in chars,(name,value,chars)
                qmp.human_cmd(f'screendump "{case/(name+".ppm")}"')
                captures.append({'name':name,'vram_sha256':hashlib.sha256(data).hexdigest(),
                                 'screen_sha256':hashlib.sha256((case/(name+'.ppm')).read_bytes()).hexdigest()})
            wait(b'RU_TEXT_READY')
            text('echo '+SAMPLE+'x');tap('backspace');line('>shell.txt');checkpoint('SHELL_SAVED')
            line('cls');line('type shell.txt');checkpoint('SHELL_SHOWN');capture('shell',[SAMPLE])
            line('cls');line('edlin edit.txt');line('i');line('\u041f\u0440\u0438\u0432\u0435\u0442');line('\u043e\u0448\u0438\u0431\u043a\u0430');tap('ctrl','z');tap('ret');time.sleep(.25)
            line('1');line(SAMPLE);line('2');line(SECOND);line('1,2l');capture('edited',[SAMPLE,SECOND]);line('e');checkpoint('EDITOR_SAVED')
            line('cls');line('edlin edit.txt');line('1,2l');capture('reopened',[SAMPLE,SECOND]);line('q');line('y');checkpoint('EDITOR_REOPENED')
            line('type edit.txt >copy.txt');checkpoint('REDIRECTED')
            line('type edit.txt | find "'+SECOND+'" >pipe.txt');checkpoint('PIPED')
            checkpoint('RU_TEXT_DONE');text('qexit.com')
            events.append(('ret',True))
            qmp._send({'execute':'input-send-event','arguments':{'events':[{'type':'key','data':{'down':True,'key':{'type':'qcode','data':'ret'}}}]}})
            status=proc.wait(timeout=15)
        finally:
            if qmp:qmp.close()
            if proc.poll() is None:proc.kill();proc.wait()
    data=log.read_bytes();assert status==33 and b'RU_TEXT_DONE' in data and b'RU_TEXT_FAIL' not in data,(status,log)
    require_profile(data,profile)
    files={}
    for name in ['SHELL.TXT','EDIT.TXT','COPY.TXT','PIPE.TXT']:
        value=subprocess.check_output(['mtype','-i',str(image),'::'+name]);(case/name).write_bytes(value);files[name]=value.hex()
    expected=(SAMPLE+'\r\n'+SECOND+'\r\n').encode('cp866')
    assert bytes.fromhex(files['SHELL.TXT'])==(SAMPLE+'\r\n').encode('cp866'),files
    assert bytes.fromhex(files['EDIT.TXT'])==expected+b'\x1a',files
    assert bytes.fromhex(files['COPY.TXT'])==expected,files
    assert bytes.fromhex(files['PIPE.TXT'])==(SECOND+'\r\n').encode('cp866'),files
    print('PASS: Russian text workflow '+profile,flush=True)
    return {'profile':profile,'emulator_exit':status,'files_hex':files,'events':events,'captures':captures,
            'serial_sha256':hashlib.sha256(data).hexdigest()}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--profile',choices=('high','low'),action='append');args=parser.parse_args()
    base=Path(os.environ.get('FLOPPY_IMAGE',ROOT/'out/floppy.img'));core=verify_base(base)
    work=Path(tempfile.mkdtemp(prefix='ru-text-',dir=ROOT/'out'));print('Russian text artifacts:',work,flush=True)
    r={'status':'running','core_sha256':core,'cases':[]}
    def save():(work/'results.json').write_text(json.dumps(r,indent=2)+'\n')
    save()
    try:
        for profile in args.profile or CONFIG:r['cases'].append(run_case(work,base,profile));save()
    except Exception as error:r['status']='failed';r['failure']=str(error);save();raise
    r['status']='selected-cases-passed';save()


if __name__=='__main__':main()
