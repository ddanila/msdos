#!/usr/bin/env python3
"""Qualify software reboot in a private frozen composition, never QMP reset."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from build_bios_low_image import ROOT
from capture_vc_memory_comparison import image_file, partition_offset
from report_dos_bios_residency import parse_map
from test_dos_char_retirement_qemu import install


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("bios", type=Path)
    parser.add_argument("--emm-build", type=Path,
                        help="matched EMM386.EXE/EMM386.MAP directory for the installed reboot hook")
    parser.add_argument("--bad-emm-chain", action="store_true",
                        help="negative control: corrupt EMM386's saved BIOS entry; must fail")
    args = parser.parse_args()
    if args.bad_emm_chain and not args.emm_build:
        parser.error("--bad-emm-chain requires --emm-build")
    assert image_file(args.image,"::IO.SYS") == (args.bios/"IO.SYS").read_bytes()
    assert image_file(args.image,"::MSDOS.SYS") == (ROOT/"src/DOS/MSDOS.SYS").read_bytes()
    listing = subprocess.check_output(["mdir", "-b", "-i",
        f"{args.image}@@{partition_offset(args.image)}", "::/"])
    if any(line.upper().endswith(b"/SWBOOT.TAG") for line in listing.splitlines()):
        raise ValueError("input contains SWBOOT.TAG; use a clean frozen image")
    work = Path(tempfile.mkdtemp(prefix="bios-int19-",dir=ROOT/"out"))
    print(f"Artifacts: {work}",flush=True)
    segments,symbols = parse_map(args.bios/"msBIO.map")
    symbols = {k.upper():v for k,v in symbols.items()}
    definitions = "".join(f"%define {key} {symbols[value]}\n" for key,value in
        (("ORIG19","ORIG19"),("OLD13","OLD13"),("OLD_VECTORS","INT19OLD02"),("ENTRY19","INT19")))
    emm_hash = None
    if args.emm_build:
        emm = (args.emm_build/"EMM386.EXE").read_bytes()
        assert image_file(args.image,"::DOS/EMM386.EXE") == emm
        emm_hash = hashlib.sha256(emm).hexdigest()
        emm_segments, emm_symbols = parse_map(args.emm_build/"EMM386.MAP")
        base = emm_segments["R_CODE"].paragraph*16 + emm_segments["R_CODE"].offset
        for key, name in (("EMM_ENTRY19", "i19_Entry"), ("EMM_OLD19", "i19_Old")):
            offset = emm_symbols[name] - base
            assert 0 <= offset < emm_segments["R_CODE"].size
            definitions += f"%define {key} {offset}\n"
        if args.bad_emm_chain:
            definitions += "%define BAD_EMM_CHAIN 1\n"
    (work/"int19-defs.inc").write_text(definitions)
    init = segments["SYSINITSEG"].paragraph*16+segments["SYSINITSEG"].offset
    manifest = json.loads((args.bios/"low.json").read_text())
    upper = manifest["high_stack_pool"] and not manifest["fail_stack_pool"]
    (work/"stack-defs.inc").write_text(f"%define EXPECT_UPPER {int(upper)}\n%define EXPECT_DOS_HIGH 1\n"
        f"%define ENTRY_OFFSET {symbols['INT08']-init}\n%define OLD_SLOT {symbols['OLD08']-init}\n")
    image=work/"boot.img"
    shutil.copyfile(args.image,image)
    for source,target in (("bios_int19_probe.asm","SWBOOT.COM"),("stack_pool_probe.asm","STACKCHK.COM"),
                          ("int21_fcb_probe.asm","I21FCB.COM")):
        subprocess.run(["nasm","-f","bin",f"-I{work}/",ROOT/"tests"/source,"-o",work/target],check=True)
        install(image,target,(work/target).read_bytes())
    install(image,"AUTOEXEC.BAT",b"@ECHO OFF\r\nCTTY AUX\r\nSTACKCHK.COM\r\nSWBOOT.COM\r\nI21FCB.COM\r\n")
    command=["qemu-system-i386","-machine","pc","-cpu","486","-m","8",
            "-display","none","-monitor","none","-serial","stdio","-boot","c",
            "-debugcon",f"file:{work/'debug.log'}","-device","isa-debug-exit,iobase=0xf4,iosize=0x04",
            "-drive",f"if=ide,index=0,format=raw,file={image},cache=writethrough"]
    try:
        result=subprocess.run(command,
            stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=40)
        code,output=result.returncode,result.stdout
    except subprocess.TimeoutExpired as error:
        code,output=None,error.stdout or b""
    (work/"serial.log").write_bytes(output)
    trace=(work/"debug.log").read_bytes()
    report=dict(exit_code=code,vectors_restored=trace.count(b"BIOS_INT19_VECTORS_PASS")==1,
        second_boot=trace.count(b"BIOS_INT19_SECOND_BOOT_PASS")==1,
        stack_passes=trace.count(b"STACK_POOL_NESTED_PASS"),fcb_pass=b"INT21_FCB_PASS" in output,
        input_sha256=hashlib.sha256(args.image.read_bytes()).hexdigest(),
        expected_upper=upper, emm_sha256=emm_hash, bad_emm_chain=args.bad_emm_chain,
        emm_chain_pass=trace.count(b"BIOS_INT19_EMM_CHAIN_PASS")==1,
        probe_sha256=hashlib.sha256((work/"SWBOOT.COM").read_bytes()).hexdigest(),
        config=image_file(args.image,"::CONFIG.SYS").decode("ascii"),
        emulator_command=command,
        qemu_version=subprocess.check_output(["qemu-system-i386","--version"],text=True).splitlines()[0])
    (work/"result.json").write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps(report,indent=2),flush=True)
    assert code==33 and report["vectors_restored"] and report["second_boot"]
    assert report["stack_passes"]==2 and report["fcb_pass"] and b"BIOS_INT19_FAIL" not in trace
    assert not args.emm_build or report["emm_chain_pass"]


if __name__=="__main__":
    main()
