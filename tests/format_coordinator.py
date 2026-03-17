#!/usr/bin/env python3
"""format_coordinator.py — Serial + QMP coordinator for FORMAT E2E test.

Replaces the continuous N\\r\\n feed.  Processes FORMAT's interactive prompts
in strict order, doing the QMP disk swap at exactly the right moment:

  For each FORMAT variant i:
    1. "press ENTER when ready"  → [swap B: to b_imgs[i] if i > 0], send \\r
    2. "ENTER for none"          → send \\r   (bare CR — empty volume label)
                                   (skipped for variants with /V: on cmd line)
    3. "Format another (Y/N)?"  → send N\\r  (N + bare CR, no LF)
    4. "FORMAT_{name}_DONE"     → save b_imgs[i] → saved_imgs[i], no response

  If FORMAT exits early (e.g. "Parameters not supported") without printing
  the label or Y/N prompts, the DONE marker appears before the expected
  intermediate pattern.  The coordinator detects this via the skip_to field
  and jumps directly to the DONE rule.

Why bare CR (not CR/LF) matters for line-input prompts:
  INT 21h cooked reads (3Fh / USER_STRING) stop at CR but do NOT consume the
  following LF — it stays in the UART FIFO.  Sending \\r\\n would leave \\n in
  the FIFO; a subsequent single-char read would consume it instead of our
  intended response.  Same pattern as test_label.sh fix (commit e1b0f97).

"Format another (Y/N)?" uses a line-input read (stops at CR), NOT a single-
  char read.  Bare N leaves FORMAT waiting for CR and it never exits.  Sending
  N\\r terminates the read cleanly.  CR is consumed as the line terminator so
  the FIFO is empty — the coordinator's next rule sends \\r for "press ENTER
  when ready" only after matching it in serial AND doing the QMP swap.

Usage:
    python3 format_coordinator.py \\
        <serial_in> <serial_out> <serial_log> <qmp_sock> \\
        <n_variants> \\
        <b_img_0> ... <b_img_{n-1}> \\
        <saved_img_0> ... <saved_img_{n-1}>
"""

import os, select, socket, json, sys, shutil

# Names must match AUTOEXEC.BAT ECHO markers exactly.
NAMES = ["VLABEL", "S", "B", "F720", "TN", "FOUR", "ONE", "EIGHT"]

# Indices of variants that have /V:<label> on the command line — FORMAT skips
# the interactive "Volume label (11 characters, ENTER for none)?" prompt.
NO_LABEL_PROMPT = {0}   # index 0 = FORMAT B: /V:TEST


def qmp_change_floppy(sock_path: str, img_path: str) -> None:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(10.0)
        s.connect(sock_path)
        s.recv(4096)                                         # greeting
        s.sendall(b'{"execute":"qmp_capabilities"}\n')
        s.recv(4096)
        cmd = json.dumps({
            "execute": "human-monitor-command",
            "arguments": {"command-line": f"change floppy1 {img_path}"},
        })
        s.sendall(cmd.encode() + b'\n')
        s.recv(4096)
    print(f"  QMP: swapped B: → {img_path}", flush=True)


