"""Generate a pinned EXE-fixup manifest for the development SYSINIT move.

This covers linker segment words only, not arbitrary pointers created by INIT.
The fixture deliberately moves upward; it is not a memory-saving algorithm.
"""
import struct


def manifest(data):
    if len(data) < 28:
        raise ValueError("short MZ header")
    magic, tail, pages, count, header, minimum, _, ss, sp, _, _, _, table, overlay = (
        struct.unpack_from("<14H", data))
    if magic != 0x5a4d or not pages or tail >= 512 or overlay or minimum:
        raise ValueError("unsupported MZ image")
    declared = (pages - 1) * 512 + (tail or 512)
    start = header * 16
    if declared != len(data) or not 28 <= start < declared:
        raise ValueError("MZ file extent mismatch")
    if not 0 < count <= 256 or table < 28 or table + 4 * count > start:
        raise ValueError("invalid MZ relocation table")
    payload = data[start:]
    paragraphs = (len(payload) + 15) // 16
    if paragraphs > 0x8000 or ss * 16 + sp > len(payload):
        raise ValueError("unsupported image/stack extent")
    records = []
    occupied = set()
    for index in range(count):
        offset, segment = struct.unpack_from("<HH", data, table + 4 * index)
        location = segment * 16 + offset
        if location + 2 > len(payload) or occupied.intersection((location, location + 1)):
            raise ValueError("out-of-image or overlapping relocation")
        occupied.update((location, location + 1))
        value = struct.unpack_from("<H", payload, location)[0]
        if value >= paragraphs:
            raise ValueError("relocation refers outside the image")
        # Normalize so a word never straddles a 64 KiB segment boundary.
        records.append((location % 16, location // 16, value))
    return paragraphs, records


def include(data, *, bad_control=False):
    paragraphs, records = manifest(data)
    if bad_control:
        offset, segment, value = records[0]
        records[0] = offset, segment, value ^ 1
    return (f"PROVIDER_IMAGE_PARAS equ {paragraphs}\n"
            f"PROVIDER_FIXUP_COUNT equ {len(records)}\n"
            "PROVIDER_MOVE_PARAS equ 32\n"
            "ProviderFixups LABEL WORD\n"
            + "".join(f"dw {offset},{segment},{value}\n"
                      for offset, segment, value in records))
