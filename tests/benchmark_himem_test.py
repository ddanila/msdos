#!/usr/bin/env python3
"""Compare default HIMEM test cost with /TESTMEM:OFF on matched DOS HDDs.

Inputs must be bootable single-partition FAT16 images with their own HIMEM.SYS
and EMM386.EXE at C:\. Microsoft media remain external inputs. All mutations
are made on private copies; the benchmark never changes the input images.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import selectors
import shutil
import statistics
import struct
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
ENV = dict(os.environ, MTOOLS_SKIP_CHECK='1', MTOOLS_NO_VFAT='1')


def run(args, **kwargs):
    return subprocess.run([str(x) for x in args], env=ENV, check=True, **kwargs)


def timed_boot(image, output, name, memory):
    command = ['qemu-system-i386', '-machine', 'pc', '-cpu', '486', '-m', str(memory),
        '-accel', 'tcg,thread=single', '-d', 'nochain', '-display', 'none',
        '-monitor', 'none', '-serial', 'none', '-nic', 'none', '-no-reboot',
        '-rtc', 'base=1995-01-02T12:00:00,clock=vm', '-boot', 'c', '-snapshot',
        '-drive', f'if=ide,index=0,format=raw,file={image}', '-debugcon', 'stdio',
        '-device', 'isa-debug-exit,iobase=0xf4,iosize=0x04']
    raw = b''
    marks = {}
    started = time.perf_counter()
    with (output / (name + '.log')).open('wb') as log:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=log)
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        try:
            while time.perf_counter() - started < 180 and 'ready' not in marks:
                if not selector.select(.25):
                    if process.poll() is not None:
                        break
                    continue
                data = os.read(process.stdout.fileno(), 4096)
                stamp = time.perf_counter()
                if not data:
                    break
                raw += data
                for key, marker in [('start', b'~BOOTBENCH_START~\n'),
                                    ('ready', b'~BOOTBENCH_READY~\n')]:
                    if marker in raw and key not in marks:
                        marks[key] = stamp
            if set(marks) != {'start', 'ready'}:
                raise RuntimeError(f'{name}: missing boot markers: {raw!r}')
            if process.wait(timeout=5) != 33:
                raise RuntimeError(f'{name}: unexpected QEMU exit status')
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            selector.close()
            (output / (name + '.trace')).write_bytes(raw)
    return dict(seconds=marks['ready'] - marks['start'], command=command)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fork-image', type=Path, required=True)
    parser.add_argument('--microsoft-image', type=Path, required=True)
    parser.add_argument('--fork-himem', type=Path, help='replace HIMEM on the private fork copies')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--repeats', type=int, default=5)
    parser.add_argument('--memory', type=int, default=16)
    parser.add_argument('--mode', choices=['high', 'high-umb'], default='high-umb')
    parser.add_argument('--max-test-ratio', type=float, help='fail if fork test cost exceeds this multiple of Microsoft')
    args = parser.parse_args()
    if args.repeats < 1 or args.memory < 2:
        parser.error('positive repeats and at least 2 MiB are required')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        parser.error('output must be empty')
    for source, name in [('boot_benchmark_mbr.asm', 'mbr.bin'),
                         ('boot_benchmark_ready.asm', 'READY.COM')]:
        run(['nasm', '-f', 'bin', ROOT/'tests'/source, '-o', output/name])
    images, provenance, geometries = {}, {}, []
    for label, source in [('fork', args.fork_image), ('microsoft', args.microsoft_image)]:
        source = source.resolve()
        data = source.read_bytes()
        offset = struct.unpack_from('<I', data, 454)[0] * 512
        if not offset or data[450] not in (4, 6, 14):
            parser.error(f'{source}: first partition must be FAT16')
        geometries.append((len(data), offset, data[offset+11:offset+36]))
        provenance[label] = {'source': str(source), 'sha256': hashlib.sha256(data).hexdigest()}
        for testmem in ('on', 'off'):
            image = output/f'{label}-{testmem}.img'
            shutil.copyfile(source, image)
            with image.open('r+b') as stream:
                stream.write((output/'mbr.bin').read_bytes()[:446])
            spec = f'{image}@@{offset}'
            def put(name, content):
                run(['mcopy', '-o', '-i', spec, '-', '::'+name], input=content)
            if label == 'fork' and args.fork_himem:
                put('HIMEM.SYS', args.fork_himem.read_bytes())
            config = 'DEVICE=C:\\HIMEM.SYS' + (' /TESTMEM:OFF' if testmem == 'off' else '') + '\r\n'
            if args.mode == 'high-umb':
                config += 'DEVICE=C:\\EMM386.EXE NOEMS\r\nDOS=HIGH,UMB\r\n'
            else:
                config += 'DOS=HIGH\r\n'
            put('CONFIG.SYS', config.encode())
            put('AUTOEXEC.BAT', b'@ECHO OFF\r\nREADY.COM\r\n')
            put('READY.COM', (output/'READY.COM').read_bytes())
            images[(label, testmem)] = image
            (output/f'{label}-{testmem}-config.txt').write_text(config)
            installed = {}
            for name in ('IO.SYS', 'MSDOS.SYS', 'COMMAND.COM', 'HIMEM.SYS', 'EMM386.EXE'):
                content = subprocess.check_output(['mtype', '-i', spec, '::'+name], env=ENV)
                installed[name] = hashlib.sha256(content).hexdigest()
            provenance[label]['installed'] = installed
    if geometries[0] != geometries[1]:
        parser.error('images must have identical sizes and FAT geometry')
    results = []
    for round_id in range(args.repeats + 1):
        cases = list(images)
        random.Random(20260909 + round_id).shuffle(cases)
        for label, testmem in cases:
            row = timed_boot(images[(label, testmem)], output,
                             f'{round_id:02d}-{label}-{testmem}', args.memory)
            row.update(label=label, testmem=testmem, warmup=round_id == 0)
            results.append(row)
            (output/'runs.json').write_text(json.dumps(results, indent=2)+'\n')
            print(f'{round_id}: {label} test={testmem} {row["seconds"]:.6f}s', flush=True)
    summary = {}
    for label in ('fork', 'microsoft'):
        medians = {mode: statistics.median(r['seconds'] for r in results
            if r['label'] == label and r['testmem'] == mode and not r['warmup'])
            for mode in ('on', 'off')}
        summary[label] = dict(medians, test_seconds=medians['on']-medians['off'])
    reference = summary['microsoft']['test_seconds']
    if reference <= 0:
        raise RuntimeError('reference test time is below measurement resolution')
    ratio = summary['fork']['test_seconds']/reference
    record = dict(provenance=provenance, summary=summary, test_ratio=ratio,
                  mode=args.mode, memory_mib=args.memory, repeats=args.repeats,
                  qemu=subprocess.check_output(['qemu-system-i386', '--version']).decode().splitlines()[0])
    (output/'result.json').write_text(json.dumps(record, indent=2)+'\n')
    print(json.dumps(record['summary'], indent=2), flush=True)
    if args.max_test_ratio is not None and ratio > args.max_test_ratio:
        raise SystemExit(f'HIMEM test ratio {ratio:.3f} exceeds {args.max_test_ratio:.3f}')


if __name__ == '__main__':
    main()
