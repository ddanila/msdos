"""The dispatch-retirement oracle must compare destinations, not copied words."""
import unittest

from test_dos_dispatch_retirement_qemu import check_tables


class DispatchTableTests(unittest.TestCase):
    def fixture(self):
        before = dict(MAXCALL=0x10, DISPATCH=0x12, FOO=0xec, DTAB=0xee, InterChar=0x15f)
        after = {key: value + 0x300 for key, value in before.items()}
        after.update(DOS_DISPATCH_TABLE_END=after["FOO"], DOS_INSTALL_TABLE_END=after["InterChar"])
        old, new = bytearray(0x1000), bytearray(0x1000)
        for data, fields, target_base in ((old, before, 0x600), (new, after, 0x800)):
            start, foo = fields["MAXCALL"], fields["FOO"]
            data[start:start+2] = bytes((36, 108))
            data[foo+4] = 55
            data[foo+2:foo+4] = (foo+4).to_bytes(2, "little")
            addresses = [start+2+i*2 for i in range(109)]
            addresses += [foo] + [foo+5+i*2 for i in range(55)]
            for index, address in enumerate(addresses):
                target = target_base + index
                data[address:address+2] = target.to_bytes(2, "little")
                fields[f"routine_{index}"] = target
        return old, new, before, after

    def test_all_rebased_destinations(self):
        self.assertEqual(len(check_tables(*self.fixture())), 165)

    def test_stale_low_destination_rejected(self):
        old, new, before, after = self.fixture()
        new[after["DISPATCH"]:after["DISPATCH"]+2] = old[before["DISPATCH"]:before["DISPATCH"]+2]
        with self.assertRaises(AssertionError):
            check_tables(old, new, before, after)

    def test_missing_install_entry_rejected(self):
        old, new, before, after = self.fixture()
        new[after["FOO"]+4] -= 1
        with self.assertRaises(AssertionError):
            check_tables(old, new, before, after)


if __name__ == "__main__":
    unittest.main()
