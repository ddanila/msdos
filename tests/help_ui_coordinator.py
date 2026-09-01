#!/usr/bin/env python3
"""Drive and capture the standalone HELP interface through QMP."""

import json
import pathlib
import socket
import sys
import time

qmp_path, output_dir, *mode_arg = sys.argv[1:]
mode = mode_arg[0] if mode_arg else "keyboard"
output = pathlib.Path(output_dir)


def connect():
    deadline = time.time() + 15
    while True:
        try:
            client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            client.connect(qmp_path)
            return client
        except OSError:
            client.close()
            if time.time() >= deadline:
                raise
            time.sleep(0.05)


client = connect()
stream = client.makefile("rwb", buffering=0)
json.loads(stream.readline())
stream.write(b'{"execute":"qmp_capabilities"}\n')
json.loads(stream.readline())


def execute(command):
    request = {
        "execute": "human-monitor-command",
        "arguments": {"command-line": command},
    }
    stream.write(json.dumps(request).encode() + b"\n")
    while True:
        reply = json.loads(stream.readline())
        if "return" in reply or "error" in reply:
            return reply


def capture(name, expected):
    binary = output / (name + ".bin")
    text = output / (name + ".txt")
    deadline = time.time() + 15
    last_reply = None
    while time.time() < deadline:
        last_reply = execute(f'pmemsave 0xb8000 4000 "{binary}"')
        if binary.exists() and binary.stat().st_size == 4000:
            data = binary.read_bytes()
            rendered = "\n".join(
                bytes(data[(row * 160):(row * 160 + 160):2]).decode(
                    "cp437", errors="replace"
                ).rstrip()
                for row in range(25)
            )
            text.write_text(rendered + "\n")
            if expected in rendered:
                return
        time.sleep(0.1)
    raise SystemExit(
        f"HELP screen never showed {expected!r}; last QMP reply: {last_reply!r}"
    )


if mode == "mouse":
    capture("mouse", "Provides ANSI escape-sequence display")
    execute("sendkey esc")
    execute("sendkey esc")
    capture("mouse-restore", "SCREEN_RESTORE_SENTINEL")
    execute("sendkey ret")
else:
    capture("index", "Command index")
    execute("sendkey f3")
    for key in "format":
        execute("sendkey " + key)
    execute("sendkey ret")
    capture("search", "Search results")
    execute("sendkey down")
    execute("sendkey ret")
    capture("topic", "Formats a disk for use with MS-DOS")
    execute("sendkey tab")
    capture("link", "Transfers system files and writes a boot sector")
    execute("sendkey esc")
    execute("sendkey esc")
    capture("restore", "SCREEN_RESTORE_SENTINEL")
    execute("sendkey ret")
stream.close()
client.close()
