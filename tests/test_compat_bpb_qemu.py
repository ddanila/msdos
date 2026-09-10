#!/usr/bin/env python3
"""Qualify formatter-independent FAT BPBs and actual INT 21h/3306h residency.

Private images only. Optional --reference supplies Microsoft's external 6.22
floppy; --reference-files supplies its matching HIMEM/EMM386 for HIGH checks.
Malformed BPBs test our legacy fallback only, not Microsoft equivalence.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ENV = dict(os.environ, MTOOLS_SKIP_CHECK='1', MTOOLS_NO_VFAT='1', LC_ALL='C')
OFFSET = 63 * 512


def run(argv, **kwargs):
    return subprocess.run(list(map(str, argv)), env=ENV, check=True,
                          capture_output=True, **kwargs)


def put(image, name, content):
    run(['mcopy', '-o', '-i', image, '-', '::' + name], input=content)


def disk(directory, variant):
    cylinders = variant.get('cylinders', 8)
    sectors = cylinders * 16 * 63
    total = sectors - 63 - variant.get('unused', 0)
    image = directory / 'disk.img'
    with image.open('wb') as stream:
        stream.truncate(sectors * 512)
        mbr = bytearray(512)
        mbr[446:462] = bytes((0, 1, 1, 0, 1 if cylinders == 8 else 6,
                             15, 63, cylinders - 1)) + struct.pack('<II', 63, sectors - 63)
        mbr[510:] = b'\x55\xaa'
        stream.write(mbr)
    spec = f'{image}@@{OFFSET}'
    run(['mformat', '-i', spec, '-T', total, '-h', 16, '-n', 63, '-H', 63,
         '-c', 2, '-R', variant.get('reserved', 1), '-d', variant.get('fats', 2),
         '-r', variant.get('root', 32), '-N', '0x12345678', '::'])
    put(spec, 'READ.TXT', b'BPB read proof\r\n')
    with image.open('r+b') as stream:
        stream.seek(OFFSET)
        bpb = bytearray(stream.read(512))
        if 'oem' in variant:
            bpb[3:11] = variant['oem'].encode('ascii')
        if variant.get('total32'):
            struct.pack_into('<H', bpb, 19, 0)
            struct.pack_into('<I', bpb, 32, total)
        for offset, fmt, value in variant.get('mutations', []):
            struct.pack_into(fmt, bpb, offset, value)
        stream.seek(OFFSET)
        stream.write(bpb)
    # DOS 4+ DPB fields describe the exact layout that file APIs must use.
    reserved = struct.unpack_from('<H', bpb, 14)[0]
    fats = bpb[16]
    roots = struct.unpack_from('<H', bpb, 17)[0]
    fat_size = struct.unpack_from('<H', bpb, 22)[0]
    root_start = reserved + fats * fat_size
    first_data = root_start + roots // 16
    fields = [(2, 'word', 512), (4, 'byte', bpb[13] - 1),
              (6, 'word', reserved), (8, 'byte', fats), (9, 'word', roots),
              (11, 'word', first_data), (13, 'word', (total - first_data) // 2 + 1),
              (15, 'word', fat_size), (17, 'word', root_start)]
    return image, fields, bpb


PROBE = """bits 16
org 100h
mov ax,ds
mov es,ax
mov ax,3306h
int 21h
cmp bx,1606h
jne failed
cmp dx,{flag}
jne failed
mov ax,es
mov cx,ds
cmp ax,cx
jne failed
{disk_checks}
mov dx,okay
mov ah,9
int 21h
mov dx,0f4h
mov ax,10h
out dx,ax
hlt
failed:
push cs
pop ds
mov dx,bad
mov ah,9
int 21h
mov dx,0f4h
mov ax,11h
out dx,ax
hlt
okay db 'COMPAT_PASS',13,10,'$'
bad db 'COMPAT_FAIL_STAGE_'
bad_stage db 'V'
 db 13,10,'$'
