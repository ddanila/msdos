#!/usr/bin/env python3
"""Compare production bootstrap cancellation with a manager-free control."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

from build_bios_low_image import ROOT, build
from capture_vc_memory_comparison import image_file
from test_dos_char_retirement_qemu import install


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('composition',type=Path)
    args=parser.parse_args()
    source=args.composition.resolve()
    record=json.loads((source/'build.json').read_text())
    image=source/'candidate.img'
    assert sha(image)==record['image_sha256']
    for name,value in record['installed_sha256'].items():
        assert hashlib.sha256(image_file(image,'::'+name)).hexdigest()==value,name
    for name,value in json.loads((source/'source-hashes.json').read_text()).items():
        if name.startswith('src/'):
            assert sha(ROOT/name)==value,name
    work=Path(tempfile.mkdtemp(prefix='composed-provider-cancel-',dir=ROOT/'out'))
    print(f'Artifacts: {work}',flush=True)
    report=dict(input_sha256=sha(image),runner_sha256=sha(Path(__file__)),results={})
    emm=source/'provider/MEMM/MEMM/EMM386.EXE'
    counts=[]
    for label in ('himem-only','cancel'):
        directory=work/label
        directory.mkdir()
        build(directory/'bios',paired_provider=emm,provider_cancel=label=='cancel',**record['bios_options'])
        if label=='himem-only':
            assert sha(directory/'bios/IO.SYS')==record['installed_sha256']['IO.SYS']
        disk=directory/'boot.img'
        shutil.copyfile(image,disk)
        install(disk,'IO.SYS',(directory/'bios/IO.SYS').read_bytes())
        config=image_file(image,'::CONFIG.SYS')
        if label=='himem-only':
            config=b'\r\n'.join(line for line in config.splitlines() if b'EMM386.EXE' not in line.upper())+b'\r\n'
        install(disk,'CONFIG.SYS',config)
        for asm,target in [('composed_xms_restore_probe.asm','XMSCHK.COM'),
                           ('umb_provider_absence_probe.asm','NOUMB.COM'),('qemu_exit.asm','QEXIT.COM')]:
            subprocess.run(['nasm','-f','bin',ROOT/'tests'/asm,'-o',directory/target],check=True)
            install(disk,target,(directory/target).read_bytes())
        install(disk,'AUTOEXEC.BAT',b'@ECHO OFF\r\nCTTY AUX\r\nXMSCHK.COM\r\nNOUMB.COM\r\nQEXIT.COM\r\n')
        command=['qemu-system-i386','-machine','pc','-cpu','486','-m','8','-display','none',
                 '-monitor','none','-serial','stdio','-no-reboot','-boot','c',
                 '-debugcon',f'file:{directory}/debug.log','-device','isa-debug-exit,iobase=0xf4,iosize=0x04',
                 '-drive',f'if=ide,format=raw,file={disk},cache=writethrough']
        result=subprocess.run(command,capture_output=True,timeout=60)
        output=result.stdout+result.stderr
        (directory/'serial.log').write_bytes(output)
        assert result.returncode==33 and b'XMS_RESTORE_PASS' in output and b'UMB_PROVIDER_ABSENT_PASS' in output,output
        assert b'_FAIL' not in output,output
        values=struct.unpack('<2H',image_file(disk,'::XMSCOUNT.BIN'))
        counts.append(values)
        report['results'][label]=dict(command=command,config=config.decode(),exit_code=result.returncode,
            xms_largest_kib=values[0],xms_total_kib=values[1],bios_sha256=sha(directory/'bios/IO.SYS'),
            serial_sha256=sha(directory/'serial.log'),passed=True)
        (work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
        print(f'{label} PASS',flush=True)
    assert counts[0]==counts[1], 'cancellation leaked or changed XMS ownership'
    assert sha(image)==report['input_sha256']
    report['restored_exact_xms_capacity']=True
    (work/'results.json').write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
