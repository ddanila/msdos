"""Raw RFB screen capture and physical keys for the private 86Box backend."""
import struct

from PIL import Image
from test_ru_legacy_keyboard_86box import VNCKeyboard


class VNCConsole(VNCKeyboard):
    KEYS = dict(VNCKeyboard.KEYS, minus=ord('-'), f2=0xffbf)
    def __init__(self, proc):
        super().__init__(proc)
        assert self.pixel_format == bytes.fromhex('2020000100ff00ff00ff100800000000')
        # Request raw pixels and advertise resize support before the guest
        # changes video mode. The initial server geometry is only a placeholder.
        self.socket.sendall(struct.pack('>BBHii', 2, 0, 2, 0, -223))
        self.canvas = Image.new('RGB', (self.width, self.height))

    def capture(self):
        for attempt in range(5):
            self.socket.sendall(struct.pack('>BBHHHH', 3, 0, 0, 0, self.width, self.height))
            kind = self.receive(1)[0]
            while kind == 2:  # Bell carries no payload.
                kind = self.receive(1)[0]
            assert kind == 0, ('Unexpected RFB message', kind)
            _, count = struct.unpack('>BH', self.receive(3))
            resized = False
            for _ in range(count):
                x, y, width, height, encoding = struct.unpack('>HHHHi', self.receive(12))
                if encoding == -223:
                    self.width, self.height = width, height
                    self.canvas = Image.new('RGB', (width, height))
                    resized = True
                else:
                    assert encoding == 0, encoding
                    pixels = self.receive(width * height * 4)
                    self.canvas.paste(Image.frombytes('RGB', (width, height), pixels, 'raw', 'BGRX'), (x, y))
            if not resized:
                return self.canvas.copy()
        raise AssertionError('RFB geometry did not settle')
