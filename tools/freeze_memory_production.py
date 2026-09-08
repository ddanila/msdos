#!/usr/bin/env python3
"""Freeze a production memory build with matching deployed tools on private media."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests'))
from capture_vc_memory_comparison import image_file, partition_offset
from report_dos_bios_residency import parse_map
from test_dos_char_retirement_qemu import ENV, install


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def listing(image, directory):
    data = subprocess.check_output(['mdir','-a','-b','-i',str(image),directory],env=ENV)
    return [line.decode('ascii').removeprefix('::/').upper() for line in data.splitlines()
            if not line.endswith(b'/')]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('base_image',type=Path)
    parser.add_argument('production',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--floppy',type=Path,default=ROOT/'out/floppy.img')
    args = parser.parse_args()
    base_digest = sha(args.base_image)
    floppy_digest = sha(args.floppy)
    production = args.production.resolve()
    record = json.loads((production/'build.json').read_text())
    assert record['kind']=='memory-production-build'
    for name,value in record['sha256'].items():
        assert sha(production/'files'/name)==value,name
    for name,value in record['source_hashes'].items():
        if name.startswith('src/'):
            assert sha(ROOT/name)==value,name
    work = args.output.resolve()
    work.mkdir(parents=True,exist_ok=False)
    image = work/'candidate.img'
    shutil.copyfile(args.base_image,image)
    for directory in ('provider','bios','command'):
        shutil.copytree(production/directory,work/directory)
    spec = f'{image}@@{partition_offset(image)}'
    existing = listing(spec,'::/')+listing(spec,'::/DOS/')
    assert not any(name.endswith('SWBOOT.TAG') for name in existing),'stale reboot receipt'
    deployed = set(listing(args.floppy,'::/'))
    installed = {}
    for destination in existing:
        name = destination.split('/')[-1]
        if name in deployed and name not in ('CONFIG.SYS','AUTOEXEC.BAT'):
            data = subprocess.check_output(['mtype','-i',str(args.floppy),'::'+name],env=ENV)
            install(image,destination,data)
            installed[destination]=hashlib.sha256(data).hexdigest()
    for name in record['sha256']:
        destinations = [name] if name in ('IO.SYS','MSDOS.SYS') else ['DOS/'+name]
        if name=='COMMAND.COM':
            destinations.append(name)
        for destination in destinations:
            install(image,destination,(production/'files'/name).read_bytes())
            installed[destination]=record['sha256'][name]
    maps = work/'maps'
    maps.mkdir()
    for extension in ('MAP','SYS'):
        shutil.copyfile(ROOT/f'src/DOS/MSDOS.{extension}',maps/f'MSDOS.{extension}')
    _,kernel = parse_map(maps/'MSDOS.MAP')
    kernel = {k.upper():v for k,v in kernel.items()}
    for name in ('SHARE','IFSFUNC'):
        source = ROOT/f'src/CMD/{name}/{name}.MAP'
        shutil.copyfile(source,maps/source.name)
        segments,fields = parse_map(source)
        base = segments['START'].paragraph*16+segments['START'].offset
        fields = {k.upper():v-base for k,v in fields.items()}
        for field in ('SWAP_START','CURRENTPDB','THISSFT','WFP_START','CONSFT','USER_ID','PROC_ID','BYTPOS','OPENBUF'):
            assert fields[field]==kernel[field],(name,field)
    config = image_file(image,'::CONFIG.SYS')
    assert all(token in config.upper() for token in (b'DOS=HIGH,UMB',b'DOS\\HIMEM.SYS',b'DOS\\EMM386.EXE'))
    for name in ('CONFIG.SYS','AUTOEXEC.BAT'):
        (work/name).write_bytes(image_file(image,'::'+name))
    (work/'source-hashes.json').write_text(json.dumps(record['source_hashes'],indent=2)+'\n')
    assert sha(args.base_image)==base_digest, 'base image changed during freeze'
    assert sha(args.floppy)==floppy_digest, 'deployed floppy changed during freeze'
    record.update(kind='memory-production-candidate',image_sha256=sha(image),installed_sha256=installed,
                  base_image_sha256=base_digest,floppy_sha256=floppy_digest,
                  freezer_sha256=sha(Path(__file__)),
                  production_build_sha256=sha(production/'build.json'),qualified=False)
    (work/'build.json').write_text(json.dumps(record,indent=2)+'\n')
    print(f'Frozen candidate: {image}',flush=True)

if __name__=='__main__':
    main()
