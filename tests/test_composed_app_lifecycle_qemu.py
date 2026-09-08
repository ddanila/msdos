#!/usr/bin/env python3
"""Repeat real application jobs on private copies of a frozen composition.

Pinned packages come from dos_app_smoke.json; no deployed SYS transfer or
configuration replacement is allowed on the composed candidate.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import time
import zipfile

from capture_dos_app_smoke import ROOT, ENV, install, package_files, run, sha
from capture_vc_memory_comparison import image_file, partition_offset
from screen_expect import QMPConnection, read_screen_text, send_keys


def digest(data):
    return hashlib.sha256(data).hexdigest()


def wait_screen(qmp, process, directory, marker, seconds=60):
    deadline = time.monotonic() + seconds
    screen = ''
    while process.poll() is None and time.monotonic() < deadline:
        screen = read_screen_text(qmp, str(directory/'vram.bin'))
        if marker in screen:
            (directory/(marker+'.txt')).write_text(screen)
            return screen
        time.sleep(.2)
    (directory/'failed-screen.txt').write_text(screen)
    raise AssertionError((marker, screen))


def verify_outputs(read, cycles, edits):
    """Validate full bytes, archive membership/CRC, and stable arena ownership."""
    snapshots = []
    artifacts = {}
    for i in range(cycles):
        payload = bytes((n * 37 + i * 19) % 256 for n in range(65537 + i * 513))
        expected = {'DATA.BIN': payload, 'NOTE.TXT': f'cycle {i:02d}\r\n'.encode()}
        for name, data in expected.items():
            for path in (f'R{i:02d}/{name}', f'B{i:02d}/{name}'):
                actual = read(path)
                assert actual == data, path
                artifacts[path] = digest(actual)
        archive = read(f'J{i:02d}.ZIP')
        with zipfile.ZipFile(io.BytesIO(archive)) as z:
            assert sorted(z.namelist()) == sorted(expected), z.namelist()
            for name, data in expected.items():
                assert z.read(name) == data, (i, name)
        artifacts[f'J{i:02d}.ZIP'] = digest(archive)
        assert read(f'P{i:02d}.TXT') == f'PIPE_{i:02d}\r\n'.encode()
        snapshot = read(f'M{i:02d}.BIN')
        assert len(snapshot) == 16
        snapshots.append(list(struct.unpack('<8H', snapshot)))
    # Cycle zero warms lazy application/shell state; all subsequent cycles
    # must return to exactly that ownership state, including the final one.
    assert all(row == snapshots[0] for row in snapshots), snapshots
    assert snapshots[0][2] > 0 and snapshots[0][4] > 0
    assert 0 < snapshots[0][6] <= snapshots[0][7]
    for i in range(edits):
        expected = b''.join(f'edit{n} azc\r\n'.encode() for n in reversed(range(i+1))) + b'original\r\n'
        actual = read(f'E{i:02d}.TXT')
        assert actual == expected, (i, actual, expected)
        artifacts[f'E{i:02d}.TXT'] = digest(actual)
        snapshot = read(f'Q{i:02d}.BIN')
        assert list(struct.unpack('<8H', snapshot)) == snapshots[0], (i, snapshot)
    return dict(artifacts_sha256=artifacts, memory_snapshots=snapshots,
                memory_fields=['strategy', 'umb_link', 'low_free_paragraphs',
                               'low_largest_paragraphs', 'upper_free_paragraphs',
                               'upper_largest_paragraphs', 'ems_free_pages', 'ems_total_pages'])


def exercise(label, source, output, packages, cycles, edits, config):
    directory = output/label
    directory.mkdir()
    disk = directory/'boot.img'
    shutil.copyfile(source,disk)
    spec = f'{disk}@@{partition_offset(disk)}'
    run(['mmd','-i',spec,'::LIFE'])
    for name, path in packages.items():
        run(['mmd','-i',spec,'::LIFE/'+name.upper()])
        run(['mcopy','-s','-m','-i',spec,*sorted(path.iterdir()),'::LIFE/'+name.upper()+'/'])
    for target, asm in [('PIPEIO.COM','command_pipe_filter.asm'),
                        ('SNAP.COM','application_memory_snapshot.asm'),('QEXIT.COM','qemu_exit.asm')]:
        run(['nasm','-f','bin',ROOT/'tests'/asm,'-o',directory/target])
        install(disk,'LIFE/'+target,(directory/target).read_bytes())
    # A fresh formatted floppy provides a second DOS block-device path.
    floppy = directory/'media.img'
    run(['mformat','-C','-f','1440','-i',floppy,'::'])
    install(disk,'CONFIG.SYS',config)
    install(disk,'LIFE/EDIT.TXT',b'original\r\n')
    batch = ['@ECHO OFF','PATH C:\\DOS','SET COMSPEC=C:\\DOS\\COMMAND.COM',
             'SET LIFECHECK=ENVIRONMENT_SURVIVED','CD \\LIFE','CTTY AUX']
    for i in range(cycles):
        for prefix in ('S','R','B'):
            run(['mmd','-i',spec,f'::LIFE/{prefix}{i:02d}'])
        payload = bytes((n * 37 + i * 19) % 256 for n in range(65537+i*513))
        install(disk,f'LIFE/S{i:02d}/DATA.BIN',payload)
        install(disk,f'LIFE/S{i:02d}/NOTE.TXT',f'cycle {i:02d}\r\n'.encode())
        batch += [f'4DOS\\4DOS.COM /C C:\\LIFE\\PKZIP\\PKZIP.EXE -ex J{i:02d}.ZIP S{i:02d}\\*.*',
                  'IF ERRORLEVEL 1 GOTO FAIL',
                  f'4DOS\\4DOS.COM /C C:\\LIFE\\PKZIP\\PKUNZIP.EXE J{i:02d}.ZIP R{i:02d}\\',
                  'IF ERRORLEVEL 1 GOTO FAIL',
                  f'COPY /Y /B R{i:02d}\\DATA.BIN A:\\DATA.BIN >NUL', 'IF ERRORLEVEL 1 GOTO FAIL',
                  f'COPY /Y /B A:\\DATA.BIN B{i:02d}\\DATA.BIN >NUL','IF ERRORLEVEL 1 GOTO FAIL',
                  f'COPY /Y R{i:02d}\\NOTE.TXT B{i:02d}\\NOTE.TXT >NUL','IF ERRORLEVEL 1 GOTO FAIL',
                  f'COMMAND /C ECHO PIPE_{i:02d}|PIPEIO|PIPEIO >P{i:02d}.TXT',
                  'IF ERRORLEVEL 1 GOTO FAIL', f'SNAP >M{i:02d}.BIN',
                  'IF ERRORLEVEL 1 GOTO FAIL', f'ECHO CYCLE_{i:02d}_PASS']
    batch += ['ECHO %LIFECHECK%', 'CTTY CON']
    for i in range(edits):
        batch += ['CLS',f'ECHO EDIT_READY_{i:02d}','PAUSE >NUL',
                  'QEDIT\\Q.EXE EDIT.TXT',f'COPY /Y EDIT.TXT E{i:02d}.TXT >NUL',
                  'IF ERRORLEVEL 1 GOTO FAIL',f'SNAP >Q{i:02d}.BIN',
                  'IF ERRORLEVEL 1 GOTO FAIL']
    batch += ['CTTY AUX','ECHO LIFECYCLE_PASS','QEXIT',':FAIL','CTTY AUX','ECHO LIFECYCLE_FAIL']
    autoexec = ('\r\n'.join(batch)+'\r\n').encode()
    install(disk,'AUTOEXEC.BAT',autoexec)
    (directory/'AUTOEXEC.BAT').write_bytes(autoexec)
    (directory/'CONFIG.SYS').write_bytes(config)
    with tempfile.TemporaryDirectory(prefix='life-qmp-') as sockets:
        sock = Path(sockets)/'qmp'
        command = ['qemu-system-i386','-machine','pc','-cpu','486','-m','8','-d','nochain',
                   '-rtc','base=1995-01-02T12:00:00,clock=vm','-display','none','-monitor','none',
                   '-serial',f'file:{directory}/serial.log','-no-reboot','-nic','none','-boot','c',
                   '-drive',f'if=ide,format=raw,file={disk}',
                   '-drive',f'if=floppy,format=raw,file={floppy}',
                   '-qmp',f'unix:{sock},server=on,wait=off',
                   '-device','isa-debug-exit,iobase=0xf4,iosize=0x04']
        (directory/'command.json').write_text(json.dumps(command,indent=2)+'\n')
        with (directory/'qemu.log').open('wb') as log:
            process = subprocess.Popen(command,stdout=log,stderr=log)
            qmp = None
            try:
                qmp = QMPConnection(str(sock),retries=30)
                for i in range(edits):
                    wait_screen(qmp,process,directory,f'EDIT_READY_{i:02d}',
                                seconds=60 + cycles*40 if i == 0 else 60)
                    send_keys(qmp,'ret')
                    screen = wait_screen(qmp,process,directory,'<*** End of File ***>')
                    assert ('original' if i == 0 else f'edit{i-1} azc') in screen
                    # Home, insert a line, correct b to z using the real keyboard,
                    # save via QEdit's File menu and exit via its Quit menu.
                    send_keys(qmp,f'home+e+d+i+t+{i}+spc+a+b+backspace+z+c+ret')
                    wait_screen(qmp,process,directory,f'edit{i} azc')
                    send_keys(qmp,'esc+f+s')
                    time.sleep(.5)
                    send_keys(qmp,'esc+q+x')
                assert process.wait(timeout=40) == 33
            finally:
                if qmp:
                    qmp.close()
                if process.poll() is None:
                    process.kill()
                    process.wait()
    serial = (directory/'serial.log').read_text(encoding='latin-1')
    assert 'LIFECYCLE_PASS' in serial and 'LIFECYCLE_FAIL' not in serial, serial
    assert serial.count('PIPE_FILTER_OVERWRITE') == cycles*2, serial
    assert 'ENVIRONMENT_SURVIVED' in serial
    for i in range(cycles):
        assert f'CYCLE_{i:02d}_PASS' in serial
    captured = {}

    def read(path):
        if path not in captured:
            captured[path] = image_file(disk,'::LIFE/'+path)
        return captured[path]

    result = verify_outputs(read,cycles,edits)
    negatives = {}
    for path in ('R00/DATA.BIN', 'J00.ZIP', 'M01.BIN', 'E00.TXT'):
        bad = bytearray(captured[path])
        bad[0] ^= 1
        try:
            verify_outputs(lambda name:bytes(bad) if name == path else captured[name],cycles,edits)
        except (AssertionError, zipfile.BadZipFile):
            negatives[path] = True
        else:
            raise AssertionError(('corruption escaped oracle',path))
    result['corruption_rejected'] = negatives
    final_floppy = subprocess.check_output(['mtype','-i',str(floppy),'::DATA.BIN'],env=ENV)
    assert final_floppy == captured[f'R{cycles-1:02d}/DATA.BIN']
    result['floppy_final_sha256'] = digest(final_floppy)
    preserved = ['IO.SYS','MSDOS.SYS','COMMAND.COM','DOS/COMMAND.COM',
                 'DOS/HIMEM.SYS','DOS/EMM386.EXE']
    if label == 'composed':
        preserved += ['DOS/SHARE.EXE','DOS/IFSFUNC.EXE','DOS/FILESYS.EXE']
    for name in preserved:
        assert image_file(disk,'::'+name) == image_file(source,'::'+name),name
    result.update(passed=True, directory=str(directory.relative_to(ROOT)),
                  image_sha256=sha(source),config=config.decode(), cycles=cycles,edit_cycles=edits,
                  preserved_system_files=preserved,
                  core_sha256={name:digest(image_file(disk,'::'+name)) for name in
                               ('IO.SYS','MSDOS.SYS','COMMAND.COM','DOS/COMMAND.COM','DOS/HIMEM.SYS','DOS/EMM386.EXE')},
                  application_sha256={name:digest(image_file(disk,'::LIFE/'+name)) for name in
                                      ('4DOS/4DOS.COM','PKZIP/PKZIP.EXE','PKZIP/PKUNZIP.EXE','QEDIT/Q.EXE')})
    assert image_file(disk,'::CONFIG.SYS') == config
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('composition',type=Path)
    parser.add_argument('--retail-image',type=Path,required=True)
    parser.add_argument('--cycles',type=int,default=12)
    parser.add_argument('--edits',type=int,default=4)
    parser.add_argument('--record-baseline',type=Path)
    args = parser.parse_args()
    if args.cycles < 2 or args.cycles > 99 or not 2 <= args.edits <= 10:
        parser.error('require 2..99 job cycles and 2..10 editor cycles')
    source = args.composition.resolve()
    build = json.loads((source/'build.json').read_text())
    candidate = source/'candidate.img'
    assert sha(candidate) == build['image_sha256']
    for name,value in build['installed_sha256'].items():
        assert digest(image_file(candidate,'::'+name)) == value,name
    for name,value in json.loads((source/'source-hashes.json').read_text()).items():
        if name.startswith('src/'):
            assert sha(ROOT/name) == value,name
    retail_reference = json.loads((ROOT/'tests/dos_app_smoke_baseline.json').read_text())
    for name,value in retail_reference['provenance']['systems']['stock'].items():
        assert digest(image_file(args.retail_image,'::'+name)) == value,('retail identity',name)
    config = image_file(candidate,'::CONFIG.SYS')
    output = Path(tempfile.mkdtemp(prefix='composed-app-lifecycle-',dir=ROOT/'out'))
    print(f'Artifacts: {output}',flush=True)
    manifest = json.loads((ROOT/'tests/dos_app_smoke.json').read_text())
    packages, provenance = {}, {}
    # Private extraction avoids disturbing other runs' cached application trees.
    cache = output/'packages'
    cache.mkdir()
    for package in manifest['packages']:
        if package['id'] in ('4dos','pkzip','qedit'):
            archive = package.get('cache_name',package['file'])
            shutil.copyfile(ROOT/'.reference/dos-apps'/archive,cache/archive)
            packages[package['id']],provenance[package['id']] = package_files(package,cache)
    report = dict(schema=1,recorded_at=datetime.now(timezone.utc).isoformat(),
                  source_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT).decode().strip(),
                  candidate=str(candidate.relative_to(ROOT)), candidate_sha256=sha(candidate),
                  build_record_sha256=sha(source/'build.json'), packages=provenance,
                  qemu_version=subprocess.check_output(['qemu-system-i386','--version']).decode().splitlines()[0],
                  command=['python3','tests/test_composed_app_lifecycle_qemu.py',str(args.composition),
                           '--retail-image',str(args.retail_image),'--cycles',str(args.cycles),'--edits',str(args.edits)],
                  remaining_scope=[
                      'Promotion review and applicable release gates remain open.',
                      'Same startup configuration does not imply identical default EMS pool sizing; compare ownership within each system and job output across systems.',
                      'Virtual floppy read/write only; removable-media changes and physical DMA/timing are not covered.',
                      'Only the listed application operations are qualified; DBCS, external hooks and broader exception/A20 contexts remain outside this run.'
                  ],
                  results={}, qualification_passed=False,
                  scope='Repeated archive/EXEC, forced shell reload/pipes, virtual floppy I/O and QEdit editing; no promotion or exhaustive application compatibility claim.')
    (output/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    for label,image in [('composed',candidate),('retail',args.retail_image.resolve())]:
        original = sha(image)
        report['results'][label] = exercise(label,image,output,packages,args.cycles,args.edits,config)
        assert sha(image) == original
        (output/'results.json').write_text(json.dumps(report,indent=2)+'\n')
        print(label,'PASS',flush=True)
    a,b = (report['results'][label] for label in ('composed','retail'))
    assert a['application_sha256'] == b['application_sha256']
    # ZIP metadata can vary with emulated execution time. Compare uncompressed
    # full contents above; compare persisted DOS files directly between systems.
    report['file_contents_match_retail'] = all(value == b['artifacts_sha256'][name]
            for name,value in a['artifacts_sha256'].items() if not name.endswith('.ZIP'))
    assert report['file_contents_match_retail']
    report['qualification_passed'] = True
    report['test_sha256'] = {name:sha(ROOT/'tests'/name) for name in
                            ('test_composed_app_lifecycle_qemu.py','application_memory_snapshot.asm',
                             'command_pipe_filter.asm','qemu_exit.asm','capture_dos_app_smoke.py',
                             'capture_vc_memory_comparison.py','screen_expect.py','dos_app_smoke.json')}
    text = json.dumps(report,indent=2)+'\n'
    (output/'results.json').write_text(text)
    if args.record_baseline:
        args.record_baseline.write_text(text)


if __name__ == '__main__':
    main()
