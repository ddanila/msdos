#!/usr/bin/env python3
"""Fault-inject private variants of a frozen composed memory build."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

from build_bios_low_image import ROOT, build as build_bios
from build_emm_mode_guard import DEFINES
from capture_vc_memory_comparison import image_file
from report_dos_bios_residency import parse_map
from report_emm386_residency import parse_map as parse_emm_map
from capture_emm_live_owners import descriptor
from test_dos_char_retirement_qemu import install

CASES = {
    'control': ({}, None),
    'bios-tables': ({'fail_tables': True}, None),
    'bios-cds': ({'fail_cds': True}, None),
    'bios-stacks': ({'fail_stack_pool': True}, None),
    'emm-table-allocation': ({}, 'EMM_TABLE_ALLOC_FAIL'),
    'emm-table-copy': ({}, 'EMM_TABLE_COPY_FAIL'),
    'umb-after-map': ({}, 'UMB_TEST_FAIL_AFTER_MAP=1'),
    'umb-before-publish': ({}, 'UMB_TEST_FAIL_BEFORE_PUBLISH'),
    'retained-child': ({}, None),
    'dos-low': ({}, 'DOS_LOW_WITNESS'),
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('composition', type=Path, help='frozen build directory with build.json')
    parser.add_argument('--case', choices=CASES, action='append')
    args = parser.parse_args()
    source = args.composition.resolve()
    record = json.loads((source/'build.json').read_text())
    image = source/'candidate.img'
    assert sha(image) == record['image_sha256'], 'frozen input changed'
    for name, digest in json.loads((source/'source-hashes.json').read_text()).items():
        if name.startswith('src/'):
            assert sha(ROOT/name) == digest, f'current source differs: {name}'
    for name, digest in record['installed_sha256'].items():
        assert hashlib.sha256(image_file(image,'::'+name)).hexdigest() == digest, name
    work = Path(tempfile.mkdtemp(prefix='composed-memory-failures-',dir=ROOT/'out'))
    print(f'Artifacts: {work}',flush=True)
    report = dict(schema=1,input_sha256=sha(image),build_record_sha256=sha(source/'build.json'),
                  runner_sha256=sha(Path(__file__)),
                  table_probe_sha256=sha(ROOT/'tests/composed_table_owner_probe.asm'),
                  results={},scope='Private fault variants; base image remains unchanged.')

    def run(command, **kwargs):
        command = list(map(str,command))
        with (work/'commands.jsonl').open('a') as log:
            log.write(json.dumps(dict(command=command,cwd=str(kwargs.get('cwd',ROOT))))+'\n')
        return subprocess.run(command,check=True,**kwargs)

    for name in args.case or CASES:
        directory=work/name
        directory.mkdir()
        overrides, fault = CASES[name]
        no_umb = name.startswith('umb-')
        negative = name == 'retained-child'
        dos_high = name != 'dos-low'
        emm = source/'provider/MEMM/MEMM/EMM386.EXE'
        if fault or name == 'control':
            shutil.copytree(source/'provider',directory/'provider')
            provider = directory/'provider/MEMM/MEMM'
            with (directory/'provider-build.log').open('w') as log:
                # Reconstruct the non-faulted control before changing a define.
                for define in [None] + ([fault] if fault else []):
                    base_flags = ' '.join('-D'+item for item in record['emm_flags']) if 'emm_flags' in record else DEFINES
                    flags = base_flags + (' -D'+define if define else '')
                    if define == 'DOS_LOW_WITNESS':
                        # Remove only the HIGH-specific boot assertion. The
                        # stack probe independently requires DOS to be LOW.
                        flags = base_flags.replace('-DEMM_BOOTSTRAP_EXPECT_HMA', '')
                    for module in ('INIT','INITTAB'):
                        run([ROOT/'bin/jwasm-masm',
                             f'-Mx -t -DI386 -DNoBugMode -DNOHIMEM {flags} -I. -I../EMM',
                             f'{module}.ASM,{module}.OBJ;'],cwd=provider,stdout=log,stderr=log)
                    run([ROOT/'bin/wlink','/NOI /PACKDATA:1 @EMM386.LNK'],cwd=provider,stdout=log,stderr=log)
                    if define is None:
                        assert sha(provider/'EMM386.EXE') == sha(emm), 'provider control reconstruction differs'
            emm = provider/'EMM386.EXE'
        options=dict(record['bios_options'],**overrides)
        build_bios(directory/'bios',paired_provider=emm,**options)
        if not fault and not overrides:
            assert sha(directory/'bios/IO.SYS') == record['installed_sha256']['IO.SYS']
        disk=directory/'boot.img'
        shutil.copyfile(image,disk)
        install(disk,'IO.SYS',(directory/'bios/IO.SYS').read_bytes())
        install(disk,'DOS/EMM386.EXE',emm.read_bytes())
        config=image_file(image,'::CONFIG.SYS')
        if not dos_high:
            assert config.count(b'DOS=HIGH') == 1
            config=config.replace(b'DOS=HIGH',b'DOS=LOW')
            install(disk,'CONFIG.SYS',config)
        segments,symbols=parse_map(directory/'bios/msBIO.map')
        init=segments['SYSINITSEG'].paragraph*16+segments['SYSINITSEG'].offset
        (directory/'stack-defs.inc').write_text(
            f'%define EXPECT_UPPER {int(dos_high and not no_umb and name != "bios-stacks")}\n'
            f'%define EXPECT_DOS_HIGH {int(dos_high)}\n'
            f'%define ENTRY_OFFSET {symbols["Int08"]-init}\n'
            f'%define OLD_SLOT {symbols["Old08"]-init}\n')
        run([ROOT/'bin/jwasm-bin',f'-I{ROOT / "src/INC"}',f'-Fo{directory / "layout.bin"}',
             ROOT/'tests/bios_public_layout_masm.asm'],stdout=subprocess.DEVNULL)
        offsets=struct.unpack('<29H',(directory/'layout.bin').read_bytes())
        _, table_symbols = parse_emm_map(emm.with_suffix('.MAP'))
        table_symbols = {symbol.name: symbol for symbol in table_symbols}
        data_paragraph = table_symbols['TableSelector'].paragraph
        definitions = {'DATA_PARAGRAPH':data_paragraph}
        for key,symbol in [('TABLE_SELECTOR','TableSelector'),('GDT_SEG','GDT_Seg'),
                           ('SAVE_MAP','_save_map'),('EMM_BRK','_emm_brk')]:
            assert table_symbols[symbol].paragraph == data_paragraph
            definitions[key] = table_symbols[symbol].offset
        (directory/'table-defs.inc').write_text(''.join(
            f'%define {key} {value}\n' for key,value in definitions.items()))
        (directory/'layout-defs.inc').write_text(''.join(
            f'%define {key} {offsets[index]}\n' for key,index in [('SFT',1),('CDS',2),('SFLINK',11),('FCB',28)]))
        probes=[('stack_pool_probe.asm','STACKCHK.COM',[]),
                ('composed_table_owner_probe.asm','TABLECHK.COM',[]),
                ('composed_layout_probe.asm','LAYOUT.COM',[]),
                ('composed_ems_accounting_probe.asm','EMSCHECK.COM',['-DEXPECT_NO_UMB'] if no_umb else []),
                ('int21_fcb_probe.asm','I21FCB.COM',['-DNO_DEBUG_EXIT']),
                ('qemu_exit.asm','QEXIT.COM',[])]
        if no_umb:
            probes += [('umb_provider_absence_probe.asm','NOUMB.COM',[])]
        else:
            probes += [('composed_memory_owner_probe.asm','OWNERS.COM',[]),
                       ('composed_owner_child.asm','OWNCHILD.COM',['-DRETAIN_CHILD'] if negative else []),
                       ('umb_ems_isolation_probe.asm','UMBEMS.COM',[])]
        for asm,target,flags in probes:
            run(['nasm','-f','bin',f'-I{directory}/',*flags,ROOT/'tests'/asm,'-o',directory/target])
            install(disk,target,(directory/target).read_bytes())
        jobs=['STACKCHK.COM','LAYOUT.COM','TABLECHK.COM','EMSCHECK.COM']
        jobs += ['NOUMB.COM'] if no_umb else ['OWNERS.COM','UMBEMS.COM']
        jobs += ['I21FCB.COM','STACKCHK.COM','QEXIT.COM']
        batch='@ECHO OFF\r\nCTTY AUX\r\n'+''.join(
            job+'\r\nIF ERRORLEVEL 1 ECHO COMPOSED_JOB_FAILED\r\n' for job in jobs)
        install(disk,'AUTOEXEC.BAT',batch.encode('ascii'))
        command=['qemu-system-i386','-machine','pc','-cpu','486','-m','8',
            '-display','none','-monitor','none','-serial','stdio','-no-reboot','-boot','c',
            '-debugcon',f'file:{directory / "debug.log"}',
            '-device','isa-debug-exit,iobase=0xf4,iosize=0x04',
            '-drive',f'if=ide,index=0,format=raw,file={disk},cache=writethrough']
        try:
            result=subprocess.run(command,capture_output=True,timeout=60)
            code,output=result.returncode,result.stdout+result.stderr
        except subprocess.TimeoutExpired as error:
            code,output=None,(error.stdout or b'')+(error.stderr or b'')
        (directory/'serial.log').write_bytes(output)
        debug=(directory/'debug.log').read_bytes()
        row=dict(exit_code=code,passed=False,fault=fault,bios_overrides=overrides,
                 bios_sha256=sha(directory/'bios/IO.SYS'),emm_sha256=sha(emm),
                 stack_passes=debug.count(b'STACK_POOL_NESTED_PASS'),negative_control=negative,
                 config=config.decode('ascii'), command=command)
        report['results'][name]=row
        (work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
        if negative:
            assert b'COMPOSED_OWNER_ACCOUNTING_FAIL' in output and b'COMPOSED_OWNER_PASS' not in output, output
            assert code==35, (code,output)
        else:
            required=[b'COMPOSED_EMS_ACCOUNTING_PASS',b'INT21_FCB_PASS']
            required += [b'UMB_PROVIDER_ABSENT_PASS'] if no_umb else [b'COMPOSED_OWNER_PASS',b'UMB_EMS_ISOLATION_PASS']
            assert code==33 and all(marker in output for marker in required), (code,output)
            assert b'_FAIL' not in output and b'STACK_POOL_FAIL' not in debug and row['stack_passes']==2, (output,debug)
            cds,sft,fcb=struct.unpack('<3H',image_file(disk,'::LAYOUT.BIN'))
            actual=[value>=0xa000 for value in (cds,sft,fcb)]
            # DOS=LOW leaves kernel/interrupt stacks low; upper DOS tables
            # remain independent allocations when the provider offers UMBs.
            expected=[not no_umb and name!='bios-cds',
                      not no_umb and name!='bios-tables',
                      not no_umb and name!='bios-tables']
            assert actual==expected, (name,actual,expected)
            row['layout_segments']=dict(cds=cds,sft=sft,fcb=fcb)
            free,total,system=struct.unpack('<3H',image_file(disk,'::EMSCOUNT.BIN'))
            row['ems_pages']=dict(free=free,total=total,system_handle_pages=system)
            table_record = image_file(disk,'::TABLES.BIN')
            assert len(table_record)==16
            data_segment,start,end,selector=struct.unpack_from('<4H',table_record)
            owner=descriptor(table_record[8:])
            assert owner['access'] & 0x80, 'table descriptor is not present'
            high=int(selector==0xb0)
            assert selector in (0x40,0xb0), selector
            physical=owner['base']+start
            size=owner['size'] if high else end-start
            assert size>0 and (start==0 if high else owner['base']==data_segment*16)
            assert high==int(not name.startswith('emm-table-')) and bool(physical>=0x100000)==bool(high)
            row['emm_table_owner']=dict(physical=physical,bytes=size,end=end,high=high,
                                       selector=selector,descriptor=owner)
        row['passed']=True
        (work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
        print(f'PASS {name}: {directory}',flush=True)
    assert sha(image)==report['input_sha256']


if __name__=='__main__':
    main()
