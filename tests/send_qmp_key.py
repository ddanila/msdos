#!/usr/bin/env python3
"""Inject one key through a QEMU QMP socket after an optional delay."""

import json
import socket
import sys
import time


if len(sys.argv) not in (3, 4):
    raise SystemExit("usage: send_qmp_key.py socket qcode [delay-seconds]")

time.sleep(float(sys.argv[3]) if len(sys.argv) == 4 else 0.0)
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
    conn.connect(sys.argv[1])
    stream = conn.makefile("rwb", buffering=0)
    json.loads(stream.readline())
    stream.write(b'{"execute":"qmp_capabilities"}\n')
    json.loads(stream.readline())
    request = {
        "execute": "send-key",
        "arguments": {"keys": [{"type": "qcode", "data": sys.argv[2]}]},
    }
    stream.write(json.dumps(request).encode("ascii") + b"\n")
    while True:
        response = json.loads(stream.readline())
        if "return" in response or "error" in response:
            break
