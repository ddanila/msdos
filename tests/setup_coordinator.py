#!/usr/bin/env python3
"""Swap Setup Disk 2 into A: when the DOS installer requests it."""

import json
import os
import select
import socket
import sys
import time


serial_in, serial_out, log_path, qmp_path, disk2 = sys.argv[1:]


def change_disk() -> None:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        deadline = time.time() + 10
        while True:
            try:
                sock.connect(qmp_path)
                break
            except OSError:
                if time.time() >= deadline:
                    raise
                time.sleep(0.05)
        sock.recv(4096)
        sock.sendall(b'{"execute":"qmp_capabilities"}\n')
        sock.recv(4096)
        command = json.dumps({
            "execute": "human-monitor-command",
            "arguments": {"command-line": f"change floppy0 {disk2}"},
        })
        sock.sendall(command.encode() + b"\n")
        sock.recv(4096)


in_fd = os.open(serial_in, os.O_WRONLY)
out_fd = os.open(serial_out, os.O_RDONLY | os.O_NONBLOCK)
buffer = bytearray()
swapped = False
deadline = time.time() + 90
with open(log_path, "wb") as log:
    while time.time() < deadline:
        ready, _, _ = select.select([out_fd], [], [], 0.2)
        if ready:
            chunk = os.read(out_fd, 4096)
            if chunk:
                log.write(chunk)
                log.flush()
                buffer += chunk
                if not swapped and b"Insert MS-DOS 6.22 Disk 2" in buffer:
                    change_disk()
                    os.write(in_fd, b"\r")
                    swapped = True
                if b"Setup completed successfully" in buffer or b"Setup could not complete" in buffer:
                    break
os.close(in_fd)
os.close(out_fd)
if not swapped:
    raise SystemExit("Setup never requested Disk 2")
