#!/usr/bin/env python3
"""Physical Russian shell/EDLIN editing, reload, pipes and saved-byte checks."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time

from ru_vnc_console import VNCConsole
from test_ru_cpi import parse_cpi
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


def screen_contains(screen,value,prompt=False,page=866):
    """Match complete glyph masks against actual pixels, without OCR or VRAM injection."""
    glyphs=parse_cpi((ROOT/f'src/DEV/DISPLAY/EGA/EGA{page}.CPI').read_bytes(),page)[16]
    width,height=screen.size
    if height!=400 or width not in (640,720):return False
    cell=width//80
    pixels=screen.load()
    for row in range(25):
        for col in range(81-len(value)):
            if all(all(bool(any(pixels[(col+i)*cell+x,row*16+y]))==bool(bits & (128>>x))
                       for x in range(8)) for i,byte in enumerate(value.encode(f'cp{page}'))
                       for y,bits in enumerate(glyphs[byte])):
                if not prompt or (col==0 and all(not any(pixels[x,row*16+y])
                    for x in range(3*cell,width) for y in range(16)) and
                    screen.crop((0,(row+1)*16,width,height)).getbbox() is None):return True
    return False


def run_case(work,base,profile,args,core,locale=None):
    page=locale['page'] if locale else 866
    encoding=f'cp{page}'
    sample=locale['sample'] if locale else SAMPLE
    second=locale['second'] if locale else SECOND
    case=work/profile;case.mkdir();image=case/'test.img'
    if args.emulator:
        subprocess.run(['bash','-c','source "$1/tests/86box_286_lib.sh"\nmake_86box_286_boot_image "$2" "$1"',
                        'bash',str(ROOT),str(image)],check=True,stdout=subprocess.DEVNULL)
    else:shutil.copyfile(base,image)
    def put(name,data):subprocess.run(['mcopy','-o','-i',str(image),'-','::'+name],input=data,check=True)
    for name in ('IO.SYS','MSDOS.SYS','COMMAND.COM'):
        assert hashlib.sha256(subprocess.check_output(['mtype','-i',str(image),'::'+name])).hexdigest()==core[name],name
    for source,name in [('CMD/EDLIN/EDLIN.COM','EDLIN.COM'),('CMD/FIND/FIND.EXE','FIND.EXE'),
                        ('DEV/COUNTRY/COUNTRY.SYS','COUNTRY.SYS'),('CMD/KEYB/KEYB.COM','KEYB.COM'),
                        ('DEV/KEYBOARD/KEYBRD2.SYS','KEYBRD2.SYS'),('CMD/NLSFUNC/NLSFUNC.EXE','NLSFUNC.EXE'),
                        ('DEV/DISPLAY/DISPLAY.SYS','DISPLAY.SYS'),(f'DEV/DISPLAY/EGA/EGA{page}.CPI',f'EGA{page}.CPI'),
                        ('CMD/MODE/MODE.COM','MODE.COM')]:
        put(name,(ROOT/'src'/source).read_bytes())
    for source,name,defines in [('ru_profile_probe.asm','PROFILE.COM',[f'-DHIGH={int(profile=="high")}']),
                                ('86box_exit.asm' if args.emulator else 'qemu_exit.asm','QEXIT.COM',[])]:
        subprocess.run(['nasm','-f','bin',*defines,str(ROOT/'tests'/source),'-o',str(case/name)],check=True)
        put(name,(case/name).read_bytes())
    put('CONFIG.SYS',(f'COUNTRY={locale["country"] if locale else 7:03d},{page},COUNTRY.SYS\r\n'+CONFIG[profile]+
                     'DEVICE=DISPLAY.SYS CON=(EGA,437,(1,3))\r\n').encode())
    actions=['PROFILE.COM > AUX','NLSFUNC',f'MODE CON CP PREPARE=(({page}) EGA{page}.CPI)',
             f'MODE CON CP SELECT={page}',locale['keyb'] if locale else 'KEYB RU,866,KEYBRD2.SYS /ID:441']
    batch=['@ECHO OFF']
    for action in actions:batch += [action,'IF ERRORLEVEL 1 GOTO FAIL']
    batch += ['ECHO RU_TEXT_READY > AUX','GOTO END',':FAIL','ECHO RU_TEXT_FAIL > AUX','QEXIT.COM',':END']
    put('AUTOEXEC.BAT',('\r\n'.join(batch)+'\r\n').encode())
    if args.emulator:
        config=(ROOT/'tests/86box/ibmat-286.cfg').read_text().replace('qt_software','vnc')
        config=config.replace('gfxcard = cga','gfxcard = vga').replace('size = 2048','size = 512')
        config=config.replace('[Other peripherals]','[Other peripherals]\nunittester_enabled = 1')
        config+='\n[AT Keyboard]\nkeys = 1\n'
        (case/'startup.cfg').write_text(config);(case/'86box.cfg').write_text(config)
        shutil.copyfile(ROOT/'tests/86box/global.cfg',case/'global.cfg')
        subprocess.run(['python3',str(ROOT/'tests/seed_86box_ibmat_nvram.py'),str(case/'nvr/ibm5170_111585.nvr'),
                        '--display','vga','--extended-kib','512'],check=True)
    log=case/'serial.log';events=[];captures=[]
    with tempfile.TemporaryDirectory(prefix='rut-') as sockets,log.open('wb') as output:
        command=['qemu-system-i386','-display','none','-m','8',
            '-drive',f'if=floppy,format=raw,file={image},cache=writethrough','-boot','a','-serial','stdio',
            '-qmp',f'unix:{sockets}/q,server=on,wait=off','-no-reboot',
            '-device','isa-debug-exit,iobase=0xf4,iosize=0x04']
        if args.emulator:
            with socket.socket() as check:
                check.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
                check.bind(('127.0.0.1',5900))
            command=[str(args.emulator.resolve()),'-N','-O',str(case/'global.cfg'),'-P',str(case),
                     '-R',str(args.roms.resolve()),'-I','a:'+str(image)]
        env=dict(os.environ)
        if args.qt_platform:env['QT_QPA_PLATFORM']=args.qt_platform
        proc=subprocess.Popen(command,env=env,stdin=subprocess.DEVNULL,stdout=output,stderr=subprocess.STDOUT)
        qmp=None
        try:
            qmp=VNCConsole(proc) if args.emulator else QMPConnection(sockets+'/q');national=bool(locale)
            def wait(marker):
                deadline=time.monotonic()+(240 if args.emulator else 30)
                while marker not in log.read_bytes():
                    assert proc.poll() is None and time.monotonic()<deadline,(marker,log)
                    if args.emulator:qmp.capture()
                    time.sleep(.03)
            def tap(*keys):
                sequence=[(k,True) for k in keys]+[(k,False) for k in reversed(keys)]
                events.extend(sequence)
                if args.emulator:
                    qmp.send(sequence);return
                for key,down in sequence:
                    qmp._send({'execute':'input-send-event','arguments':{'events':[{'type':'key','data':{'down':down,'key':{'type':'qcode','data':key}}}]}})
                    assert 'error' not in qmp._recv_response()
                    time.sleep(.01)
            def text(value):
                nonlocal national
                if locale:
                    national=locale['type'](value,tap,national)
                    return
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
            def checkpoint(name):
                if args.emulator:screen_wait(['A>'],prompt=True)
                line('echo '+name+' >aux');wait(name.encode())
                if args.emulator:screen_wait(['A>'],prompt=True)
            def screen_wait(expected,prompt=False):
                deadline=time.monotonic()+30
                while True:
                    screen=qmp.capture()
                    if all(screen_contains(screen,value,prompt,page) for value in expected):return screen
                    assert proc.poll() is None and time.monotonic()<deadline,('screen text missing',expected)
                    screen.save(case/'waiting.png');time.sleep(.1)
            def capture(name,expected):
                if args.emulator:
                    screen=screen_wait(expected);path=case/(name+'.png');screen.save(path)
                    captures.append({'name':name,'screen_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                                     'expected_text':expected,'size':list(screen.size)})
                    return
                path=case/(name+'.bin');qmp.human_cmd(f'pmemsave 0xb8000 4000 "{path}"')
                data=path.read_bytes();chars=data[::2]
                for value in expected:assert value.encode(encoding) in chars,(name,value,chars)
                qmp.human_cmd(f'screendump "{case/(name+".ppm")}"')
                if locale:
                    from PIL import Image
                    screen=Image.open(case/(name+'.ppm'))
                    for value in expected:
                        assert screen_contains(screen,value,page=page),(name,value,'rendered glyph mismatch')
                    screen.save(case/(name+'.png'))
                captures.append({'name':name,'vram_sha256':hashlib.sha256(data).hexdigest(),
                                 'screen_sha256':hashlib.sha256((case/(name+'.ppm')).read_bytes()).hexdigest()})
            wait(b'RU_TEXT_READY')
            text('echo '+sample+'x');tap('backspace');line('>shell.txt');checkpoint('SHELL_SAVED')
            line('cls');line('type shell.txt');checkpoint('SHELL_SHOWN');capture('shell',[sample])
            line('cls');line('edlin edit.txt');
            if args.emulator:screen_wait(['New file'])
            line('i');line(locale['first'] if locale else '\u041f\u0440\u0438\u0432\u0435\u0442');line(locale['error'] if locale else '\u043e\u0448\u0438\u0431\u043a\u0430');tap('ctrl','z');tap('ret');time.sleep(.25)
            line('1');line(sample);line('2');line(second);line('1,2l');capture('edited',[sample,second]);line('e');checkpoint('EDITOR_SAVED')
            line('cls');line('edlin edit.txt');
            if args.emulator:screen_wait(['End of input file'])
            line('1,2l');capture('reopened',[sample,second]);line('q');line('y');checkpoint('EDITOR_REOPENED')
            line('type edit.txt >copy.txt');checkpoint('REDIRECTED')
            line('type edit.txt | find "'+second+'" >pipe.txt');checkpoint('PIPED')
            checkpoint('RU_TEXT_DONE');text('qexit.com')
            events.append(('ret',True))
            if args.emulator:qmp.send([('ret',True)])
            else:qmp._send({'execute':'input-send-event','arguments':{'events':[{'type':'key','data':{'down':True,'key':{'type':'qcode','data':'ret'}}}]}})
            status=proc.wait(timeout=15)
        finally:
            if qmp:qmp.close()
            if proc.poll() is None:proc.kill();proc.wait()
    data=log.read_bytes();assert status==(0 if args.emulator else 33) and b'RU_TEXT_DONE' in data and b'RU_TEXT_FAIL' not in data,(status,log)
    require_profile(data,profile)
    files={}
    for name in ['SHELL.TXT','EDIT.TXT','COPY.TXT','PIPE.TXT']:
        value=subprocess.check_output(['mtype','-i',str(image),'::'+name]);(case/name).write_bytes(value);files[name]=value.hex()
    expected=(sample+'\r\n'+second+'\r\n').encode(encoding)
    assert bytes.fromhex(files['SHELL.TXT'])==(sample+'\r\n').encode(encoding),files
    assert bytes.fromhex(files['EDIT.TXT'])==expected+b'\x1a',files
    assert bytes.fromhex(files['COPY.TXT'])==expected,files
    assert bytes.fromhex(files['PIPE.TXT'])==(second+'\r\n').encode(encoding),files
    print('PASS: '+(locale['language'] if locale else 'Russian')+' text workflow '+profile,flush=True)
    return {'profile':profile,'emulator_exit':status,'files_hex':files,'events':events,'captures':captures,
            'serial_sha256':hashlib.sha256(data).hexdigest()}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--profile',choices=('high','low'),action='append')
    parser.add_argument('--emulator',type=Path);parser.add_argument('--roms',type=Path);parser.add_argument('--qt-platform')
    args=parser.parse_args()
    if args.emulator and not args.roms:parser.error('--roms is required with --emulator')
    if args.emulator and args.profile and args.profile!=['low']:parser.error('286 backend requires LOW')
    base=Path(os.environ.get('FLOPPY_IMAGE',ROOT/'out/floppy.img'));core=verify_base(base)
    work=Path(tempfile.mkdtemp(prefix='ru-text-',dir=ROOT/'out'));print('Russian text artifacts:',work,flush=True)
    r={'status':'running','core_sha256':core,'backend':'86box-286' if args.emulator else 'qemu','cases':[]}
    if args.emulator:r['emulator_sha256']=hashlib.sha256(args.emulator.read_bytes()).hexdigest()
    def save():(work/'results.json').write_text(json.dumps(r,indent=2)+'\n')
    save()
    try:
        for profile in args.profile or (['low'] if args.emulator else CONFIG):r['cases'].append(run_case(work,base,profile,args,core));save()
    except Exception as error:r['status']='failed';r['failure']=str(error);save();raise
    r['status']='selected-cases-passed';save()


if __name__=='__main__':main()
