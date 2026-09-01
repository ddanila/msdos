#!/usr/bin/env python3
"""Create deterministic IBM 5170 CMOS state for an 86Box test VM."""

import argparse
import datetime
from pathlib import Path


def bcd(value: int) -> int:
    return ((value // 10) << 4) | (value % 10)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--extended-kib", type=int, default=2048)
    args = parser.parse_args()
    if not 0 <= args.extended_kib <= 0xFFFF:
        parser.error("--extended-kib must fit in the IBM AT CMOS field")

    # IBM AT-compatible MC146818 layout.  A fixed valid date avoids depending
    # on host time while the VM template has time synchronization disabled.
    cmos = bytearray(64)
    stamp = datetime.datetime(1994, 6, 22, 12, 0, 0)
    cmos[0x00] = bcd(stamp.second)
    cmos[0x02] = bcd(stamp.minute)
    cmos[0x04] = bcd(stamp.hour)
    cmos[0x06] = bcd(stamp.isoweekday())
    cmos[0x07] = bcd(stamp.day)
    cmos[0x08] = bcd(stamp.month)
    cmos[0x09] = bcd(stamp.year % 100)
    cmos[0x0A] = 0x26
    cmos[0x0B] = 0x02
    cmos[0x0D] = 0x80
    cmos[0x0E] = 0x00
    cmos[0x0F] = 0x00
    cmos[0x10] = 0x20  # Drive A: 1.2 MiB, drive B: absent.
    cmos[0x12] = 0x00  # No fixed disks.
    cmos[0x14] = 0x21  # Diskette installed, 80-column color display.
    cmos[0x15:0x17] = (640).to_bytes(2, "little")
    cmos[0x17:0x19] = args.extended_kib.to_bytes(2, "little")
    checksum = sum(cmos[0x10:0x2E]) & 0xFFFF
    cmos[0x2E:0x30] = checksum.to_bytes(2, "big")
    cmos[0x30:0x32] = args.extended_kib.to_bytes(2, "little")
    cmos[0x32] = bcd(stamp.year // 100)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(cmos)


if __name__ == "__main__":
    main()
