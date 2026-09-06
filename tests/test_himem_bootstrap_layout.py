import unittest

from report_himem_residency import (
    BOOTSTRAP_PROCEDURES, PERMANENT_PROCEDURES, check_bootstrap_layout,
)


class BootstrapLayoutTests(unittest.TestCase):
    def setUp(self):
        self.numbers = dict(HIMEM_PERMANENT_BYTES=2048, HIMEM_BOOTSTRAP_CODE_BYTES=1024,
                            HIMEM_HANDLES_OFFSET=3072)
        self.procedures = {name: 2048 + i * 16 for i, name in enumerate(BOOTSTRAP_PROCEDURES)}
        self.procedures.update({name: 16 + i * 16 for i, name in enumerate(PERMANENT_PROCEDURES)})

    def test_capacities_and_rounding(self):
        for count in (1, 8, 32, 127, 128):
            result = check_bootstrap_layout(self.numbers, self.procedures, count)
            self.assertEqual(result["retained_bootstrap_bytes"], ((1024 + count * 5 + 15) // 16) * 16)
            self.assertEqual(result["linked_boot_end"], 2048 + result["retained_bootstrap_bytes"])
            self.assertEqual(result["released_bytes"], 0)

    def test_wrong_boundaries(self):
        for key, value in (("HIMEM_PERMANENT_BYTES", 2049), ("HIMEM_HANDLES_OFFSET", 3071),
                           ("HIMEM_BOOTSTRAP_CODE_BYTES", 0)):
            with self.assertRaises(ValueError):
                check_bootstrap_layout(dict(self.numbers, **{key: value}), self.procedures, 32)
        for count in (0, 129):
            with self.assertRaises(ValueError):
                check_bootstrap_layout(self.numbers, self.procedures, count)

    def test_wrong_or_missing_procedure(self):
        for name, offset in ((BOOTSTRAP_PROCEDURES[0], 2047), (PERMANENT_PROCEDURES[0], 2048)):
            with self.assertRaises(ValueError):
                check_bootstrap_layout(self.numbers, dict(self.procedures, **{name: offset}), 32)
        with self.assertRaises(KeyError):
            check_bootstrap_layout(self.numbers, {}, 32)

    def test_staging_interface_remains_permanent(self):
        procedures = dict(self.procedures, private_bootstrap_stage=512, xms_stage_forward=768)
        check_bootstrap_layout(self.numbers, procedures, 32)
        for name in ("private_bootstrap_stage", "xms_stage_forward"):
            with self.assertRaises(ValueError):
                check_bootstrap_layout(self.numbers, dict(procedures, **{name: 2048}), 32)
        del procedures["xms_stage_forward"]
        with self.assertRaises(KeyError):
            check_bootstrap_layout(self.numbers, procedures, 32)


if __name__ == "__main__":
    unittest.main()
