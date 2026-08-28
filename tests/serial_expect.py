#!/usr/bin/env python3
"""serial_expect.py — real-time serial I/O coordinator for QEMU interactive tests.

Usage:
    python3 serial_expect.py <in_fifo> <out_fifo> <log_file> \
        <pattern1> <response1> [<pattern2> <response2> ...]

Reads raw bytes from <out_fifo> (QEMU serial output → host), logs them to <log_file>,
and scans for each pattern in order.  When a pattern is found, the corresponding
response is written to <in_fifo> (host → QEMU serial input / DOS stdin).

Responses support C-style escapes: \\r → CR (0x0D), \\n → LF (0x0A),
\\t → TAB, and \\xNN → an arbitrary byte.

FIFO setup (caller must do this before starting QEMU):
    mkfifo "$SERIAL_IN" "$SERIAL_OUT"
    exec 3<>"$SERIAL_IN"
    python3 serial_expect.py "$SERIAL_IN" "$SERIAL_OUT" "$SERIAL_LOG" ...
    exec 3>&-

Why O_RDWR on $SERIAL_IN:
    QEMU opens pipe.in with O_RDONLY which blocks until a writer exists.
    Our 'exec 3<>"$SERIAL_IN"' opens the FIFO with O_RDWR (both ends), so
    QEMU's O_RDONLY open finds an existing writer and does not block.
    When Python opens $SERIAL_IN for O_WRONLY it also does not block.

Pattern matching:
    Patterns are matched against a sliding buffer of the last 8 KB.
    Each pattern is matched at most once and in the order given.
    After all patterns fire, the coordinator keeps running until EOF (QEMU exit).
"""

import os, select, sys, re, time

def decode_response(s: str) -> bytes:
    s = re.sub(r'\\x([0-9a-fA-F]{2})', lambda match: chr(int(match.group(1), 16)), s)
    return s.replace('\\r', '\r').replace('\\n', '\n').replace('\\t', '\t').encode('latin-1')

def main():
    if len(sys.argv) < 4 or (len(sys.argv) - 4) % 2 != 0:
        sys.exit("usage: serial_expect.py in_fifo out_fifo log [pattern response ...]")

    in_path   = sys.argv[1]
    out_path  = sys.argv[2]
    log_path  = sys.argv[3]
    pairs     = sys.argv[4:]
    rules     = [(pairs[i].encode(), decode_response(pairs[i+1]))
                 for i in range(0, len(pairs), 2)]

    # The caller holds the FIFO read end as O_RDWR so this write-only open cannot block.
    fin  = open(in_path,  'wb', buffering=0)
    fout = open(out_path, 'rb', buffering=0)
    log  = open(log_path, 'wb')

    buf   = bytearray()
    idx   = 0
    fired = False

    try:
        while True:
            r, _, _ = select.select([fout], [], [], 0.5)
            if not r:
                continue
            chunk = os.read(fout.fileno(), 512)
            if not chunk:
                break
            log.write(chunk)
            log.flush()
            buf.extend(chunk)
            if len(buf) > 8192:
                buf = buf[-8192:]

            if idx < len(rules):
                pat, resp = rules[idx]
                if pat in buf:
                    fin.write(resp)
                    fin.flush()
                    buf.clear()
                    idx += 1
    finally:
        fin.close()
        fout.close()
        log.close()

if __name__ == '__main__':
    main()