read_name db 'C:\\READ.TXT',0
write_name db 'C:\\WRITE.TXT',0
payload db 'BPB read proof',13,10
payload_end:
buffer times 32 db 0
"""


def disk_checks(fields, invalid):
    if invalid:
        # Rejected media must use the historical fallback (8-sector clusters),
        # never the invalid BPB's two-sector clusters or unsafe divisor.
        fields = [(4, 'byte', 7), (6, 'word', 1), (8, 'byte', 2), (15, 'word', 3)]
    checks = "mov byte [cs:bad_stage],'D'\npush ds\nmov ah,32h\nmov dl,3\nint 21h\ncmp al,0\njne failed\n"
    for offset, width, value in fields:
        checks += f'cmp {width} [bx+{offset}],{value}\njne failed\n'
    checks += 'pop ds\n'
    if invalid:
        return checks
    return checks + """mov byte [cs:bad_stage],'R'
mov ax,3d00h
mov dx,read_name
int 21h
jc failed
mov bx,ax
mov ah,3fh
mov cx,payload_end-payload
mov dx,buffer
int 21h
jc failed
cmp ax,payload_end-payload
jne failed
mov ah,3eh
int 21h
jc failed
mov si,buffer
mov di,payload
mov cx,payload_end-payload
cld
repe cmpsb
jne failed
mov byte [cs:bad_stage],'W'
mov ah,3ch
xor cx,cx
mov dx,write_name
int 21h
jc failed
mov bx,ax
mov ah,40h
mov cx,payload_end-payload
mov dx,payload
int 21h
jc failed
cmp ax,payload_end-payload
jne failed
mov ah,3eh
int 21h
jc failed
"""


def boot(directory, base, mode, variant=None, drivers=None, expected_layout=True):
    directory.mkdir()
    floppy = directory / 'boot.img'
    shutil.copyfile(base, floppy)
    if drivers:
        for name in ('HIMEM.SYS', 'EMM386.EXE'):
            run(['mcopy', '-o', '-i', floppy, drivers / name, '::' + name])
    extra = []
    checks = ''
    if variant is not None:
        image, fields, bpb = disk(directory, variant)
        (directory / 'bpb.bin').write_bytes(bpb)
        checks = disk_checks(fields, variant.get('invalid', False))
        extra = ['-drive', f'if=ide,format=raw,file={image}']
    source = directory / 'probe.asm'
    source.write_text(PROBE.format(flag='1000h' if mode == 'high' else '0', disk_checks=checks))
    run(['nasm', '-f', 'bin', source, '-o', directory / 'probe.com'])
    put(floppy, 'PROBE.COM', (directory / 'probe.com').read_bytes())
    config = 'FILES=40\r\nLASTDRIVE=Z\r\n'
    if mode == 'high':
        config += 'DEVICE=A:\\HIMEM.SYS\r\nDEVICE=A:\\EMM386.EXE NOEMS\r\nDOS=HIGH,UMB\r\n'
    elif mode == 'fallback':
        config += 'DOS=HIGH\r\n'
    else:
        config += 'DOS=LOW\r\n'
    put(floppy, 'CONFIG.SYS', config.encode())
    put(floppy, 'AUTOEXEC.BAT', b'@ECHO OFF\r\nCTTY AUX\r\nA:\\PROBE.COM\r\n')
    argv = ['qemu-system-i386', '-machine', 'pc', '-cpu', '486', '-m', '16',
            '-accel', 'tcg,thread=single', '-d', 'nochain', '-display', 'none',
            '-monitor', 'none', '-serial', 'stdio', '-nic', 'none', '-no-reboot',
            '-boot', 'a', '-drive', f'if=floppy,format=raw,file={floppy}',
            '-device', 'isa-debug-exit,iobase=0xf4,iosize=0x04', *extra]
    (directory / 'command.json').write_text(json.dumps(argv, indent=2) + '\n')
    try:
        result = subprocess.run(argv, capture_output=True, timeout=45, env=ENV)
    except subprocess.TimeoutExpired as error:
        (directory / 'serial.log').write_bytes((error.stdout or b'') + (error.stderr or b''))
        raise
    output = result.stdout + result.stderr
    (directory / 'serial.log').write_bytes(output)
    if not expected_layout:
        assert result.returncode == 35 and b'COMPAT_FAIL_STAGE_D' in output, output.decode('cp437')
        return
    assert result.returncode == 33 and b'COMPAT_PASS' in output, output.decode('cp437')
    if variant is not None and not variant.get('invalid'):
        actual = run(['mtype', '-i', f'{image}@@{OFFSET}', '::WRITE.TXT']).stdout
        assert actual == b'BPB read proof\r\n', actual


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', type=Path, default=ROOT / 'out/floppy.img')
    parser.add_argument('--reference', type=Path)
    parser.add_argument('--reference-files', type=Path)
    args = parser.parse_args()
    output = Path(tempfile.mkdtemp(prefix='compat-bpb-', dir=ROOT / 'out'))
    print(f'Artifacts: {output}', flush=True)
    variants = {
        'mtools-fat12': {},
        'blank-oem': {'oem': '        '},
        'arbitrary-oem': {'oem': 'CUSTOM!!'},
        'dos-oem': {'oem': 'MSDOS5.0'},
        'fat12-total32': {'total32': True},
        'fat12-layout': {'reserved': 4, 'fats': 1, 'root': 16},
        'fat12-short-volume': {'unused': 1024},
        'mtools-fat16': {'cylinders': 64},
        'fat16-total32': {'cylinders': 128},
        'fat16-layout': {'cylinders': 128, 'reserved': 4, 'fats': 1, 'root': 16},
    }
    invalid = {
        'no-signature': (510, '<H', 0), 'sector-size': (11, '<H', 1024),
        'zero-cluster': (13, '<B', 0), 'non-power-cluster': (13, '<B', 3),
        'zero-reserved': (14, '<H', 0), 'zero-fats': (16, '<B', 0),
        'zero-root': (17, '<H', 0), 'unaligned-root': (17, '<H', 17),
        'zero-fat-size': (22, '<H', 0), 'short-fat': (22, '<H', 1),
        'metadata-overflow': (22, '<H', 32768), 'short-volume': (19, '<H', 2),
        'oversized-volume': (19, '<H', 65535),
    }
    records = []
    for label, image, drivers in [('ours', args.image, None), ('microsoft', args.reference, args.reference_files)]:
        if image is None:
            continue
        image_sha = hashlib.sha256(image.read_bytes()).hexdigest()
        jobs = [(f'hma-{mode}', mode, None) for mode in ('low', 'high', 'fallback')
                if label == 'ours' or mode != 'high' or drivers]
        jobs += [(name, 'low', variant) for name, variant in variants.items()]
        jobs += [('mtools-high', 'high', {})] if label == 'ours' or drivers else []
        if label == 'ours':
            jobs += [(f'invalid-{name}', 'low', {'invalid': True, 'mutations': [mutation]})
                     for name, mutation in invalid.items()]
        for name, mode, variant in jobs:
            # Retail 6.22 failed these DPB assertions in the initial control.
            # Record the difference explicitly; it is not a matching pass.
            expected_layout = not (label == 'microsoft' and name in
                                   ('blank-oem', 'arbitrary-oem', 'fat12-layout', 'fat16-layout'))
            row = dict(system=label, name=name, mode=mode, image_sha256=image_sha,
                       expected_layout=expected_layout)
            try:
                boot(output / f'{label}-{name}', image, mode, variant, drivers, expected_layout)
                row['passed'] = True
            except Exception as error:
                row.update(passed=False, error=str(error))
            records.append(row)
            print(f"{'PASS' if row['passed'] else 'FAIL'}: {label} {name}" +
                  (' (expected retail DPB mismatch)' if not expected_layout else '') +
                  (f" {row['error']}" if not row['passed'] else ''), flush=True)
            (output / 'results.json').write_text(json.dumps(records, indent=2) + '\n')
    return 0 if all(row['passed'] for row in records) else 1


if __name__ == '__main__':
    raise SystemExit(main())
