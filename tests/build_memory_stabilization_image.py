#!/usr/bin/env python3
"""Freeze a matched composed image after building/deploying current sources.

Requires a completed, non-faulted capture_emm_init_phases.py provider fixture.
The base is an external FAT16 hard-disk image; neither input image is modified.
This builder records inputs and layout checks, not runtime qualification.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

from build_bios_low_image import ROOT, build as build_bios
from capture_vc_memory_comparison import image_file, partition_offset
from report_dos_bios_residency import parse_map
from test_command_high_resident_qemu import build as build_command
from test_dos_char_retirement_qemu import ENV, install
from test_umb_subpage_composition import paired_inputs


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def listing(spec, directory):
    output = subprocess.check_output(['mdir', '-a', '-b', '-i', str(spec), directory], env=ENV)
    return [line.decode('ascii').removeprefix('::/').upper()
            for line in output.splitlines() if not line.endswith(b'/')]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('base_image', type=Path)
    parser.add_argument('paired_provider', type=Path)
    parser.add_argument('output', type=Path, help='new, empty output directory')
    parser.add_argument('--floppy', type=Path, default=ROOT / 'out/floppy.img')
    args = parser.parse_args()
    emm, himem = paired_inputs(args.paired_provider)
    if not args.base_image.is_file() or not args.floppy.is_file():
        parser.error('base image and deployed floppy must exist')
    work = args.output.resolve()
    work.mkdir(parents=True, exist_ok=False)
    print(f'Artifacts: {work}', flush=True)
    commands = work / 'commands.jsonl'

    def audit(event, values):
        if event == 'subprocess.Popen':
            executable, argv, cwd, _ = values
            with commands.open('a') as log:
                log.write(json.dumps(dict(executable=str(executable), argv=list(map(str, argv)),
                                          cwd=str(cwd) if cwd else str(Path.cwd()))) + '\n')
    sys.addaudithook(audit)
    image = work / 'candidate.img'
    shutil.copyfile(args.base_image, image)
    shutil.copytree(args.paired_provider, work / 'provider',
                    ignore=shutil.ignore_patterns('*.img', '*.bin'))
    # Preserve the provider binaries even though the fixture's raw captures
    # (*.bin) and test disks are excluded from this build snapshot.
    emm = work / 'provider/MEMM/MEMM/EMM386.EXE'
    himem = work / 'provider/HIMEM.SYS'
    options = dict(early=True, tail_body=True, rebase=True, compact=True,
        high_cds=True, dispatch=True, characters=True, retire_characters=True,
        pack_headers=True, retire_media=True, pack_drive_graph=True,
        high_stack_pool=True, retire_clock=True, retire_mux=True,
        compact_tracks=True, retire_swap=True, retire_ioctl_state=True)
    bios = build_bios(work / 'bios', paired_provider=emm, **options)
    command = build_command(work / 'command', True, upper_data=True)
    spec = f'{image}@@{partition_offset(image)}'
    existing = listing(spec, '::/') + listing(spec, '::/DOS/')
    if any(n.endswith('SWBOOT.TAG') for n in existing):
        raise ValueError('base contains a stale reboot receipt')
    deployed = set(listing(args.floppy, '::/'))
    installed = {}
    # Refresh existing system tools from the freshly deployed floppy, keeping
    # applications and the external disk's partition/boot layout intact.
    for destination in existing:
        name = destination.split('/')[-1]
        if name not in deployed or name in ('CONFIG.SYS', 'AUTOEXEC.BAT'):
            continue
        data = subprocess.check_output(['mtype', '-i', str(args.floppy), '::'+name], env=ENV)
        install(image, destination, data)
        installed[destination] = hashlib.sha256(data).hexdigest()
    files = {'IO.SYS': work/'bios/IO.SYS', 'MSDOS.SYS': ROOT/'src/DOS/MSDOS.SYS',
        'COMMAND.COM': command, 'DOS/COMMAND.COM': command,
        'DOS/HIMEM.SYS': himem, 'DOS/EMM386.EXE': emm}
    maps = work / 'maps'
    maps.mkdir()
    shutil.copyfile(ROOT/'src/DOS/MSDOS.MAP', maps/'MSDOS.MAP')
    shutil.copyfile(ROOT/'src/DOS/MSDOS.SYS', maps/'MSDOS.SYS')
    _, kernel_fields = parse_map(maps/'MSDOS.MAP')
    kernel_fields = {k.upper():v for k,v in kernel_fields.items()}
    for name in ('SHARE', 'IFSFUNC', 'FILESYS'):
        source = ROOT/f'src/CMD/{name}/{name}.EXE'
        files['DOS/'+name+'.EXE'] = source
        if name in ('SHARE', 'IFSFUNC'):
            shutil.copyfile(source.with_suffix('.MAP'), maps/(name+'.MAP'))
            segments, fields = parse_map(source.with_suffix('.MAP'))
            base = segments['START'].paragraph*16 + segments['START'].offset
            fields = {k.upper():v-base for k,v in fields.items()}
            for field in ('SWAP_START','CURRENTPDB','THISSFT','WFP_START','CONSFT',
                          'USER_ID','PROC_ID','BYTPOS','OPENBUF'):
                if fields[field] != kernel_fields[field]:
                    raise ValueError(f'{name} shared kernel offset mismatch: {field}')
    for destination, source in files.items():
        install(image, destination, source.read_bytes())
        installed[destination] = sha(source)
    config = image_file(args.base_image, '::CONFIG.SYS')
    config = b'\r\n'.join(line for line in config.splitlines()
                            if not line.strip().upper().startswith(b'STACKS='))
    config += b'\r\nSTACKS=9,128\r\n'
    if not all(s in config.upper() for s in (b'DOS=HIGH,UMB', b'DOS\\HIMEM.SYS', b'DOS\\EMM386.EXE')):
        raise ValueError('base must use paired DOS managers and DOS=HIGH,UMB')
    install(image, 'CONFIG.SYS', config)
    (work/'CONFIG.SYS').write_bytes(config)
    (work/'AUTOEXEC.BAT').write_bytes(image_file(image,'::AUTOEXEC.BAT'))
    tracked = subprocess.check_output(['git','ls-files','-z','src','tests','tools','bin','mk',
                                      'Makefile','jwasm','watcom'], cwd=ROOT).decode().split('\0')
    source_hashes = {n:sha(ROOT/n) for n in tracked if n and (ROOT/n).is_file()}
    source_hashes['tests/build_memory_stabilization_image.py'] = sha(Path(__file__))
    (work/'source-hashes.json').write_text(json.dumps(source_hashes,indent=2)+'\n')
    record = dict(schema=1, source_commit=subprocess.check_output(
        ['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
        builder_sha256=sha(Path(__file__)), base_image_sha256=sha(args.base_image),
        floppy_sha256=sha(args.floppy), source_hashes_sha256=sha(work/'source-hashes.json'),
        provider_result_sha256=sha(work/'provider/result.json'),
        provider_source=str(args.paired_provider.resolve()), bios_options=options,
        bios_manifest_sha256=sha(work/'bios/low.json'),
        command_options=['COMMAND_RESIDENT_BINDING','COMMAND_HIGH_RESIDENT',
                         'COMMAND_HIGH_RESIDENT_POISON','COMMAND_UMB_DATA'],
        config=config.decode('ascii'), image_sha256=sha(image), installed_sha256=installed,
        shared_layout_checked=['SHARE','IFSFUNC'], qualified=False)
    if bios['paired_provider_sha256'] != installed['DOS/EMM386.EXE']:
        raise ValueError('BIOS/provider identity mismatch')
    (work/'build.json').write_text(json.dumps(record,indent=2)+'\n')
    print(f'Frozen image: {image}\nSHA256: {record["image_sha256"]}',flush=True)


if __name__ == '__main__':
    main()
