#!/usr/bin/env python3
"""Watch a low-pool boundary from initialization to its first changed value.

Local DOS images only. QEMU uses a disposable disk snapshot; no binary patches.
"""
import argparse
import hashlib
import json
from pathlib import Path
import socket
import re
import struct
import subprocess
import tempfile
import time

from build_bios_low_image import ROOT
from capture_vc_memory_comparison import image_file
from screen_expect import QMPConnection


class Remote:
    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(35)
        for attempt in range(100):
            try:
                self.sock.connect(str(path))
                break
            except (FileNotFoundError, ConnectionRefusedError):
                if attempt == 99:
                    raise
                time.sleep(.02)

    def packet(self, command):
        data = command.encode()
        self.sock.sendall(b"$" + data + b"#" + f"{sum(data)%256:02x}".encode())
        while True:
            byte = self.sock.recv(1)
            if not byte:
                raise EOFError("debugger disconnected")
            if byte == b"$":
                break
            if byte == b"-":
                raise ValueError("debugger rejected packet")
        reply = bytearray()
        while (byte := self.sock.recv(1)) != b"#":
            if not byte:
                raise EOFError("partial debugger packet")
            reply += byte
        checksum = b""
        while len(checksum) < 2:
            part = self.sock.recv(2-len(checksum))
            if not part:
                raise EOFError("partial debugger checksum")
            checksum += part
        assert sum(reply)%256 == int(checksum,16)
        self.sock.sendall(b"+")
        return reply.decode()

    def memory(self, address, size):
        data = bytes.fromhex(self.packet(f"m{address:x},{size:x}"))
        assert len(data) == size
        return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--code-segment", type=lambda x:int(x,0), default=0x3be)
    parser.add_argument("--pool-segment", type=lambda x:int(x,0), default=0x3e4)
    parser.add_argument("--count", type=int, default=8)
    parser.add_argument("--size", type=int, default=32)
    args = parser.parse_args()
    assert image_file(args.image, "::MSDOS.SYS") == (ROOT / "src/DOS/MSDOS.SYS").read_bytes()
    image_hash = hashlib.sha256(args.image.read_bytes()).hexdigest()
    assert 8 <= args.count <= 64 and 32 <= args.size <= 512
    entry = args.count-2
    offset = args.count*8+(entry+1)*args.size-2
    address = args.pool_segment*16+offset
    assert 0 < args.code_segment < args.pool_segment and address+2 < 0xa0000
    work = Path(tempfile.mkdtemp(prefix="stack-write-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    process = subprocess.Popen(["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
        "-display", "none", "-monitor", "none", "-serial", "none", "-no-reboot", "-boot", "c", "-S",
        "-gdb", f"unix:{work/'gdb'},server=on,wait=off", "-qmp", f"unix:{work/'qmp'},server=on,wait=off",
        "-drive", f"if=ide,index=0,format=raw,file={args.image.resolve()},snapshot=on"],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    remote = None
    records, armed = [], False
    try:
        remote = Remote(work / "gdb")
        assert remote.packet(f"Z2,{address:x},2") == "OK"
        for index in range(10000):
            stop = remote.packet("c")
            assert stop.startswith("T"), stop
            value = int.from_bytes(remote.memory(address,2),"little")
            header = struct.unpack("<6H", remote.memory(args.code_segment*16,12))
            row = dict(stop=stop, value=value, header=header)
            records.append(row)
            if not armed:
                if (value == entry*8 and header[1] == args.count and header[3] == args.size
                        and header[4:] == (0,args.pool_segment)):
                    armed = True
                    print(f"Initialized marker {address:05X}={value:04X}; watching subsequent writes", flush=True)
                continue
            if value == entry*8:
                continue
            row["registers"] = remote.packet("g")
            qmp = QMPConnection(str(work / "qmp"))
            try:
                row["cpu"] = qmp.human_cmd("info registers")
                (work / "registers.log").write_text(row["cpu"])
                row["stack_window"] = remote.memory(args.pool_segment*16+offset-32,64).hex()
                ip = int(re.search(r"EIP=([0-9a-fA-F]+)", row["cpu"])[1],16)
                base = int(re.search(r"CS =[0-9a-fA-F]+ ([0-9a-fA-F]+)", row["cpu"])[1],16)
                # This diagnostic accepts only the observed 16-bit real/v86
                # writer; never decode an unknown protected-mode code segment.
                assert "DS16" in row["cpu"].split("CS =",1)[1].splitlines()[0]
                row["code_address"] = base+ip-16
                code = work / "writer.bin"
                code.write_bytes(remote.memory(row["code_address"],64))
                row["code"] = code.read_bytes().hex()
                (work / "writer.dis").write_bytes(subprocess.check_output([
                    "ndisasm", "-b", "16", "-o", str(row["code_address"]), code]))
            finally:
                qmp.close()
            print(row["cpu"], flush=True)
            print(f"First changed marker: {entry*8:04X} -> {value:04X}", flush=True)
            break
        else:
            raise RuntimeError("watchpoint limit reached before corruption")
    finally:
        (work / "watch.json").write_text(json.dumps(dict(address=address, expected=entry*8,
            image_sha256=image_hash,
            armed=armed, observations=records), indent=2)+"\n")
        if remote:
            remote.sock.close()
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


if __name__ == "__main__":
    main()
