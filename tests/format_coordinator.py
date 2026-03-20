#!/usr/bin/env python3
"""format_coordinator.py — Serial + QMP coordinator for FORMAT E2E test.

Replaces the continuous N\\r\\n feed.  Processes FORMAT's interactive prompts
in strict order, doing the QMP disk swap at exactly the right moment:

  For each FORMAT variant i:
    0. "---FORMAT-{name}---"    → [swap B: to b_imgs[i] if i > 0], no response
                                   (batch marker always appears before FORMAT runs)
    1. "press ENTER when ready"  → send \\r
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
        <n_variants> <names_csv> <no_label_csv> \\
        <b_img_0> ... <b_img_{n-1}> \\
        <saved_img_0> ... <saved_img_{n-1}>

    names_csv      : comma-separated variant names matching AUTOEXEC.BAT ECHO
                     markers (e.g. "VLABEL,S,B")
    no_label_csv   : comma-separated names of variants whose FORMAT command
                     includes /V:<label> so FORMAT skips the volume-label prompt
                     (e.g. "VLABEL"); use "" for none
"""

import os, select, socket, json, sys, shutil, time


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


def build_rules(n: int, names: list, no_label_prompt: set,
                b_imgs: list, saved_imgs: list) -> list:
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
        marker_rule_idx = None

        # Pre-swap: trigger on batch marker (---FORMAT-<NAME>---).
        # The swap happens here instead of on "press ENTER" so that variants
        # which suppress all prompts (/SELECT, /AUTOTEST) still get a fresh
        # B: image.  The batch marker always appears before FORMAT runs.
        if i > 0:
            marker_rule_idx = len(rules)
            rules.append([f"---FORMAT-{names[i]}---".encode(), None,
                          ('swap', b_imgs[i]), None])

        # "press ENTER when ready" — just send \r (swap already done above)
        rules.append([b"press ENTER when ready", b'\r', None, None])  # skip_to filled below

        # Interactive volume label prompt — absent when /V: given on command line
        if i not in no_label_prompt:
            rules.append([b"ENTER for none", b'\r', None, None])

        # "Format another (Y/N)?" — N + CR only (no LF).
        # FORMAT uses a line-input read that stops at CR; bare N hangs waiting
        # for CR.  Sending N\r terminates the read.  No \n so the FIFO is
        # empty afterwards (CR is consumed as the line terminator).
        rules.append([b"Format another", b'N\r', None, None])

        done_idx = len(rules)

        # Batch DONE marker — save image, no serial response, no skip_to
        rules.append([
            f"FORMAT_{names[i]}_DONE".encode(),
            None,
            ('save', b_imgs[i], saved_imgs[i]),
            None,
        ])

        # Back-fill skip_to for all rules of this variant (so if DONE appears
        # before an intermediate prompt, the coordinator can jump ahead).
        for j in range(variant_start, done_idx):
            rules[j][3] = done_idx
        # The batch marker swap rule must always fire — never skip it.
        # (The marker always appears before DONE in the serial stream.)
        if marker_rule_idx is not None:
            rules[marker_rule_idx][3] = None

    return [tuple(r) for r in rules]


def main() -> None:
    args = sys.argv[1:]
    if len(args) < 7:
        sys.exit("usage: format_coordinator.py serial_in serial_out serial_log "
                 "qmp_sock n names_csv no_label_csv b_img_0..n-1 saved_img_0..n-1")

    serial_in     = args[0]
    serial_out    = args[1]
    serial_log    = args[2]
    qmp_sock      = args[3]
    n             = int(args[4])
    names         = args[5].split(',')
    no_label_set  = set(args[6].split(',')) if args[6] else set()
    no_label_prompt = {i for i, name in enumerate(names) if name in no_label_set}
    b_imgs        = args[7:7 + n]
    saved_imgs    = args[7 + n:7 + 2 * n]

    if len(names) != n:
        sys.exit(f"Expected {n} names, got {len(names)}: {names}")
    if len(b_imgs) != n or len(saved_imgs) != n:
        sys.exit(f"Expected {n} b_imgs and {n} saved_imgs, "
                 f"got {len(b_imgs)} and {len(saved_imgs)}")

    rules    = build_rules(n, names, no_label_prompt, b_imgs, saved_imgs)
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

            # All rules processed — read trailing output briefly (for ===DONE===
            # and any other trailing serial data), then exit without waiting for
            # QEMU to time out.  The caller kills QEMU after we return.
            if rule_idx >= len(rules):
                deadline = time.monotonic() + 3.0
                while time.monotonic() < deadline:
                    r, _, _ = select.select([fout], [], [], 0.1)
                    if r:
                        chunk2 = os.read(fout.fileno(), 512)
                        if not chunk2:
                            break
                        log.write(chunk2); log.flush()
                break

    finally:
        fin.close()
        fout.close()
        log.close()
        print(f"Coordinator done: {rule_idx}/{len(rules)} rules processed.", flush=True)


if __name__ == '__main__':
    main()
