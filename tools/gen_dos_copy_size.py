#!/usr/bin/env python3
"""Generate SYSINIT's staging-copy bound from the complete linked kernel."""

import argparse
from pathlib import Path


def copy_size(length):
    if not 0 < length <= 0xFFF0:
        raise ValueError("kernel must fit within the 16-bit staging-copy window")
    return (length + 1) & ~1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kernel", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    size = copy_size(args.kernel.stat().st_size)
    text = f"; Generated from the complete MSDOS.SYS; includes DOSINIT and defaults.\nDOSSIZE EQU {size}\n"
    if not args.output.exists() or args.output.read_text() != text:
        args.output.write_text(text)


if __name__ == "__main__":
    main()
