"""Bounds-checked COUNTRY.SYS reader shared by locale regression probes."""

import struct


def read_records(data):
    def take(offset, size):
        if offset < 0 or offset + size > len(data):
            raise ValueError("COUNTRY.SYS object outside file")
        return data[offset:offset + size]

    def word(offset):
        return struct.unpack("<H", take(offset, 2))[0]

    def pointer(offset):
        return struct.unpack("<I", take(offset, 4))[0]

    if take(0, 8) != b"\xffCOUNTRY":
        raise ValueError("COUNTRY.SYS signature")
    table = pointer(19)
    position = table + 2
    records = {}
    for _ in range(word(table)):
        size, country, page = struct.unpack("<HHH", take(position, 6))
        if size != 12:
            raise ValueError("COUNTRY.SYS directory entry size")
        entry = pointer(position + 10)
        position += size + 2
        count = word(entry)
        entry += 2
        objects = {}
        for _ in range(count):
            size = word(entry)
            if size != 6:
                raise ValueError("COUNTRY.SYS object pointer size")
            kind = take(entry + 2, 1)[0]
            target = pointer(entry + 4)
            length = word(target + 8)
            if kind in objects:
                raise ValueError("duplicate country object")
            objects[kind] = {"offset": target, "signature": take(target, 8),
                             "payload": take(target + 10, length)}
            entry += size + 2
        if (country, page) in records:
            raise ValueError("duplicate country/code-page record")
        records[country, page] = objects
    return records
