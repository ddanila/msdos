#!/usr/bin/env python3
"""Build matched memory components without boot witnesses or retired-byte poison."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
# Reuse the maintained layout generators; their build functions do not run guests.
sys.path.insert(0, str(ROOT/'tests'))
from build_bios_low_image import build as build_bios
from test_command_high_resident_qemu import build as build_command

# These legacy *_TEST names select operational interfaces, not fault injection.
EMM_FLAGS = ('UMB_SUBPAGE_DISCOVERY UMB_SUBPAGE_MAPPING EMM_COMMON_XMS_TEST '
    'EMM_UMB_OWNER_TEST EMM_UMB_RESULTS_TEST EMM_XMS_COPY_TEST EMM_XMS_OWNER_TEST '
    'EMM_AUTHORITATIVE_OWNER_TEST EMM_HIGH_TABLES EMM_SPLIT_PREPARE '
    'EMM_DEFER_PROVIDER PROVIDER_REBASE EMM_BOOTSTRAP_PRODUCTION').split()
HIMEM_FLAGS = ('HIMEM_UMB_HANDOFF_TEST HIMEM_UMB_RESULTS_TEST HIMEM_COMMON_XMS_TEST '
    'HIMEM_BOOTSTRAP_STAGE_TEST HIMEM_PROTECTED_COPY_TEST HIMEM_PROTECTED_OWNER_TEST '
    'HIMEM_AUTHORITATIVE_OWNER_TEST').split()
BIOS_OPTIONS = dict(early=True, tail_body=True, rebase=True, compact=True,
    high_cds=True, dispatch=True, characters=True, retire_characters=True,
    pack_headers=True, retire_media=True, pack_drive_graph=True, high_stack_pool=True,
    retire_clock=True, retire_mux=True, compact_tracks=True, retire_swap=True,
    retire_ioctl_state=True, poison=False)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def build_inputs():
    # These generated inputs are reused by the component linkers. Source-only
    # hashing would miss a rebuilt kernel/object or a replaced native tool.
    result = {}
    for directory in ('MEMM','INC','DEV/HIMEM','BIOS','DOS','CMD/COMMAND'):
        for path in (ROOT/'src'/directory).rglob('*'):
            if path.is_file() and path.suffix.upper() in {'.OBJ','.LIB','.INC','.LNK','.SYS','.COM','.BIN'}:
                result[str(path.relative_to(ROOT))] = sha(path)
    host = {('Darwin','arm64'):'macos-arm64',('Linux','x86_64'):'linux-x64'}[
        (platform.system(),platform.machine())]
    paths = [ROOT/'jwasm'/host/'jwasm',*(ROOT/'watcom/bin'/host/name for name in ('wcc','wlib','wlink'))]
    for path in paths:
        result[str(path.relative_to(ROOT))] = sha(path)
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path, help='new output directory; build ordinary artifacts first')
    args = parser.parse_args()
    output = args.output.resolve()
    tracked = subprocess.check_output(['git','ls-files','-z','src','tests','tools','bin','mk',
                                      'Makefile','jwasm','watcom'],cwd=ROOT).decode().split('\0')
    inputs = {name:sha(ROOT/name) for name in tracked if name and (ROOT/name).is_file()}
    inputs[str(Path(__file__).relative_to(ROOT))] = sha(Path(__file__))
    generated_inputs = build_inputs()
    replace = output.exists()
    if replace:
        previous = json.loads((output/'build.json').read_text())
        if previous.get('kind') != 'memory-production-build':
            raise ValueError('output is not an owned production build directory')
        if previous.get('source_hashes') == inputs and previous.get('build_inputs') == generated_inputs and all(
                (output/'files'/name).is_file() and sha(output/'files'/name)==value
                for name,value in previous['sha256'].items()):
            print(f'Production build is current: {output}',flush=True)
            return
        allowed = {'provider','bios','command','files','build.log','commands.json','build.json'}
        if set(p.name for p in output.iterdir()) - allowed:
            raise ValueError('output contains qualification artifacts; preserve it and use a new directory')
    output.parent.mkdir(parents=True,exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix=output.name+'-',dir=output.parent))
    print(f'Production build: {work}', flush=True)
    shutil.copytree(ROOT/'src/MEMM',work/'provider/MEMM')
    shutil.copytree(ROOT/'src/INC',work/'provider/INC')
    shutil.copytree(ROOT/'src/DEV/HIMEM',work/'provider/DEV/HIMEM')
    directory = work/'provider/MEMM/MEMM'
    defines = ' '.join('-D'+flag for flag in EMM_FLAGS)
    flags = f'-Mx -t -DI386 -DNoBugMode -DNOHIMEM {defines} -I. -I../EMM -I../../INC -I../../DEV/HIMEM'
    commands = []
    with (work/'build.log').open('w') as log:
        def run(command, cwd=directory):
            commands.append(dict(argv=list(map(str,command)),cwd=str(cwd)))
            (work/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
            subprocess.run(command,cwd=cwd,stdout=log,stderr=log,check=True)
        for name in ('PPAGE','MOVEB','RRTRAP','EMMINIT','INITTAB','SHIPHI','TABDEF','INIT'):
            options = flags + (' -DRRTRAP_LOW_ONLY' if name=='RRTRAP' else '')
            run([ROOT/'bin/jwasm-masm',options,f'{name}.ASM,{name}.OBJ;'])
        run([ROOT/'bin/jwasm-masm',f'-Mx -t -DI386 -DNoBugMode -DNOHIMEM {defines} -I../MEMM',
             'EMMSUP.ASM,EMMSUP.OBJ;'],work/'provider/MEMM/EMM')
        run([ROOT/'bin/wlink','/NOI /PACKDATA:1 @EMM386.LNK'])
        run([ROOT/'bin/jwasm-bin','-q','-bin','-Sa',f'-Fl={work}/provider/HIMEM.LST',
             *['-D'+flag for flag in HIMEM_FLAGS],f'-I{work}/provider/INC',
             f'-Fo{work}/provider/HIMEM.SYS',work/'provider/DEV/HIMEM/HIMEM.ASM'])
    emm = directory/'EMM386.EXE'
    bios = build_bios(work/'bios',paired_provider=emm,**BIOS_OPTIONS)
    command = build_command(work/'command',True,upper_data=True,poison=False)
    files = {'IO.SYS':work/'bios/IO.SYS','MSDOS.SYS':ROOT/'src/DOS/MSDOS.SYS',
             'COMMAND.COM':command,'HIMEM.SYS':work/'provider/HIMEM.SYS','EMM386.EXE':emm}
    (work/'files').mkdir()
    for name,path in files.items():
        shutil.copyfile(path,work/'files'/name)
    record = dict(kind='memory-production-build',source_hashes=inputs,build_inputs=generated_inputs,emm_flags=EMM_FLAGS,himem_flags=HIMEM_FLAGS,bios_options=BIOS_OPTIONS,
                  command_options=dict(high=True,upper_data=True,poison=False),
                  sha256={name:sha(path) for name,path in files.items()},qualified=False)
    assert bios['paired_provider_sha256']==record['sha256']['EMM386.EXE']
    (work/'build.json').write_text(json.dumps(record,indent=2)+'\n')
    if replace:
        backup = output.with_name(work.name+'-previous')
        output.rename(backup)
        try:
            work.rename(output)
        except BaseException:
            backup.rename(output)
            raise
        shutil.rmtree(backup)
    else:
        work.rename(output)

if __name__=='__main__':
    main()
