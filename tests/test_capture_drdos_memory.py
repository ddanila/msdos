#!/usr/bin/env python3
"""Media-independent checks for the DR-DOS clean-room capture parser."""

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("capture_drdos_memory.py")
SPEC = spec_from_file_location("capture_drdos_memory", SCRIPT)
assert SPEC and SPEC.loader
CAPTURE = module_from_spec(SPEC)
SPEC.loader.exec_module(CAPTURE)


SCREEN = """
║ 0100  1  1,024   DOS 6.00        00 01       ║
║ 0141  2  2,048   EMM386          67          ║
║ 01C2  1  1,264   COMMAND.COM     22 2E       ║
║ 0212  1  9,092   VC.COM          1B 21       ║
║ 044B  1  618,736   free memory                 ║
║ D000  2  47,888   free memory                 ║
"""

MEM = """
│ Conventional │ 640,000 (625K) │ 618,736
│ Upper        │  49,104 ( 48K) │  47,888
│ High         │  65,520 ( 64K) │  10,880
"""

CEILING = "MEMORY_CEILING INT12=027F BDA=027F EBDA=9FC0\r\n"


class CaptureParserTest(unittest.TestCase):
    def test_comparison_artifact_identities_are_pinned(self) -> None:
        release = "Digital Research DR-DOS 6.0"
        self.assertTrue(CAPTURE.comparison_identities_match(
            release,
            CAPTURE.KNOWN_MEDIA_SHA256[release],
            CAPTURE.KNOWN_VC_SHA256,
            CAPTURE.KNOWN_DRDOS6_DISK_MD5,
        ))
        self.assertFalse(CAPTURE.comparison_identities_match(
            release,
            "0" * 64,
            CAPTURE.KNOWN_VC_SHA256,
            CAPTURE.KNOWN_DRDOS6_DISK_MD5,
        ))

    def test_full_owner_rows_and_summary_are_retained(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            screen = Path(temporary) / "screen.txt"
            screen.write_text(SCREEN, encoding="utf-8")
            result = CAPTURE.parse(screen, MEM, CEILING)

        self.assertEqual(result["largest"], 618_736)
        self.assertEqual(result["upper_free"], 47_888)
        self.assertEqual(result["hma_free"], 10_880)
        self.assertEqual(result["int12"], 0x027F)
        self.assertEqual(result["ebda"], 0x9FC0)
        self.assertIn(
            {"segment": 0x0141, "blocks": 2, "bytes": 2_048, "owner": "EMM386"},
            result["owners"],
        )

    def test_report_includes_identity_and_normalized_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            screen = Path(temporary) / "screen.txt"
            screen.write_text(SCREEN, encoding="utf-8")
            result = CAPTURE.parse(screen, MEM, CEILING)
            media = Path(temporary) / "media.json"
            media.write_text("fixture", encoding="ascii")
            report = CAPTURE.report(
                {"baseline": result},
                media,
                CAPTURE.KNOWN_VC_SHA256,
                "Digital Research DR-DOS 6.0",
                {"baseline": ["HIDOS=OFF"]},
                CAPTURE.KNOWN_DRDOS6_DISK_MD5,
                "QEMU emulator version test",
            )
        self.assertIn("QEMU emulator version test", report)
        self.assertIn("| 0141h | 2 | 2,048 | EMM386 |", report)
        self.assertIn("Raw evidence SHA-256", report)


if __name__ == "__main__":
    unittest.main()
