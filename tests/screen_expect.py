#!/usr/bin/env python3
"""screen_expect.py — Video memory pattern matcher for QEMU E2E tests.

Reads text-mode video memory (B800:0000, 80x25) via QMP, matches patterns
in screen text, sends keystrokes.  Like serial_expect.py but for full-screen
DOS programs that write directly to video RAM (INT 10h) and read keyboard
via INT 16h — neither of which goes through CTTY AUX / serial.

Architecture:
  1. Connect to QEMU via QMP unix socket
  2. Poll: dump 4000 bytes from physical 0xB8000 (color text mode)
  3. Extract character bytes (skip attribute bytes), form 80x25 text
  4. Strip trailing whitespace per line, collapse into searchable string
  5. Match next rule's pattern as substring
  6. On match: send keystrokes via QMP send-key, advance to next rule
  7. After all rules: capture final screen for verification

Video memory layout (CGA/EGA/VGA text mode):
  Physical 0xB8000..0xB8F9F = 4000 bytes = 2000 (char, attr) pairs
  Row 0: bytes 0..159,  Row 1: bytes 160..319, ...  Row 24: bytes 3840..3999
  Character at (row, col) = byte at offset (row * 160 + col * 2)

Usage:
    python3 screen_expect.py <qmp_sock> <screen_log> \\
        'pattern1' 'key1[+key2+...]' \\
        'pattern2' 'key1[+key2+...]' ...

Keys: ret, esc, up, down, left, right, a-z, 0-9, spc, tab, backspace, etc.
Multiple keys in sequence separated by '+': 'y+ret' sends Y then Enter.
Delay between keystrokes: 50ms (sufficient for BIOS keyboard buffer).

Example:
    python3 tests/screen_expect.py /tmp/qmp.sock /tmp/screen.log \\
        'Insert' 'ret' \\
        'Invalid Parameters' 'ret'
"""

import json, os, socket, sys, time, tempfile


VRAM_PHYS = 0xB8000     # Color text mode base address
VRAM_SIZE = 4000         # 80 * 25 * 2 (char + attr pairs)
COLS = 80
ROWS = 25
POLL_INTERVAL = 0.3      # seconds between screen reads
KEY_DELAY = 0.05         # seconds between keystrokes
TIMEOUT = 120            # seconds total before giving up


class QMPConnection:
    """Persistent QMP connection to QEMU.

    Handles the QMP greeting, capability negotiation, and filters out
    async events ({"event": ...}) that QEMU sends between commands.
    """

    def __init__(self, sock_path: str, retries: int = 10):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(10.0)
        # Retry connection — QEMU may still be initializing
        for attempt in range(retries):
            try:
                self.sock.connect(sock_path)
                break
            except (ConnectionRefusedError, FileNotFoundError):
                if attempt == retries - 1:
                    raise
                time.sleep(0.5)
        self._buf = b''
        self._recv_json()                                     # greeting
        self._send({"execute": "qmp_capabilities"})
        self._recv_json()

    def _send(self, obj: dict) -> None:
        self.sock.sendall(json.dumps(obj).encode() + b'\n')

    def _recv_json(self) -> dict:
        """Read one complete JSON object from the socket.

        QMP sends newline-delimited JSON.  Async events may arrive at any
        time; this method returns the first complete JSON object found.
        """
        while True:
            # Try to parse a complete JSON object from accumulated buffer
            nl = self._buf.find(b'\n')
            if nl >= 0:
                line = self._buf[:nl]
                self._buf = self._buf[nl + 1:]
                if line.strip():
                    try:
                        return json.loads(line)
                    except json.JSONDecodeError:
                        pass  # malformed line, skip
            else:
                # Need more data
                chunk = self.sock.recv(65536)
                if not chunk:
                    raise ConnectionError("QMP connection closed")
                self._buf += chunk

    def _recv_response(self) -> dict:
        """Read until we get a command response (skip async events)."""
        while True:
            obj = self._recv_json()
            if "return" in obj or "error" in obj:
                return obj
            # else: async event like {"event": "..."} — skip

    def human_cmd(self, cmd_line: str) -> str:
        """Run a human monitor command, return the string result."""
        self._send({
            "execute": "human-monitor-command",
            "arguments": {"command-line": cmd_line},
        })
        resp = self._recv_response()
        return resp.get("return", "")

    def send_key(self, qcode: str) -> None:
        """Send a single keystroke via QMP."""
        self._send({
            "execute": "send-key",
            "arguments": {"keys": [{"type": "qcode", "data": qcode}]},
        })
        self._recv_response()

    def close(self) -> None:
        self.sock.close()


