#!/usr/bin/env python3
"""Keep COMMAND's class-D lookup routine before its relocatable catalog."""

from __future__ import annotations

import sys
from pathlib import Path


CLASS = b"$M_CLASS_D_STRUC LABEL BYTE\r\n"
LABEL = b"CRITICAL_MSG_START LABEL BYTE\r\n"
PROC = b"        IF      FARmsg\r\n$M_CLS_6 PROC FAR\r\n"
PROC_END = b"$M_CLS_6 ENDP\r\n\r\n"
SEPARATOR = b"; " + b"-" * 58 + b"\r\n"


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: layout_command_critical_catalog.py COMMAND.CLD COMMAND.CDH", file=sys.stderr)
        return 2

    source = Path(sys.argv[1])
    output = Path(sys.argv[2])
    data = source.read_bytes()
    if LABEL in data:
        if data.index(PROC) > data.index(LABEL):
            raise SystemExit(f"{source}: relocated label precedes lookup routine")
        output.write_bytes(data)
        return 0

    class_at = data.index(CLASS)
    proc_at = data.index(PROC)
    proc_end = data.index(PROC_END, proc_at) + len(PROC_END)
    if data[proc_end : proc_end + len(SEPARATOR)] == SEPARATOR:
        proc_end += len(SEPARATOR)

    routine = data[proc_at:proc_end]
    data = data[:proc_at] + data[proc_end:]
    class_at = data.index(CLASS)
    data = data[:class_at] + routine + LABEL + data[class_at:]
    output.write_bytes(data)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