def build_rules(n: int, b_imgs: list, saved_imgs: list) -> list:
    """Return an ordered list of (pattern, response, hook, skip_to) tuples.

    pattern  : bytes to scan for in the serial buffer
    response : bytes to write to serial_in, or None
    hook     : ('swap', img_path) | ('save', src, dst) | None
    skip_to  : index of the DONE rule for this variant, or None for the DONE
               rule itself.  When looking for an intermediate prompt and the
               DONE marker appears first (FORMAT exited early), the coordinator
               jumps directly to skip_to without sending a response.
    """
    rules = []
    for i in range(n):
        variant_start = len(rules)

        # "press ENTER when ready" — swap disk first (except for the very first FORMAT)
        hook = ('swap', b_imgs[i]) if i > 0 else None
        rules.append([b"press ENTER when ready", b'\r', hook, None])  # skip_to filled below

        # Interactive volume label prompt — absent when /V: given on command line
        if i not in NO_LABEL_PROMPT:
            rules.append([b"ENTER for none", b'\r', None, None])

        # "Format another (Y/N)?" — N + CR only (no LF).
        # FORMAT uses a line-input read that stops at CR; bare N hangs waiting
        # for CR.  Sending N\r terminates the read.  No \n so the FIFO is
        # empty afterwards (CR is consumed as the line terminator).
        rules.append([b"Format another", b'N\r', None, None])

        done_idx = len(rules)

        # Batch DONE marker — save image, no serial response, no skip_to
        rules.append([
            f"FORMAT_{NAMES[i]}_DONE".encode(),
            None,
            ('save', b_imgs[i], saved_imgs[i]),
            None,
        ])

        # Back-fill skip_to for all rules of this variant (so if DONE appears
        # before an intermediate prompt, the coordinator can jump ahead).
        for j in range(variant_start, done_idx):
            rules[j][3] = done_idx

    return [tuple(r) for r in rules]


def main() -> None:
    args = sys.argv[1:]
    if len(args) < 5:
        sys.exit("usage: format_coordinator.py serial_in serial_out serial_log "
                 "qmp_sock n b_img_0..n-1 saved_img_0..n-1")

    serial_in  = args[0]
    serial_out = args[1]
    serial_log = args[2]
    qmp_sock   = args[3]
    n          = int(args[4])
    b_imgs     = args[5:5 + n]
    saved_imgs = args[5 + n:5 + 2 * n]

    if len(b_imgs) != n or len(saved_imgs) != n:
        sys.exit(f"Expected {n} b_imgs and {n} saved_imgs, "
                 f"got {len(b_imgs)} and {len(saved_imgs)}")

    rules    = build_rules(n, b_imgs, saved_imgs)
    rule_idx = 0

    fin  = open(serial_in,  'wb', buffering=0)
    fout = open(serial_out, 'rb', buffering=0)
    log  = open(serial_log, 'wb')

    buf = bytearray()

    try:
        while True:
            r, _, _ = select.select([fout], [], [], 0.5)
            if not r:
                continue
            chunk = os.read(fout.fileno(), 512)
            if not chunk:
                break   # EOF: QEMU exited
            log.write(chunk); log.flush()
            buf.extend(chunk)
            if len(buf) > 65536:
                buf = buf[-65536:]

            # Drain as many consecutive rules as the buffer satisfies
            while rule_idx < len(rules):
                pattern, response, hook, skip_to = rules[rule_idx]

                # If FORMAT exited early (before this prompt), the DONE marker
                # appears before the expected pattern.  Jump to the DONE rule.
                if skip_to is not None:
                    done_pattern = rules[skip_to][0]
                    if buf.find(done_pattern) >= 0:
                        print(f"  rule[{rule_idx}] SKIPPED (DONE marker appeared early)",
                              flush=True)
                        rule_idx = skip_to
                        continue

                idx = buf.find(pattern)
                if idx < 0:
                    break   # current rule not in buffer yet — keep reading
                buf = buf[idx + len(pattern):]   # consume up to end of pattern
                print(f"  rule[{rule_idx}] matched: {pattern.decode(errors='replace')[:50]}",
                      flush=True)
                if hook:
                    kind = hook[0]
                    if kind == 'swap':
                        qmp_change_floppy(qmp_sock, hook[1])
                    elif kind == 'save':
                        shutil.copy(hook[1], hook[2])
                        print(f"  Saved {hook[2]}", flush=True)
                if response:
                    fin.write(response); fin.flush()
                rule_idx += 1

    finally:
        fin.close()
        fout.close()
        log.close()
        print(f"Coordinator done: {rule_idx}/{len(rules)} rules processed.", flush=True)


if __name__ == '__main__':
    main()
