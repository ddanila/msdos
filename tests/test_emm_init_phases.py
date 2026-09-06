#!/usr/bin/env python3
import struct
import unittest

from capture_emm_init_phases import check_phases, parse_trace, strip_capacity_records, parse_bootstrap_layout


class InitPhaseTests(unittest.TestCase):
    def layout(self):
        return struct.pack("<2s6H", b"XL", 0x400, 2240, 3008, 32, 3168, 448)

    def test_bootstrap_layout_receipt(self):
        result = parse_bootstrap_layout(self.layout())
        self.assertEqual(result["retained_bootstrap_bytes"], 928)
        self.assertEqual(result["released_bytes"], 0)
        for offset, value in ((2, 0), (2, 0x9fff), (4, 2241), (6, 2200),
                              (8, 0), (8, 129), (10, 3169), (12, 2240)):
            data = bytearray(self.layout())
            struct.pack_into("<H", data, offset, value)
            with self.assertRaises(ValueError):
                parse_bootstrap_layout(data)
        for data in (b"", self.layout()[:-1], self.layout() + b"x"):
            with self.assertRaises(ValueError):
                parse_bootstrap_layout(data)

    def test_bootstrap_owner_record(self):
        record = struct.pack("<2sHIH", b"XO", 3, 0x110000, 1)
        rows = parse_trace(self.trace() + record, bootstrap_owner=True)
        self.assertEqual(rows[-1]["bootstrap_owner"],
                         dict(handle=3, physical=0x110000, size_kib=1, high_committed=False))
        check_phases(rows, "ON")

    def test_authoritative_owner_publication(self):
        owner = struct.pack("<2sHIH", b"XO", 3, 0x110000, 1)
        marker = struct.pack("<2sI", b"XA", 0x220000)
        rows = parse_trace(self.trace() + marker + self.layout() + owner,
                           bootstrap_owner=True, authoritative_owner=True)
        self.assertTrue(rows[-1]["bootstrap_owner"]["high_committed"])
        self.assertEqual(rows[-1]["bootstrap_owner"]["high_code_base"], 0x220000)
        check_phases(rows, "ON")
        for marker in (b"", b"XX", marker + marker, struct.pack("<2sI", b"XA", 0x90000)):
            with self.assertRaises(ValueError):
                parse_trace(self.trace() + marker + self.layout() + owner,
                            bootstrap_owner=True, authoritative_owner=True)

    def test_bad_bootstrap_owner_record(self):
        for record in (b"", b"XF", struct.pack("<2sHIH", b"XO", 0, 0x110000, 1),
                       struct.pack("<2sHIH", b"XO", 1, 0x90000, 1),
                       struct.pack("<2sHIH", b"XO", 1, 0x110000, 0)):
            with self.assertRaises(ValueError):
                parse_trace(self.trace() + record, bootstrap_owner=True)

    def test_cancelled_authoritative_owner_is_not_published(self):
        first = self.trace()[:13]
        phases = b"".join(first[:2] + bytes([stage]) + first[3:] for stage in (1, 9, 10))
        owner = struct.pack("<2sHIH", b"XO", 3, 0x110000, 1)
        options = dict(split=True, rejected=True, bootstrap_owner=True, authoritative_owner=True)
        rows = parse_trace(phases + self.layout() + owner, **options)
        self.assertFalse(rows[-1]["bootstrap_owner"]["high_committed"])
        check_phases(rows, "ON", split=True, rejected=True)
        with self.assertRaises(ValueError):
            parse_trace(phases + struct.pack("<2sI", b"XA", 0x220000) + self.layout() + owner, **options)

    def test_capacity_records(self):
        for handles, altregs in ((None, None), (255, None), (None, 0), (255, 254), (2, 0)):
            data = self.trace()
            for tag, count in ((b"HC", handles), (b"AC", altregs)):
                if count is not None:
                    data += tag + struct.pack("<H", count)
            result = strip_capacity_records(data, handles=handles, altregs=altregs)
            self.assertEqual(result, self.trace())
            check_phases(parse_trace(result), "ON")

    def test_bad_capacity_records(self):
        base = self.trace()
        for tail in (b"", b"HC\xff\x00", b"HC\xff\x00AC\xff\xff",
                     b"AC\xfe\x00HC\xff\x00", b"HC\x02\x00AC\xfe\x00",
                     b"HC\xff\x00HC\xff\x00AC\xfe\x00"):
            with self.assertRaises(ValueError):
                parse_trace(strip_capacity_records(base + tail, handles=255, altregs=254))

    def trace(self, mode="ON"):
        return b"".join(struct.pack("<2sB5H", b"IP", stage,
                                   int(stage >= 6 and (mode in ("ON", "RAM") or stage == 6)),
                                   0x100 if stage < 8 else 0x200, 0x300,
                                   0x400 if stage < 8 else 0x500, 0x600)
                        for stage in range(1, 9))

    def test_mode_boundaries(self):
        for mode in ("ON", "OFF", "AUTO", "RAM"):
            check_phases(parse_trace(self.trace(mode)), mode)

    def test_table_owner_layout(self):
        for mode in ("ON", "OFF", "AUTO", "RAM"):
            for high, physical in ((0, 0xD000), (1, 0x160000)):
                base = self.trace(mode)
                record = struct.pack("<2sI3H", b"HT", physical, 1961, 0x700, high)
                rows = parse_trace(base[:78] + record + base[78:], table_layout=True)
                self.assertEqual(rows[5]["tables"], dict(
                    physical=physical, bytes=1961, end=0x700, high=high))
                check_phases(rows, mode)

    def test_invalid_table_owner_layout(self):
        base = self.trace()
        good = struct.pack("<2sI3H", b"HT", 0x160000, 1961, 0x700, 1)
        for record in (b"", good[:-1], good + good,
                       struct.pack("<2sI3H", b"XX", 0x160000, 1961, 0x700, 1),
                       struct.pack("<2sI3H", b"HT", 0xD000, 1961, 0x700, 1),
                       struct.pack("<2sI3H", b"HT", 0x160000, 1961, 0x700, 0),
                       struct.pack("<2sI3H", b"HT", 0x160000, 0, 0x700, 1),
                       struct.pack("<2sI3H", b"HT", 0x160000, 1961, 0, 1),
                       struct.pack("<2sI3H", b"HT", 0x160000, 1961, 0x700, 2)):
            with self.assertRaises(ValueError):
                parse_trace(base[:78] + record + base[78:], table_layout=True)

    def test_bad_length_and_order(self):
        for data in (b"", self.trace()[:-1], self.trace() + b"x",
                     self.trace().replace(b"IP\x03", b"IP\x02")):
            with self.assertRaises(ValueError):
                parse_trace(data)

    def test_early_cpu_activation(self):
        rows = parse_trace(self.trace())
        rows[4]["pe"] = 1
        with self.assertRaisesRegex(ValueError, "CPU"):
            check_phases(rows, "ON")

    def test_early_or_missing_vector(self):
        for vector in ("int15", "int67"):
            for index, value in ((4, "changed"), (7, None)):
                rows = parse_trace(self.trace())
                rows[index][vector] = rows[0][vector] if value is None else value
                with self.assertRaisesRegex(ValueError, "interrupt"):
                    check_phases(rows, "ON")

    def test_prepared_return_and_rejection(self):
        base = self.trace()
        prepared = struct.pack("<2sB5H", b"IP", 9, 0, 0x100, 0x300, 0x400, 0x600)
        cleanup = struct.pack("<2sB5H", b"IP", 10, 0, 0x100, 0x300, 0x400, 0x600)
        check_phases(parse_trace(base[:13] + prepared + base[13:], split=True),
                     "ON", split=True)
        check_phases(parse_trace(base[:13] + prepared + cleanup, rejected=True),
                     "ON", rejected=True)
        with self.assertRaises(ValueError):
            parse_trace(base[:13] + prepared + cleanup.replace(b"IP\x0a", b"IP\x0b"),
                        rejected=True)

    def test_prepared_or_rejected_mutation(self):
        rows = parse_trace(self.trace())
        for index in (1, 2):
            sample = [dict(rows[0]) for _ in range(3)]
            sample[index]["int67"] = "changed"
            with self.assertRaises(ValueError):
                check_phases(sample, "ON", rejected=True)

    def test_separate_activation_stack(self):
        def record(stage, pe=0, published=False):
            return struct.pack("<2sB5H", b"IP", stage, pe,
                               0x200 if published else 0x100, 0x300,
                               0x500 if published else 0x400, 0x600)
        data = (self.trace()[:13] + record(9) + record(12)
                + self.trace()[13:] + record(13, 1, True))
        rows = parse_trace(data, split=True, activation_stack=True)
        check_phases(rows, "ON", split=True, activation_stack=True)
        with self.assertRaises(ValueError):
            parse_trace(data[:-13] + record(14), split=True, activation_stack=True)
        rows[-1]["int67"] = "changed"
        with self.assertRaisesRegex(ValueError, "stack boundary"):
            check_phases(rows, "ON", split=True, activation_stack=True)

    def test_lifecycle_terminal_state(self):
        for mode in ("ON", "OFF", "AUTO", "RAM"):
            for rejected in (False, True):
                for stack in (False, True):
                    base = self.trace(mode)
                    def clone(record, stage):
                        return record[:2] + bytes([stage]) + record[3:]
                    prepared = clone(base[:13], 9)
                    terminal = clone(base[:13], 10) if rejected else base[-13:]
                    data = base[:13] + prepared
                    if stack:
                        data += clone(prepared, 12)
                    data += terminal if rejected else base[13:]
                    if stack:
                        data += clone(terminal, 13)
                    data += clone(terminal, 15)
                    flags = dict(split=True, rejected=rejected,
                                 activation_stack=stack, lifecycle=True)
                    rows = parse_trace(data, **flags)
                    check_phases(rows, mode, **flags)
                    with self.assertRaises(ValueError):
                        parse_trace(data[:-13] + clone(terminal, 16), **flags)
                    rows[-1]["int15"] = "changed"
                    with self.assertRaisesRegex(ValueError, "lifecycle"):
                        check_phases(rows, mode, **flags)

    def test_loader_return_and_resume(self):
        for mode in ("ON", "OFF", "AUTO", "RAM"):
            for rejected in (False, True):
                base = self.trace(mode)
                def record(stage):
                    return base[:2] + bytes([stage]) + base[3:13]
                data = (base[:13] + record(9) + record(17)
                        + (record(10) if rejected else base[13:]) + b"LD")
                flags = dict(split=True, rejected=rejected, loader=True)
                rows = parse_trace(data, **flags)
                check_phases(rows, mode, **flags)
                for invalid in (data[:-2], data + b"LD",
                                data.replace(b"IP\x11", b"IP\x09")):
                    with self.assertRaises(ValueError):
                        parse_trace(invalid, **flags)
                rows[2]["int15"] = "changed"
                with self.assertRaisesRegex(ValueError, "loader resume"):
                    check_phases(rows, mode, **flags)

    def test_moved_loader_entries(self):
        base = self.trace()
        def record(stage):
            return base[:2] + bytes([stage]) + base[3:13]
        data = bytearray(base[:13] + record(9) + record(17) + base[13:] + b"LD")
        old, new = 0xce3, 0xd03
        for offset in (7, 11):
            struct.pack_into("<H", data, len(data) - 15 + offset, new)
        moved = data[:26] + struct.pack("<2s3H", b"RB", old, new, 7335) + data[26:]
        flags = dict(split=True, loader=True, rebase=True)
        rows = parse_trace(moved, **flags)
        check_phases(rows, "ON", **flags)
        rows[-1]["int67"] = f"{old:04X}:009B"
        with self.assertRaisesRegex(ValueError, "moved image"):
            check_phases(rows, "ON", **flags)
        for header in (b"RF", struct.pack("<2s3H", b"RB", old, old, 7335),
                       struct.pack("<2s3H", b"RB", old, new, 0)):
            with self.assertRaises(ValueError):
                parse_trace(data[:26] + header + data[26:], **flags)


if __name__ == "__main__":
    unittest.main()