def read_screen_text(qmp: QMPConnection, tmp_path: str) -> str:
    """Dump video memory via QMP pmemsave and extract screen text.

    Returns a single string: 25 lines joined by newlines, trailing
    whitespace stripped per line.
    """
    qmp.human_cmd(f'pmemsave 0x{VRAM_PHYS:X} {VRAM_SIZE} "{tmp_path}"')
    try:
        with open(tmp_path, 'rb') as f:
            raw = f.read(VRAM_SIZE)
    except FileNotFoundError:
        return ""
    if len(raw) < VRAM_SIZE:
        return ""

    # Extract character bytes (even offsets), skip attribute bytes (odd offsets)
    chars = bytes(raw[i] for i in range(0, VRAM_SIZE, 2))

    lines = []
    for row in range(ROWS):
        line = chars[row * COLS:(row + 1) * COLS]
        # Decode as CP437 (DOS code page), strip trailing whitespace
        lines.append(line.decode('cp437', errors='replace').rstrip())
    return '\n'.join(lines)


def send_keys(qmp: QMPConnection, keys_str: str) -> None:
    """Send a sequence of keystrokes.  Keys separated by '+'."""
    for key in keys_str.split('+'):
        key = key.strip()
        if not key:
            continue
        qmp.send_key(key)
        time.sleep(KEY_DELAY)


def main() -> None:
    args = sys.argv[1:]
    if len(args) < 4 or len(args) % 2 != 0:
        sys.exit("usage: screen_expect.py qmp_sock screen_log "
                 "[pattern response]...")

    qmp_sock = args[0]
    log_path = args[1]
    rules = [(args[i], args[i + 1]) for i in range(2, len(args), 2)]

    print(f"screen_expect: {len(rules)} rules, connecting to {qmp_sock}",
          flush=True)

    qmp = QMPConnection(qmp_sock)
    rule_idx = 0
    deadline = time.monotonic() + TIMEOUT

    with tempfile.NamedTemporaryFile(suffix='.bin', delete=False) as tmp:
        tmp_path = tmp.name

    log = open(log_path, 'w')

    try:
        while rule_idx < len(rules) and time.monotonic() < deadline:
            screen = read_screen_text(qmp, tmp_path)
            if not screen:
                time.sleep(POLL_INTERVAL)
                continue

            pattern, response = rules[rule_idx]

            if pattern in screen:
                log.write(f"=== Rule {rule_idx}: matched '{pattern}' ===\n")
                log.write(screen + '\n\n')
                print(f"  rule[{rule_idx}] matched: {pattern[:60]}", flush=True)
                send_keys(qmp, response)
                rule_idx += 1
                # Brief pause after sending keys to let DOS process them
                time.sleep(0.5)
            else:
                time.sleep(POLL_INTERVAL)

        # Capture final screen
        time.sleep(1.0)
        screen = read_screen_text(qmp, tmp_path)
        log.write("=== Final screen ===\n")
        log.write(screen + '\n')

        if rule_idx < len(rules):
            log.write(f"\nTIMEOUT: only {rule_idx}/{len(rules)} rules matched\n")
            print(f"screen_expect: TIMEOUT after {TIMEOUT}s — "
                  f"{rule_idx}/{len(rules)} rules matched", flush=True)
        else:
            print(f"screen_expect: all {len(rules)} rules matched.", flush=True)

    finally:
        log.close()
        os.unlink(tmp_path)
        qmp.close()


if __name__ == '__main__':
    main()
