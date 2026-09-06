import struct
import unittest

from emm_loader_rebase import include, manifest


class ManifestTests(unittest.TestCase):
    def image(self):
        data = bytearray(128)
        struct.pack_into("<14H", data, 0, 0x5a4d, 128, 1, 2, 4, 0, 0xffff,
                         0, 64, 0, 0, 0, 28, 0)
        struct.pack_into("<4H", data, 28, 2, 0, 1, 1)
        struct.pack_into("<H", data, 66, 1)
        struct.pack_into("<H", data, 81, 2)
        return data

    def test_manifest_and_negative_control(self):
        data = self.image()
        self.assertEqual(manifest(data), (4, [(2, 0, 1), (1, 1, 2)]))
        self.assertIn("dw 2,0,1", include(data))
        self.assertIn("dw 2,0,0", include(data, bad_control=True))
        self.assertEqual(manifest(data)[1][0][2], 1)

    def test_invalid_header_and_extent(self):
        for offset, value in ((0, 0), (2, 512), (4, 0), (6, 0), (6, 257),
                              (8, 1), (10, 1), (16, 65), (24, 63), (26, 1)):
            data = self.image()
            struct.pack_into("<H", data, offset, value)
            with self.assertRaises(ValueError):
                manifest(data)
        for data in (b"", self.image()[:-1], self.image() + b"x"):
            with self.assertRaises(ValueError):
                manifest(data)

    def test_invalid_fixups(self):
        for offset, segment in ((2, 0), (3, 0), (63, 0), (0xffff, 0xffff)):
            data = self.image()
            struct.pack_into("<HH", data, 32, offset, segment)
            with self.assertRaises(ValueError):
                manifest(data)
        data = self.image()
        struct.pack_into("<H", data, 66, 4)
        with self.assertRaises(ValueError):
            manifest(data)


if __name__ == "__main__":
    unittest.main()
