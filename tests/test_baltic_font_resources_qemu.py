#!/usr/bin/env python3
"""Reject missing/malformed CP775 fonts and recover prepared display state."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

from ru_profiles import CONFIG, verify_base, require_profile
from test_baltic_country_qemu import ROOT, LANGUAGES, compile_probes, command
from test_ru_cpi import parse_cpi


def mutations(original):
    def patch(offset, value, fmt='<I'):
        data = bytearray(original)
        struct.pack_into(fmt, data, offset, value)
        return bytes(data)
    return {
        'missing': None,
        'empty': b'',
        'signature': b'X'+original[1:],
        'file-header': original[:22],
        'entry-header': original[:52],
        'font-header': original[:58],
        'glyph-header': original[:64],
        'glyph-body': original[:4096],
        # The CPI carries attribution text after its actual font payload.
        'last-row': original[:struct.unpack_from('<I', original, 27)[0]-1],
        'directory-pointer': patch(19, len(original)+256),
        'font-pointer': patch(49, len(original)+256),
        'unsupported-page': patch(41, 9999, '<H'),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--language', choices=list(LANGUAGES), action='append')
    parser.add_argument('--profile', choices=list(CONFIG), action='append')
    parser.add_argument('--case', action='append')
    parser.add_argument('--height', type=int, choices=[8,14,16], default=16)
    args = parser.parse_args()
    base = Path(os.environ.get('FLOPPY_IMAGE', ROOT/'out/floppy.img'))
    core = verify_base(base)
    work = Path(tempfile.mkdtemp(prefix='baltic-font-resources-', dir=ROOT/'out'))
    print(f'Baltic font resource artifacts: {work}', flush=True)
    compile_probes(work)
    command('nasm', '-f', 'bin', '-DPAGE=775', f'-DHEIGHT={args.height}', '-DDUMP_ONLY',
            str(ROOT/'tests/ru_font_probe.asm'), '-o', str(work/'FONT.COM'))
    command('nasm', '-f', 'bin', '-DPAGE=775', f'-DHEIGHT={args.height}', '-DDUMP_ONLY', '-DINACTIVE_DISPLAY',
            str(ROOT/'tests/ru_font_probe.asm'), '-o', str(work/'BADFONT.COM'))
    command('nasm', '-f', 'bin', f'-DHEIGHT={args.height}', '-DSETUP_ONLY',
            str(ROOT/'tests/ru_font_probe.asm'), '-o', str(work/'SETH.COM'))
    original = (ROOT/'src/DEV/DISPLAY/EGA/EGA775.CPI').read_bytes()
    expected = parse_cpi(original, 775)[args.height]
    selected = {k:v for k,v in mutations(original).items() if not args.case or k in args.case}
    assert selected, 'no resource cases selected'
    report = {'status':'running', 'core_sha256':core, 'height':args.height, 'cases':[]}
    def save():
        (work/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    save()
    try:
        for language in args.language or LANGUAGES:
            for memory in args.profile or CONFIG:
                folder = work/(language+'-'+memory); folder.mkdir()
                image = folder/'boot.img'; shutil.copyfile(base, image)
                def put(name, data):
                    command('mcopy','-o','-i',str(image),'-','::'+name,input=data)
                for probe in work.glob('*.COM'):
                    put(probe.name, probe.read_bytes())
                for source, name in [('DEV/COUNTRY/COUNTRY.SYS','COUNTRY.SYS'),
                                     ('DEV/DISPLAY/DISPLAY.SYS','DISPLAY.SYS'),
                                     ('DEV/DISPLAY/EGA/EGA775.CPI','EGA775.CPI'),
                                     ('CMD/MODE/MODE.COM','MODE.COM'),
                                     ('CMD/NLSFUNC/NLSFUNC.EXE','NLSFUNC.EXE')]:
                    put(name,(ROOT/'src'/source).read_bytes())
                config = f'COUNTRY={LANGUAGES[language]},775,COUNTRY.SYS\r\n'+CONFIG[memory]
                config += 'DEVICE=DISPLAY.SYS CON=(EGA,437,(1,3))\r\n'
                actions = ['@ECHO OFF','CTTY AUX']
                def accept(action):
                    actions.extend([action,'IF ERRORLEVEL 1 GOTO FAIL'])
                def snapshot(name, inactive=False):
                    if not inactive:
                        accept('CPCHK.COM')
                    accept(f'P{LANGUAGES[language]}775.COM')
                    accept('BADFONT.COM' if inactive else 'FONT.COM')
                    accept('COPY FONT.BIN '+name+' >NUL')
                accept(memory.upper()+'.COM');accept('NLSFUNC');accept('SETH.COM')
                accept('MODE CON CP PREPARE=((775) EGA775.CPI)')
                accept('MODE CON CP SELECT=775');snapshot('BEFORE.BIN')
                variants = []
                for index,(name,data) in enumerate(selected.items()):
                    filename = f'BAD{index:02d}.CPI'
                    if data is not None:
                        put(filename,data);(folder/filename).write_bytes(data)
                    actions += [f'ECHO FONT_REJECT_{index:02d}',
                                f'MODE CON CP PREPARE=((775) {filename})',
                                'IF NOT ERRORLEVEL 1 GOTO FAIL']
                    if data is not None:
                        actions += ['MODE CON CP SELECT=775','IF NOT ERRORLEVEL 1 GOTO FAIL']
                    snapshot(f'F{index:02d}.BIN', inactive=data is not None)
                    accept('MODE CON CP PREPARE=((775) EGA775.CPI)')
                    accept('MODE CON CP SELECT=775');snapshot(f'R{index:02d}.BIN')
                    variants.append({'name':name,'filename':filename,'size':len(data) if data is not None else None,
                                     'sha256':hashlib.sha256(data).hexdigest() if data is not None else None,
                                     'display_after_rejection':'inactive' if data is not None else '775'})
                accept(memory.upper()+'.COM')
                actions += ['ECHO BALTIC_FONT_RESOURCES_DONE','QEXIT.COM',':FAIL','ECHO BALTIC_FONT_RESOURCE_FAIL','QEXIT.COM']
                for name,data in [('CONFIG.SYS',config),('AUTOEXEC.BAT','\r\n'.join(actions)+'\r\n')]:
                    put(name,data.encode('ascii'));(folder/name).write_bytes(data.encode('ascii'))
                log=folder/'serial.log'
                with log.open('wb') as output:
                    result=subprocess.run([os.environ.get('QEMU','qemu-system-i386'),'-display','none','-m','8',
                         '-drive',f'if=floppy,format=raw,file={image}','-boot','a','-serial','stdio','-monitor','none',
                         '-no-reboot','-device','isa-debug-exit,iobase=0xf4,iosize=0x04'],
                         stdin=subprocess.DEVNULL,stdout=output,stderr=subprocess.STDOUT,timeout=90)
                output=log.read_bytes()
                assert result.returncode==33 and b'BALTIC_FONT_RESOURCES_DONE' in output and b'BALTIC_FONT_RESOURCE_FAIL' not in output,(log,output)
                require_profile(output,memory)
                snapshots = ['BEFORE.BIN']+[f'{prefix}{i:02d}.BIN' for i in range(len(variants)) for prefix in ('F','R')]
                hashes={}
                for name in snapshots:
                    data=command('mtype','-i',str(image),'::'+name).stdout
                    assert len(data)==8192 and all(data[b*32:b*32+args.height]==expected[b] for b in range(256)),(folder,name)
                    (folder/name).write_bytes(data);hashes[name]=hashlib.sha256(data).hexdigest()
                assert len(set(hashes.values()))==1,(folder,'font plane changed')
                for marker in (b'RU_FONT_PASS',b'RU_COUNTRY_PASS'):
                    assert output.count(marker)==len(snapshots),(folder,marker)
                assert output.count(b'RU_CODEPAGE_PASS')==len(snapshots)-sum(v['display_after_rejection']=='inactive' for v in variants)
                report['cases'].append({'language':language,'profile':memory,'emulator_exit':result.returncode,
                    'mutations':variants,'snapshots':hashes,'config':config,'actions':actions,
                    'log':str(log.relative_to(work)),'log_sha256':hashlib.sha256(output).hexdigest()})
                save();print('PASS:',folder.name,flush=True)
    except Exception as error:
        report.update(status='failed',failure=str(error));save();raise
    report['status']='passed';save()


if __name__ == '__main__':
    main()
