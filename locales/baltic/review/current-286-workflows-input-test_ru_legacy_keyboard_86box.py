#!/usr/bin/env python3
"""Physical RU input through AT 84-key or XT 83-key keyboards and real IBM BIOS."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time

from test_ru_keyboard_qemu import steps, modifier_steps
from test_ru_country_qemu import compile_probes

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from memory_release import selected_core


def legacy_steps():
    """Keep the byte oracle; use only physical keys present on an 84-key AT."""
    result = []
    def tap(key):
        return [(key,True),(key,False)]
    for item in steps()+modifier_steps():
        # The old keyboard has no right Alt/Ctrl; left Ctrl+Alt covers third shift.
        if any(key in ('alt_r','ctrl_r') for key,down in item['keys']):
            continue
        item = dict(item)
        events = []
        for key,down in item['keys']:
            pad = {'up':'kp_8','left':'kp_4','delete':'kp_decimal'}.get(key)
            if pad:
                # There is no separate navigation cluster. Restore Num Lock.
                if down:
                    events += tap('num_lock')+tap(pad)+tap('num_lock')
            else:
                events.append((key,down))
        item['keys'] = events
        result.append(item)
    return result


class VNCKeyboard:
    """RFB 3.8 physical key events, sent to a private local 86Box server."""
    KEYS = {'alt':0xffe9,'shift':0xffe1,'shift_r':0xffe2,'ctrl':0xffe3,
            'caps_lock':0xffe5,'num_lock':0xff7f,'esc':0xff1b,'ret':0xff0d,
            'backspace':0xff08,'tab':0xff09,'spc':32,'f1':0xffbe,
            'kp_1':0xffb1,'kp_8':0xffb8,'kp_4':0xffb4,'kp_decimal':0xff9f,  # XK_KP_Delete maps to physical scan 53h.
            'kp_add':0xffab,'kp_subtract':0xffad}
    KEYS.update({name:ord(char) for name,char in [('bracket_left','['),('bracket_right',']'),
        ('semicolon',';'),('apostrophe',"'"),('grave_accent','`'),('comma',','),
        ('dot','.'),('slash','/'),('backslash','\\'),('minus','-'),('equal','=')]})

    def __init__(self, proc):
        self.socket = None
        deadline = time.monotonic()+30
        while time.monotonic()<deadline and proc.poll() is None:
            try:
                self.socket=socket.create_connection(('127.0.0.1',5900),timeout=1)
                break
            except OSError:
                time.sleep(.1)
        if self.socket is None:
            raise RuntimeError('86Box VNC server did not start; use a VNC-enabled backend')
        self.socket.settimeout(10)
        try:
            assert self.receive(12)==b'RFB 003.008\n'
            self.socket.sendall(b'RFB 003.008\n')
            count=self.receive(1)[0]
            assert 1 in self.receive(count), 'VNC requires unsupported authentication'
            self.socket.sendall(b'\x01')
            assert self.receive(4)==b'\0'*4
            self.socket.sendall(b'\x01')
            header=self.receive(24)
            self.width,self.height=struct.unpack('>HH',header[:4])
            self.pixel_format=header[4:20]
            self.title=self.receive(struct.unpack('>I',header[20:24])[0]).decode(errors='replace')
        except BaseException:
            self.close()
            raise

    def receive(self,count):
        data=b''
        while len(data)<count:
            chunk=self.socket.recv(count-len(data))
            if not chunk:
                raise RuntimeError('VNC connection closed')
            data+=chunk
        return data

    def send(self,events):
        for key,down in events:
            value=ord(key) if len(key)==1 else self.KEYS[key]
            self.socket.sendall(struct.pack('>BBHI',4,int(down),0,value))
            # Release modifiers before the probe checks them two BIOS ticks later.
            time.sleep(.01)

    def close(self):
        if self.socket:
            self.socket.close()
            self.socket=None


def prepare_lifecycle(case, kind, put):
    """Probe resident state across rejected loads and RU/GR/RU reloads."""
    cases=[]
    actions=[]
    phase_count=0
    def tap(*keys):
        return [(key,True) for key in keys]+[(key,False) for key in reversed(keys)]
    def phase(label, values):
        nonlocal phase_count
        start=len(cases)
        cases.extend({'name':label+' '+name,'keys':keys,'bios_ax':value}
                     for name,keys,value in values)
        (case/'expected.bin').write_bytes(b''.join(struct.pack('<H',s['bios_ax']) for s in cases[start:]))
        name=f'L{phase_count}.COM'
        subprocess.run(['nasm','-f','bin',f'-DSTART_INDEX={start}',
                        *(['-DDOS_INPUT'] if kind=='dos' else []),
                        str(ROOT/'tests/ru_keyboard_probe.asm'),'-o',str(case/name)],cwd=case,check=True)
        put(name,(case/name).read_bytes())
        actions.append((name,False))
        phase_count+=1
    latin=('Latin',tap('alt','shift')+tap('q'),0x1071)
    russian=('Russian',tap('alt','shift_r')+tap('q'),0xa9)
    phase('initial', [('Latin',tap('q'),0x1071),russian])
    library=(ROOT/'src/DEV/KEYBOARD/KEYBRD2.SYS').read_bytes()
    put('BADSIG.SYS',bytes([0])+library[1:])
    put('SHORT.SYS',library[:20])
    rejected=[('missing','KEYB RU,866,MISSING.SYS'),
              ('bad signature','KEYB RU,866,BADSIG.SYS'),
              ('short header','KEYB RU,866,SHORT.SYS'),
              ('unsupported page','KEYB RU,855,KEYBRD2.SYS'),
              ('unsupported ID','KEYB RU,866,KEYBRD2.SYS /ID:999'),
              ('unsupported layout','KEYB ZZ,866,KEYBRD2.SYS')]
    for label,command in rejected:
        actions.extend([(command,True),('TYPECHK.COM',False)])
        phase(label,[('preserved Russian',tap('q'),0xa9),latin,russian])
    put('KEYBOARD.SYS',(ROOT/'src/DEV/KEYBOARD/KEYBOARD.SYS').read_bytes())
    actions.extend([('KEYB GR,437,KEYBOARD.SYS',False),('TYPECHK.COM',False)])
    phase('German',[('y becomes z',tap('y'),0x157a),('z becomes y',tap('z'),0x2c79)])
    actions.extend([('KEYB RU,866,KEYBRD2.SYS /ID:441',False),('TYPECHK.COM',False)])
    phase('reloaded RU',[('initial Latin',tap('q'),0x1071),russian,latin])
    return cases,actions,phase_count


def run_case(work, args, core, kind, locale=None):
    case=work/kind
    case.mkdir()
    image=case/'test.img'
    subprocess.run(['bash','-c','source "$1/tests/86box_286_lib.sh"\nmake_86box_286_boot_image "$2" "$1"',
                    'bash',str(ROOT),str(image)],check=True,stdout=subprocess.DEVNULL)
    if args.machine=='xt83':
        # Reformat the private template for the XT BIOS's 360 KiB geometry.
        boot=case/'boot.bin'
        boot.write_bytes(image.read_bytes()[:512])
        initial={name:subprocess.check_output(['mtype','-i',str(image),'::'+name])
                 for name in ('IO.SYS','MSDOS.SYS','COMMAND.COM','SYSMENU.OVL')}
        image.unlink()
        subprocess.run(['mformat','-C','-f','360','-B',str(boot),'-i',str(image),'::'],check=True)
        for name,data in initial.items():
            subprocess.run(['mcopy','-i',str(image),'-','::'+name],input=data,check=True)
        subprocess.run(['python3',str(ROOT/'tests/compact_fat_root.py'),str(image)],check=True)
    def put(name,data):
        subprocess.run(['mcopy','-o','-i',str(image),'-','::'+name],input=data,check=True)
    def copy(name,path):
        put(name,path.read_bytes())
    for name in ('IO.SYS','MSDOS.SYS','COMMAND.COM'):
        data=subprocess.check_output(['mtype','-i',str(image),'::'+name])
        assert data==core[name],name
    page = locale['page'] if locale else 866
    country = locale['country'] if locale else 7
    country_probe = locale['country_probe'] if locale else 'P866.COM'
    selection = locale['selection'] if locale else 'RU,866,KEYBRD2.SYS /ID:441'
    (locale['compile_probes'] if locale else compile_probes)(case)
    cases=locale['steps'](kind) if locale else legacy_steps()
    (case/'expected.bin').write_bytes(b''.join(struct.pack('<H',step['bios_ax']) for step in cases))
    subprocess.run(['nasm','-f','bin',*(['-DDOS_INPUT'] if kind=='dos' else []),
                    str(ROOT/'tests/ru_keyboard_probe.asm'),'-o',str(case/'PROBE.COM')],cwd=case,check=True)
    for source,target in [('86box_exit.asm','BXEXIT.COM'),('ru_legacy_keyboard_type.asm','TYPECHK.COM')]:
        subprocess.run(['nasm','-f','bin',*(['-DXT83'] if args.machine=='xt83' else []),str(ROOT/'tests'/source),'-o',str(case/target)],check=True)
    for name in (country_probe,'CPCHK.COM','PROBE.COM','BXEXIT.COM','TYPECHK.COM'):
        copy(name,case/name)
    for source,name in [('DEV/COUNTRY/COUNTRY.SYS','COUNTRY.SYS'),('CMD/KEYB/KEYB.COM','KEYB.COM'),
                         ('DEV/KEYBOARD/KEYBRD2.SYS','KEYBRD2.SYS'),('CMD/NLSFUNC/NLSFUNC.EXE','NLSFUNC.EXE'),
                         ('DEV/DISPLAY/DISPLAY.SYS','DISPLAY.SYS'),(f'DEV/DISPLAY/EGA/EGA{page}.CPI',f'EGA{page}.CPI'),
                         ('CMD/MODE/MODE.COM','MODE.COM')]:
        copy(name,ROOT/'src'/source)
    put('CONFIG.SYS',f'COUNTRY={country:03d},{page},COUNTRY.SYS\r\nDOS=LOW\r\nDEVICE=DISPLAY.SYS CON=(EGA,437,(1,3))\r\nNUMLOCK=ON\r\n'.encode('ascii'))
    actions=[country_probe,'NLSFUNC',f'MODE CON CP PREPARE=(({page}) EGA{page}.CPI)',f'MODE CON CP SELECT={page}',
             'KEYB '+selection,'TYPECHK.COM','CPCHK.COM',country_probe,'PROBE.COM']
    actions=[(action,False) for action in actions]
    probe_passes=type_passes=1
    if args.suite=='lifecycle':
        assert locale is None, 'Baltic lifecycle requires its own phase oracle'
        cases,extra,probe_passes=prepare_lifecycle(case,kind,put)
        actions=actions[:-1]+extra
        type_passes=9
    batch=['@ECHO OFF','CTTY AUX']
    for action,rejected in actions:
        batch += ['ECHO RUN '+action,action,
                  'IF '+('NOT ' if rejected else '')+'ERRORLEVEL 1 GOTO FAIL']
    batch += ['ECHO RU_LEGACY_KEY_DONE','BXEXIT.COM',':FAIL','ECHO RU_LEGACY_KEY_FAIL','BXEXIT.COM FAIL']
    put('AUTOEXEC.BAT',('\r\n'.join(batch)+'\r\n').encode())
    config=(ROOT/'tests/86box/ibmat-286.cfg').read_text().replace('qt_software','vnc')
    config=config.replace('gfxcard = cga','gfxcard = vga').replace('size = 2048','size = 512')
    config=config.replace('[Other peripherals]','[Other peripherals]\nunittester_enabled = 1')
    config+='\n[AT Keyboard]\nkeys = 1\n'
    if args.machine=='xt83':
        config=(ROOT/'tests/86box/ibmxt-ru.cfg').read_text()
    (case/'startup.cfg').write_text(config)
    (case/'86box.cfg').write_text(config)
    shutil.copyfile(ROOT/'tests/86box/global.cfg',case/'global.cfg')
    if args.machine=='at84':
        subprocess.run(['python3',str(ROOT/'tests/seed_86box_ibmat_nvram.py'),str(case/'nvr/ibm5170_111585.nvr'),
                        '--display','vga','--extended-kib','512'],check=True)
    # Refuse to connect to an unrelated server already using the backend port.
    with socket.socket() as check:
        # A previous case can leave TIME_WAIT sockets after a clean exit.
        check.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        check.bind(('127.0.0.1',5900))
    env=dict(os.environ)
    if args.qt_platform:
        env['QT_QPA_PLATFORM']=args.qt_platform
    log=case/'serial.log'
    with log.open('wb') as output:
        proc=subprocess.Popen([str(args.emulator.resolve()),'-N','-O',str(case/'global.cfg'),'-P',str(case),
                               '-R',str(args.roms.resolve()),'-I','a:'+str(image)],env=env,
                              stdin=subprocess.DEVNULL,stdout=output,stderr=subprocess.STDOUT)
        vnc=None
        try:
            vnc=VNCKeyboard(proc)
            assert case.name in vnc.title, vnc.title
            reconnect_at=time.monotonic()+10
            startup_reconnects=0
            for index,step in enumerate(cases):
                deadline=time.monotonic()+(180 if index==0 else 20)
                marker=f'RU_KEY_READY {index:04X}'.encode()
                while marker not in log.read_bytes():
                    if proc.poll() is not None:
                        raise AssertionError(f'guest stopped at {step}: {log}')
                    if time.monotonic()>deadline:
                        raise AssertionError(f'input timeout at {step}: {log}')
                    if index==0 and time.monotonic()>=reconnect_at and b'RUN ' not in log.read_bytes():
                        # 86Box can accept the first VNC client during hard-reset
                        # initialization, then pause after that client's resume.
                        # Reconnect before any input; never extend the deadline.
                        vnc.close()
                        time.sleep(.1)
                        vnc=VNCKeyboard(proc)
                        assert case.name in vnc.title, vnc.title
                        startup_reconnects+=1
                        reconnect_at=time.monotonic()+10
                    time.sleep(.02)
                vnc.send(step['keys'])
            status=proc.wait(timeout=30)
        finally:
            if vnc:
                vnc.close()
            if proc.poll() is None:
                proc.kill()
                proc.wait()
    data=log.read_bytes()
    assert status==0 and b'RU_LEGACY_KEY_DONE' in data and b'FAIL' not in data,log
    for marker,count in [(b'RU_COUNTRY_PASS',2),(b'RU_CODEPAGE_PASS',1),
                         (f'RU_{args.machine.upper()}_TYPE_PASS'.encode(),type_passes),
                         (b'RU_KEY_PASS',probe_passes)]:
        assert data.count(marker)==count,(marker,log)
    assert data.count(b'RU_KEY_READY')==len(cases)
    print(f'PASS: {args.machine.upper()} {kind}, {len(cases)} physical reads',flush=True)
    return {'input':kind,'emulator_exit':status,'reads':len(cases),'steps':cases,'probe_passes':probe_passes,'type_passes':type_passes,
            'actions':actions,'startup_reconnects':startup_reconnects,
            'log':str(log.relative_to(work)),'log_sha256':hashlib.sha256(data).hexdigest(),
            'config_sha256':hashlib.sha256(config.encode()).hexdigest()}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emulator',type=Path,required=True,help='VNC-enabled 86Box with loopback-only listeners')
    parser.add_argument('--roms',type=Path,required=True)
    parser.add_argument('--qt-platform')
    parser.add_argument('--machine',choices=('at84','xt83'),default='at84')
    parser.add_argument('--suite',choices=('physical','lifecycle'),default='physical')
    parser.add_argument('--input',choices=('bios','dos'),action='append')
    args=parser.parse_args()
    core=selected_core()
    if not core:
        parser.error('MEMORY_CORE_DIR must select the production core')
    work=Path(tempfile.mkdtemp(prefix='ru-legacy-keyboard-',dir=ROOT/'out'))
    print(f'Russian legacy keyboard artifacts: {work}',flush=True)
    report={'status':'running','machine':args.machine,'suite':args.suite,'core_sha256':{name:hashlib.sha256(data).hexdigest() for name,data in core.items()},
            'emulator_sha256':hashlib.sha256(args.emulator.read_bytes()).hexdigest(),'cases':[]}
    def save():
        (work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    save()
    try:
        for kind in args.input or ('bios','dos'):
            report['cases'].append(run_case(work,args,core,kind))
            save()
    except Exception as error:
        report['status']='failed'
        report['failure']=str(error)
        save()
        raise
    report['status']='selected-cases-passed'
    save()


if __name__=='__main__':
    main()
