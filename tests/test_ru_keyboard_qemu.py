#!/usr/bin/env python3
"""Physical QMP keyboard input, independent BIOS byte oracle, private media."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import time

from screen_expect import QMPConnection

ROOT = Path(__file__).resolve().parents[1]


def command(*args, **kwargs):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)


def steps():
    cases = []
    def add(name, keys, value):
        cases.append({'name': name, 'keys': keys, 'bios_ax': value})
    def tap(*keys):
        return [(key, True) for key in keys] + [(key, False) for key in reversed(keys)]
    add('initial Latin', tap('q'), 0x1071)
    for switch, value in [('shift_r', 0xa9), ('shift_r', 0xa9), ('shift', 0x1071), ('shift', 0x1071)]:
        add('Alt then '+switch, tap('alt', switch)+tap('q'), value)
    for switch, value in [('shift_r', 0xa9), ('shift', 0x1071), ('shift_r', 0xa9)]:
        add(switch+' then Alt', tap(switch, 'alt')+tap('q'), value)
    # Unicode JCUKEN rows specified independently of the assembled CP866 bytes.
    rows = [('q w e r t y u i o p bracket_left bracket_right', [0x439,0x446,0x443,0x43a,0x435,0x43d,0x433,0x448,0x449,0x437,0x445,0x44a]),
            ('a s d f g h j k l semicolon apostrophe', [0x444,0x44b,0x432,0x430,0x43f,0x440,0x43e,0x43b,0x434,0x436,0x44d]),
            ('z x c v b n m comma dot', [0x44f,0x447,0x441,0x43c,0x438,0x442,0x44c,0x431,0x44e]),
            ('grave_accent', [0x451])]
    for caps in (False, True):
        prefix = tap('caps_lock') if caps else []
        for shift in (False, True):
            for keys, letters in rows:
                for key, code in zip(keys.split(), letters):
                    char = chr(code)
                    if caps != shift:
                        char = char.upper()
                    add(f'caps={caps} shift={shift} {key}', prefix+tap(*(['shift'] if shift else []),key), char.encode('cp866')[0])
                    prefix=[]
    add('caps off',tap('caps_lock')+tap('q'),0xa9)
    for key,scan in [('q',0x10),('a',0x1e),('z',0x2c)]:
        add('Ctrl '+key,tap('ctrl',key),(scan<<8)|(ord(key)-96))
    punctuation = [('slash',0x35,46,44),('3',4,51,252),('4',5,52,59),
                   ('6',7,54,58),('7',8,55,63),('backslash',0x2b,92,47)]
    for key,scan,lower,upper in punctuation:
        add('punctuation '+key,tap(key),(scan<<8)|lower)
        add('shift punctuation '+key,tap('shift',key),(scan<<8)|upper)
    third = [('2',3,64),('3',4,35),('4',5,253),('6',7,94),('7',8,38),
             ('8',9,36),('bracket_left',0x1a,91),('bracket_right',0x1b,93),
             ('backslash',0x2b,124),('comma',0x33,60),('dot',0x34,62),('slash',0x35,47)]
    for modifiers in [('alt_r',),('ctrl','alt')]:
        for key,scan,byte in third:
            add('third shift '+str(modifiers)+' '+key,tap(*modifiers,key),(scan<<8)|byte)
    for key,value in [('esc',0x011b),('ret',0x1c0d),('backspace',0x0e08),
                      ('tab',0x0f09),('spc',0x3920),('f1',0x3b00),('up',0x4800),
                      ('left',0x4b00),('delete',0x5300)]:
        add('control/navigation '+key,tap(key),value)
    add('right Shift alphabet',tap('shift_r','q'),0x89)
    for key,value in [('kp_1',0x4f31),('kp_add',0x4e2b),('kp_subtract',0x4a2d)]:
        add('numeric keypad '+key,tap(key),value)
    add('keypad navigation',tap('num_lock')+tap('kp_1'),0x4f00)
    add('keypad numeric restored',tap('num_lock')+tap('kp_1'),0x4f31)
    add('return Latin',tap('alt','shift')+tap('q'),0x1071)
    return cases



def modifier_steps():
    """Independent physical-key expectations for modifier priority and release."""
    cases=[]
    def tap(*keys):
        return [(key,True) for key in keys]+[(key,False) for key in reversed(keys)]
    def add(name,keys,value):
        cases.append({'name':name,'keys':keys,'bios_ax':value})
    add('select Russian',tap('alt','shift_r')+tap('q'),0xa9)
    add('both Shifts count as Shift',tap('shift','shift_r','q'),0x89)
    add('Caps enabled',tap('caps_lock')+tap('q'),0x89)
    add('Caps with both Shifts',tap('shift','shift_r','q'),0xa9)
    # Caps changes letters only; these DOS punctuation facts are in the contract.
    for key,scan,lower,upper in [('slash',0x35,46,44),('3',4,51,252),
                               ('4',5,52,59),('6',7,54,58),('7',8,55,63),
                               ('backslash',0x2b,92,47)]:
        add('Caps punctuation '+key,tap(key),(scan<<8)|lower)
        add('Caps shifted punctuation '+key,tap('shift_r',key),(scan<<8)|upper)
    # Ctrl codes follow US physical letter positions regardless of Caps/Shift.
    for modifier in ['ctrl','ctrl_r']:
        for key,scan,control in [('q',0x10,17),('a',0x1e,1),('z',0x2c,26)]:
            add('Caps '+modifier+' '+key,tap(modifier,key),(scan<<8)|control)
            add('Caps Shift '+modifier+' '+key,tap('shift_r',modifier,key),(scan<<8)|control)
    add('Caps disabled',tap('caps_lock')+tap('q'),0xa9)
    for modifiers in [('alt',),('alt_r',),('ctrl','alt')]:
        add('Alt-letter BIOS passthrough '+str(modifiers),tap(*modifiers,'q'),0x1000)
    # Right Shift keeps Russian selected. Third shift outranks ordinary Shift.
    for modifiers in [('alt_r','shift_r'),('ctrl','alt','shift_r'),
                      ('ctrl_r','alt','shift_r'),('ctrl','alt_r','shift_r')]:
        for key,scan,value in [('3',4,35),('4',5,253),('slash',0x35,47)]:
            add('third shift priority '+str(modifiers)+' '+key,tap(*modifiers,key),(scan<<8)|value)
    # A modifier make selects the language; releasing it cannot change selection.
    for keys,value in [(('alt','shift_r','shift'),0x1071),
                       (('alt','shift','shift_r'),0xa9),
                       (('shift','shift_r','alt'),0xa9),
                       (('shift_r','shift','alt'),0xa9),
                       (('alt_r','shift'),0x1071),
                       (('alt_r','shift_r'),0xa9)]:
        add('selection precedence '+str(keys),tap(*keys)+tap('q'),value)
    add('ordinary Russian after releases',tap('q'),0xa9)
    add('return Latin',tap('alt','shift')+tap('q'),0x1071)
    add('Latin Caps',tap('caps_lock')+tap('q'),0x1051)
    add('Latin Caps Shift',tap('shift_r','q'),0x1071)
    add('Latin Caps off',tap('caps_lock')+tap('q'),0x1071)
    return cases


def run_case(work, base, name, corrupt=False, dos=False, reload=False, reject=None, recipe=False, cases=None, library_source=None, keyb_selection=None, country=7, enhanced=False, expected_failure=None):
    directory=work/name
    directory.mkdir()
    cases=steps() if cases is None else cases
    if reload:
        def tap(*keys):
            return [(key,True) for key in keys]+[(key,False) for key in reversed(keys)]
        cases=[{'name':label,'keys':events,'bios_ax':value} for label,events,value in [
            ('initial RU Latin',tap('q'),0x1071),
            ('RU national',tap('alt','shift_r')+tap('q'),0xa9),
            ('GR y is z',tap('y'),0x157a),
            ('GR z is y',tap('z'),0x2c79),
            ('reloaded RU Latin',tap('q'),0x1071),
            ('reloaded RU national',tap('alt','shift_r')+tap('q'),0xa9),
            ('reloaded RU Latin selection',tap('alt','shift')+tap('q'),0x1071)]]
    if reject:
        cases=[{'name':'initial Latin','keys':[('q',True),('q',False)],'bios_ax':0x1071},
               {'name':'select Russian','keys':[('alt',True),('shift_r',True),('shift_r',False),('alt',False),('q',True),('q',False)],'bios_ax':0xa9},
               {'name':'Russian after rejected load','keys':[('q',True),('q',False)],'bios_ax':0xa9}]
    (directory/'expected.bin').write_bytes(b''.join(struct.pack('<H',s['bios_ax']) for s in cases))
    command('nasm','-f','bin',*(['-DDOS_INPUT'] if dos else []),*(['-DENHANCED_INPUT'] if enhanced else []),str(ROOT/'tests/ru_keyboard_probe.asm'),'-o',str(directory/'PROBE.COM'),cwd=directory)
    if reload or reject:
        phases = [(0,2,'PROBE.COM'),(2,4,'GPROBE.COM'),(4,7,'RPROBE.COM')] if reload else [(0,2,'PROBE.COM'),(2,3,'RPROBE.COM')]
        for start,end,program in phases:
            (directory/'expected.bin').write_bytes(b''.join(struct.pack('<H',s['bios_ax']) for s in cases[start:end]))
            command('nasm','-f','bin',f'-DSTART_INDEX={start}',str(ROOT/'tests/ru_keyboard_probe.asm'),'-o',str(directory/program),cwd=directory)
    command('nasm','-f','bin',str(ROOT/'tests/qemu_exit.asm'),'-o',str(directory/'QEXIT.COM'))
    library=Path(library_source) if library_source else ROOT/'src/DEV/KEYBOARD/KEYBRD2.SYS'
    if corrupt:
        data=bytearray(library.read_bytes())
        data[data.index(b'\x29\xf1')+1]=0xf0
        library=directory/'KEYBRD2.SYS'
        library.write_bytes(data)
    image=directory/'boot.img'
    shutil.copyfile(base,image)
    for source,target in [(directory/'PROBE.COM','PROBE.COM'),(directory/'QEXIT.COM','QEXIT.COM'),
                          (library,'KEYBRD2.SYS'),(ROOT/'src/CMD/KEYB/KEYB.COM','KEYB.COM')]:
        command('mcopy','-o','-i',str(image),str(source),'::'+target)
    if reload:
        for program in ('GPROBE.COM','RPROBE.COM'):
            command('mcopy','-o','-i',str(image),str(directory/program),'::'+program)
        command('mcopy','-o','-i',str(image),str(ROOT/'src/DEV/KEYBOARD/KEYBOARD.SYS'),'::KEYBOARD.SYS')
    if reject:
        command('mcopy','-o','-i',str(image),str(directory/'RPROBE.COM'),'::RPROBE.COM')
        bad=bytearray(library.read_bytes())
        if reject=='bad-signature':
            bad[0]=0
        elif reject=='short-header':
            bad=bad[:20]
        (directory/'BAD.SYS').write_bytes(bad)
        command('mcopy','-o','-i',str(image),str(directory/'BAD.SYS'),'::BAD.SYS')
    batch='@ECHO OFF\r\nCTTY AUX\r\nKEYB RU,866,KEYBRD2.SYS /ID:441\r\nIF ERRORLEVEL 1 GOTO FAIL\r\nKEYB\r\nPROBE\r\nIF ERRORLEVEL 1 GOTO FAIL\r\nECHO RU_KEY_DONE\r\nQEXIT\r\n:FAIL\r\nECHO RU_CASE_FAIL\r\nQEXIT\r\n'
    if reload:
        batch=batch.replace('ECHO RU_KEY_DONE',
            'KEYB GR,437,KEYBOARD.SYS\r\nIF ERRORLEVEL 1 GOTO FAIL\r\nGPROBE\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
            'KEYB RU,866,KEYBRD2.SYS /ID:441\r\nIF ERRORLEVEL 1 GOTO FAIL\r\nRPROBE\r\nIF ERRORLEVEL 1 GOTO FAIL\r\nECHO RU_KEY_DONE')
    if reject:
        rejected_command={
            'missing':'KEYB RU,866,MISSING.SYS',
            'bad-signature':'KEYB RU,866,BAD.SYS',
            'short-header':'KEYB RU,866,BAD.SYS',
            'unsupported-page':'KEYB RU,855,KEYBRD2.SYS',
            'unsupported-id':'KEYB RU,866,KEYBRD2.SYS /ID:999',
            'unsupported-layout':'KEYB ZZ,866,KEYBRD2.SYS',
        }[reject]
        batch=batch.replace('ECHO RU_KEY_DONE', rejected_command+'\r\nIF NOT ERRORLEVEL 1 GOTO FAIL\r\n'
            'KEYB\r\nRPROBE\r\nIF ERRORLEVEL 1 GOTO FAIL\r\nECHO RU_KEY_DONE')
    if keyb_selection:
        batch=batch.replace('KEYB RU,866,KEYBRD2.SYS /ID:441', 'KEYB '+keyb_selection)
    config=f'COUNTRY={country:03d},{775 if keyb_selection else 866},COUNTRY.SYS\r\nNUMLOCK=ON\r\n'
    if keyb_selection:
        command('mcopy','-o','-i',str(image),str(ROOT/'src/DEV/COUNTRY/COUNTRY.SYS'),'::COUNTRY.SYS')
    if recipe:
        # Execute the installed document's actual lines, adapting only its
        # C:\DOS directory to this private floppy's root. Installed-disk
        # boot qualification is separate.
        doc=(ROOT/'locales/ru/RUSSIAN.TXT').read_text()
        def section(name):
            return doc.split('['+name+']\n',1)[1].split('[END]',1)[0].replace('C:\\DOS\\','').splitlines()
        config='\r\n'.join(section('CONFIG'))+'\r\nNUMLOCK=ON\r\n'
        actions=[]
        for line in section('AUTOEXEC'):
            actions.extend([line,'IF ERRORLEVEL 1 GOTO FAIL'])
        batch=batch.replace('KEYB RU,866,KEYBRD2.SYS /ID:441', '\r\n'.join(actions))
        command('nasm','-f','bin',str(ROOT/'tests/ru_codepage_probe.asm'),'-o',str(directory/'CPCHK.COM'))
        for source,target in [(ROOT/'src/DEV/DISPLAY/EGA/EGA866.CPI','EGA866.CPI'),
                              (ROOT/'src/DEV/DISPLAY/DISPLAY.SYS','DISPLAY.SYS'),
                              (ROOT/'src/CMD/MODE/MODE.COM','MODE.COM'),
                              (ROOT/'src/CMD/NLSFUNC/NLSFUNC.EXE','NLSFUNC.EXE'),
                              (directory/'CPCHK.COM','CPCHK.COM')]:
            command('mcopy','-o','-i',str(image),str(source),'::'+target)
        batch=batch.replace('ECHO RU_KEY_DONE','CPCHK\r\nIF ERRORLEVEL 1 GOTO FAIL\r\nECHO RU_KEY_DONE')
    for target,data in [('CONFIG.SYS',config),('AUTOEXEC.BAT',batch)]:
        command('mcopy','-o','-i',str(image),'-','::'+target,input=data.encode())
    log=directory/'serial.log'
    with tempfile.TemporaryDirectory(prefix='ruk-') as sockets, log.open('wb') as output:
        proc=subprocess.Popen([os.environ.get('QEMU','qemu-system-i386'),'-display','none','-m','4',
            '-drive',f'if=floppy,format=raw,file={image}','-boot','a','-serial','stdio',
            '-qmp',f'unix:{sockets}/q,server=on,wait=off','-no-reboot',
            '-device','isa-debug-exit,iobase=0xf4,iosize=0x04'],stdin=subprocess.DEVNULL,stdout=output,stderr=subprocess.STDOUT)
        qmp=None
        try:
            qmp=QMPConnection(sockets+'/q')
            for index,case in enumerate(cases):
                marker=f'RU_KEY_READY {index:04X}\r\n'.encode()
                deadline=time.monotonic()+15
                while marker not in log.read_bytes():
                    if proc.poll() is not None:
                        break
                    if time.monotonic()>deadline:
                        raise AssertionError(f'timeout at {case}: {log}')
                    time.sleep(.01)
                if proc.poll() is not None:
                    break
                # Separate events preserve physical modifier order and key releases.
                for key,down in case['keys']:
                    qmp._send({'execute':'input-send-event','arguments':{'events':[{'type':'key','data':{'down':down,'key':{'type':'qcode','data':key}}}]}})
                    result=qmp._recv_response()
                    if 'error' in result:
                        raise AssertionError(result)
                    time.sleep(.005)
            result=proc.wait(timeout=15)
        finally:
            if qmp:
                qmp.close()
            if proc.poll() is None:
                proc.kill()
                proc.wait()
    output=log.read_bytes()
    assert result==33,(result,log)
    if expected_failure is not None:
        assert expected_failure in output and b'RU_KEY_DONE' not in output, (log,output)
    elif corrupt:
        assert b'RU_KEY_FAIL actual=00F0' in output and b'RU_KEY_DONE' not in output, (log,output)
    else:
        assert b'RU_KEY_DONE' in output and b'RU_KEY_PASS' in output and b'FAIL' not in output,(log,output)
    if recipe:
        assert b'RU_CODEPAGE_PASS' in output,(log,output)
    print(f'PASS: {name}',flush=True)
    return {'name':name,'enhanced_bios_input':enhanced,'negative_control':corrupt or expected_failure is not None,'dos_input':dos,'reload_existing':reload,'rejection':reject,'documented_recipe':recipe,'emulator_exit':result,'steps':cases,
            'completed_reads':output.count(b'RU_KEY_READY'),'log':str(log.relative_to(work)),
            'log_sha256':hashlib.sha256(output).hexdigest()}


def main():
    selections = {'physical':{},'dos-input':{'dos':True},'wrong-yo':{'corrupt':True},
                  'reload-existing':{'reload':True},'documented-recipe':{'recipe':True},
                  'modifier-edges':{'cases':modifier_steps()},
                  'modifier-edges-dos':{'cases':modifier_steps(),'dos':True}}
    selections.update({'reject-'+name:{'reject':name} for name in
        ('missing','bad-signature','short-header','unsupported-page','unsupported-id','unsupported-layout')})
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case',choices=list(selections),action='append')
    args=parser.parse_args()
    work=Path(tempfile.mkdtemp(prefix='ru-keyboard-',dir=ROOT/'out'))
    print(f'Russian keyboard artifacts: {work}',flush=True)
    base=Path(os.environ.get('FLOPPY_IMAGE',ROOT/'out/floppy.img'))
    report={'status':'running','cases':[]}
    def save():
        (work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    save()
    try:
        for name in args.case or selections:
            report['cases'].append(run_case(work,base,name,**selections[name]))
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
