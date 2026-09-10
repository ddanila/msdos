#!/usr/bin/env python3
"""VGA font-plane bytes and rendered pixels on real IBM AT BIOS and a 286."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile

from PIL import Image
from test_ru_display_qemu import existing_font
from test_ru_cpi import CPI, parse_cpi, check_glyphs

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from memory_release import selected_core


def verify_grid(screen,plane,height,line_graphics_start=0xc0):
    """Check glyph pixels and VGA's ninth-column line-graphics replication."""
    assert screen.width%80==0 and screen.width//80 in (8,9),screen.size
    cell=screen.width//80
    for byte in range(256):
        x=(byte%16)*3*cell;y=(4+byte//16)*height
        for row in range(height):
            mask=plane[byte*32+row]
            for bit in range(cell):
                expected=bool(mask & (128>>bit)) if bit<8 else (line_graphics_start<=byte<=0xdf and bool(mask&1))
                ink=screen.getpixel((x+bit,y+row))!=(0,0,0)
                assert ink==expected,('rendered glyph',byte,row,bit)
    return 256*height*cell


def run_case(work,args,core,page,height,expected,corrupt,
             cpi_source=None,corrupt_slot=0xf1,country=7,country_page=866):
    name=f'{page}-{height}'+('-corrupt' if corrupt else '')
    case=work/name;case.mkdir();image=case/'test.img'
    subprocess.run(['bash','-c','source "$1/tests/86box_286_lib.sh"\nmake_86box_286_boot_image "$2" "$1"',
                    'bash',str(ROOT),str(image)],check=True,stdout=subprocess.DEVNULL)
    def put(name,data):
        subprocess.run(['mcopy','-o','-i',str(image),'-','::'+name],input=data,check=True)
    for filename in ('IO.SYS','MSDOS.SYS','COMMAND.COM'):
        assert subprocess.check_output(['mtype','-i',str(image),'::'+filename])==core[filename],filename
    for filename,defines in [('SETH.COM',['-DSETUP_ONLY']),('PROBE.COM',[])]:
        subprocess.run(['nasm','-f','bin',f'-I{ROOT}/tests/',f'-DHEIGHT={height}',f'-DPAGE={page}',
                        '-DBOX86',*defines,str(ROOT/'tests/ru_font_probe.asm'),'-o',str(case/filename)],check=True)
        put(filename,(case/filename).read_bytes())
    subprocess.run(['nasm','-f','bin',str(ROOT/'tests/86box_exit.asm'),'-o',str(case/'BXEXIT.COM')],check=True)
    put('BXEXIT.COM',(case/'BXEXIT.COM').read_bytes())
    cpi=bytearray((cpi_source or (CPI if page==866 else CPI.with_name('EGA.CPI'))).read_bytes())
    if corrupt:
        if height!=16:
            raise ValueError('wrong-slot control requires the 16-row font')
        cpi[59+6+corrupt_slot*16]^=0x80
    put('TEST.CPI',cpi)
    for source,target in [('DEV/COUNTRY/COUNTRY.SYS','COUNTRY.SYS'),
                          ('DEV/DISPLAY/DISPLAY.SYS','DISPLAY.SYS'),
                          ('CMD/MODE/MODE.COM','MODE.COM'),('CMD/NLSFUNC/NLSFUNC.EXE','NLSFUNC.EXE')]:
        put(target,(ROOT/'src'/source).read_bytes())
    put('CONFIG.SYS',f'COUNTRY={country:03d},{country_page},COUNTRY.SYS\r\nDOS=LOW\r\nDEVICE=DISPLAY.SYS CON=(EGA,437,(1,3))\r\n'.encode('ascii'))
    actions=['NLSFUNC',f'MODE CON CP PREPARE=(({page}) TEST.CPI)','SETH.COM',
             f'MODE CON CP SELECT={page}','PROBE.COM']
    batch=['@ECHO OFF','CTTY AUX']
    for action in actions:
        batch += ['ECHO RUN '+action,action,'IF ERRORLEVEL 1 GOTO FAIL']
    batch += ['ECHO RU_DISPLAY_DONE','BXEXIT.COM',':FAIL','ECHO RU_DISPLAY_FAIL','BXEXIT.COM FAIL']
    put('AUTOEXEC.BAT',('\r\n'.join(batch)+'\r\n').encode())
    config=(ROOT/'tests/86box/ibmat-286.cfg').read_text()
    config=config.replace('gfxcard = cga','gfxcard = vga').replace('size = 2048','size = 512')
    config=config.replace('[Other peripherals]','[Other peripherals]\nunittester_enabled = 1')
    (case/'startup.cfg').write_text(config);(case/'86box.cfg').write_text(config)
    shutil.copyfile(ROOT/'tests/86box/global.cfg',case/'global.cfg')
    subprocess.run(['python3',str(ROOT/'tests/seed_86box_ibmat_nvram.py'),str(case/'nvr/ibm5170_111585.nvr'),
                    '--display','vga','--extended-kib','512'],check=True)
    env=dict(os.environ)
    if args.qt_platform:env['QT_QPA_PLATFORM']=args.qt_platform
    log=case/'serial.log'
    with log.open('wb') as output:
        result=subprocess.run([str(args.emulator.resolve()),'-N','-O',str(case/'global.cfg'),'-P',str(case),
                               '-R',str(args.roms.resolve()),'-I','a:'+str(image)],env=env,
                              stdin=subprocess.DEVNULL,stdout=output,stderr=subprocess.STDOUT,timeout=300)
    data=log.read_bytes()
    assert result.returncode==0 and b'FAIL' not in data,(result.returncode,log)
    for marker in (b'RU_FONT_READY',b'RU_FONT_PASS',b'RU_DISPLAY_DONE'):
        assert data.count(marker)==1,(marker,log)
    plane=subprocess.check_output(['mtype','-i',str(image),'::FONT.BIN'])
    assert len(plane)==8192
    (case/'font-plane.bin').write_bytes(plane)
    mismatches=[b for b in range(256) if plane[b*32:b*32+height]!=expected[b]]
    assert mismatches==([corrupt_slot] if corrupt else []),(case,mismatches)
    pixels=subprocess.check_output(['mtype','-i',str(image),'::SCREEN.BIN'])
    width,rows=struct.unpack('<HH',pixels[:4]);assert len(pixels)==4+width*rows*3
    screen=Image.frombytes('RGB',(width,rows),pixels[4:],'raw','BGR')
    assert len(screen.getcolors(width*rows) or [])>1,'blank screen'
    verify_grid(screen,plane,height)
    screen.save(case/'screen.png')
    print(f'PASS: 286 display {name}, {width}x{rows}',flush=True)
    return {'name':name,'page':page,'height':height,'negative_control':corrupt,'mismatched_slots':mismatches,
            'emulator_exit':result.returncode,'screen_size':[width,rows],
            'font_plane_sha256':hashlib.sha256(plane).hexdigest(),
            'screen_sha256':hashlib.sha256((case/'screen.png').read_bytes()).hexdigest(),
            'cpi_sha256':hashlib.sha256(cpi).hexdigest(),'config_sha256':hashlib.sha256(config.encode()).hexdigest(),
            'log':str(log.relative_to(work)),'log_sha256':hashlib.sha256(data).hexdigest()}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emulator',type=Path,required=True);parser.add_argument('--roms',type=Path,required=True)
    parser.add_argument('--qt-platform');parser.add_argument('--case',action='append')
    parser.add_argument('--jobs',type=int,choices=(1,2),default=1)
    args=parser.parse_args();core=selected_core()
    if not core:parser.error('MEMORY_CORE_DIR must select the production core')
    fonts=parse_cpi(CPI.read_bytes());check_glyphs(fonts)
    cases=[(866,h,fonts[h],False) for h in (14,8,16)]
    cases += [(p,16,existing_font(p,16),False) for p in (437,850,860,863,865)]
    cases += [(866,16,fonts[16],True)]
    names=[f'{p}-{h}'+('-corrupt' if c else '') for p,h,e,c in cases]
    if args.case and set(args.case)-set(names):parser.error('unknown case; choose '+', '.join(names))
    work=Path(tempfile.mkdtemp(prefix='ru-display-286-',dir=ROOT/'out'))
    print(f'Russian 286 display artifacts: {work}',flush=True)
    report={'status':'running','core_sha256':{n:hashlib.sha256(d).hexdigest() for n,d in core.items()},
            'emulator_sha256':hashlib.sha256(args.emulator.read_bytes()).hexdigest(),'cases':[]}
    def save():(work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    save()
    try:
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futures=[pool.submit(run_case,work,args,core,page,height,expected,corrupt)
                     for name,(page,height,expected,corrupt) in zip(names,cases)
                     if not args.case or name in args.case]
            for future in as_completed(futures):
                try:
                    report['cases'].append(future.result());save()
                except Exception as error:
                    report['status']='failed';report['failure']=str(error);save()
                    print(f'FAIL: {error}',flush=True)
                    for pending in futures:pending.cancel()
                    raise
    except Exception as error:
        report['status']='failed';report['failure']=str(error);save();raise
    report['status']='selected-cases-passed';save()


if __name__=='__main__':main()
