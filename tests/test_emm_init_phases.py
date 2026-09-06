#!/usr/bin/env python3
import struct
import unittest

from capture_emm_init_phases import check_phases, parse_trace


class InitPhaseTests(unittest.TestCase):
    def trace(self, mode="ON"):
        return b"".join(struct.pack("<2sB5H", b"IP", stage,
                                   int(stage >= 6 and (mode in ("ON", "RAM") or stage == 6)),
                                   0x100 if stage < 8 else 0x200, 0x300,
                                   0x400 if stage < 8 else 0x500, 0x600)
                        for stage in range(1, 9))

    def test_mode_boundaries(self):
        for mode in ("ON", "OFF", "AUTO", "RAM"):
            check_phases(parse_trace(self.trace(mode)), mode)

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


if __name__ == "__main__":
    unittest.main()
