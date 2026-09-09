#!/usr/bin/env python3
"""Verify HIMEM's actual memory-test routine, fault coverage and CPU state."""
from pathlib import Path
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

from report_himem_residency import PROCEDURE_RE, parse_symbols

ROOT = Path(__file__).resolve().parents[1]
ENV = dict(os.environ, MTOOLS_SKIP_CHECK='1', MTOOLS_NO_VFAT='1')


def run(args, **kwargs):
    return subprocess.run([str(x) for x in args], env=ENV, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--production', action='store_true')
    parser.add_argument('--a20-backend', choices=['fast', 'bios', 'kbc'], default='fast')
    parser.add_argument('--case', action='append')
    args = parser.parse_args()
    build_flags = []
    if args.production:
        sys.path.insert(0, str(ROOT/'tools'))
        from build_memory_production import HIMEM_FLAGS
        build_flags = ['-D'+flag for flag in HIMEM_FLAGS]
    if args.a20_backend in ('bios', 'kbc'):
        build_flags += ['-DA20_TEST_SKIP_FAST']
    if args.a20_backend == 'kbc':
        build_flags += ['-DA20_TEST_SKIP_BIOS']
    out = Path(tempfile.mkdtemp(prefix='himem-testmem-', dir=ROOT/'out'))
    print(f'Artifacts: {out}', flush=True)
    cases = [('one-kib', 1, None, 1), ('full-chunk', 64, None, 1),
             ('partial-tail', 2051, None, 1),
             ('fault-first', 2051, 0x100000, 1),
             ('fault-boundary', 2051, 0x110000, 1),
             ('fault-last-byte', 2051, 0x100000+2051*1024-1, 1),
             ('fault-second-pattern', 2051, 0x100000+2051*1024-1, 2)]
    cases = [(*case, None) for case in cases] + [
        (f'nmi-phase-{phase}', 65, None, 1, phase) for phase in range(1, 6)]
    if args.case:
        unknown = set(args.case) - {case[0] for case in cases}
        if unknown:
            parser.error(f'unknown cases: {unknown}')
        cases = [case for case in cases if case[0] in args.case]
    results = []
    for name, span, fault, phase, nmi_phase in cases:
        directory = out/name
        directory.mkdir()
        driver, listing = directory/'HIMEM.SYS', directory/'HIMEM.LST'
        flags = [] if fault is None else ['-DTESTMEM_FAULT',
            f'-DTESTMEM_FAULT_PHYSICAL={fault}', f'-DTESTMEM_FAULT_PATTERN={phase}']
        if nmi_phase is not None:
            flags += [f'-DTESTMEM_NMI_AT={nmi_phase}']
        run([ROOT/'bin/jwasm-bin', '-q', '-bin', '-Sa', f'-I{ROOT}/src/INC', *build_flags, *flags,
             f'-Fl{listing}', f'-Fo{driver}', ROOT/'src/DEV/HIMEM/HIMEM.ASM'])
        symbols, _ = parse_symbols(listing)
        procedures = {m[1]:int(m[2],16) for line in listing.read_text().splitlines()
                      if (m := PROCEDURE_RE.match(line))}
        probe = directory/'PROBE.COM'
        defines = [f'-DHIMEM_BINARY="{driver}"', f'-DSPAN_KB={span}',
            f'-DEXTENDED_KB_OFFSET={symbols["extended_kb"][0]}',
            f'-DTEST_ENTRY={procedures["test_memory_386"]}',
            f'-DSET_ENTRY={procedures["set_a20_hardware"]}',
            f'-DQUERY_ENTRY={procedures["query_a20_hardware"]}']
        if fault is not None:
            defines += ['-DEXPECT_FAILURE']
        if nmi_phase is not None:
            defines += ['-DEXPECT_NMI']
        run(['nasm', '-f', 'bin', *defines,
             ROOT/'tests/himem_testmem_state_probe.asm', '-o', probe])
        image = directory/'boot.img'
        shutil.copyfile(ROOT/'out/floppy.img', image)
        run(['mcopy', '-o', '-i', image, probe, '::PROBE.COM'])
        for target, content in [('CONFIG.SYS', b'\r\n'),
            ('AUTOEXEC.BAT', b'@ECHO OFF\r\nCTTY AUX\r\nPROBE.COM\r\n')]:
            run(['mcopy', '-o', '-i', image, '-', '::'+target], input=content)
        command = ['qemu-system-i386', '-machine', 'pc', '-cpu', '486', '-m', '16',
            '-d', 'nochain', '-display', 'none', '-monitor', 'none', '-serial', 'stdio',
            '-nic', 'none', '-no-reboot', '-boot', 'a',
            '-drive', f'if=floppy,format=raw,file={image}',
            '-device', 'isa-debug-exit,iobase=0xf4,iosize=0x04']
        result = subprocess.run(command, capture_output=True, timeout=40)
        (directory/'qemu.log').write_bytes(result.stdout+result.stderr)
        passed = result.returncode == 33 and b'HIMEM_TESTMEM_STATE_PASS' in result.stdout
        results.append(dict(name=name, span_kib=span, fault=fault, pattern=phase,
                            nmi_phase=nmi_phase, production=args.production,
                            a20_backend=args.a20_backend, passed=passed))
        (out/'results.json').write_text(json.dumps(results, indent=2)+'\n')
        assert passed, (name, result.stdout, result.stderr)
        print(f'PASS {name}: both A20 entry states, CPU state and memory guard', flush=True)


if __name__ == '__main__':
    main()
