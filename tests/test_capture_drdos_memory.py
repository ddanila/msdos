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

INTERFACES = """DOS_VERSION CF=0 AX=0006 BX=0000 DX=0000
DOS_ALLOC_STRATEGY CF=0 AX=0000 BX=0000 DX=0000
DOS_UMB_LINK CF=0 AX=0001 BX=0000 DX=0000
XMS_PRESENT CF=0 AX=4380 BX=0000 DX=0000
XMS_VERSION CF=0 AX=0200 BX=0200 DX=0001
A20_QUERY CF=0 AX=0001 BX=0200 DX=0001
XMS_FREE CF=0 AX=1C00 BX=0000 DX=1C00
XMS_UMB_LARGEST CF=0 AX=0000 BX=00B0 DX=1234
HMA_REQUEST CF=0 AX=0000 BX=0091 DX=FFFF
A20_FINAL CF=0 AX=0001 BX=0091 DX=FFFF
EMS_STATUS CF=0 AX=0000 BX=00B0 DX=1234
EMS_VERSION CF=0 AX=0040 BX=00B0 DX=1234
EMS_FRAME CF=0 AX=0000 BX=D000 DX=1234
EMS_PAGES CF=0 AX=0000 BX=01C0 DX=01C0
DRDOS_PUBLIC_MEMORY_END
"""


class CaptureParserTest(unittest.TestCase):
    def test_extended_pools_are_not_summed(self) -> None:
        summary = CAPTURE.parse_memory_summary(
            "│ Extended          │ 7,208,960 (7,040K) │ 0 (0K) │\n"
            "│ Extended via XMS  │ --------          │ 6,922,240 (6,760K) │\n"
            "│ EMS               │ 6,914,048 (6,752K) │ 6,914,048 (6,752K) │\n")
        self.assertEqual(summary["Extended"], {"total": 7208960, "free": 0})
        self.assertEqual(summary["Extended via XMS"], {"total": None, "free": 6922240})
        self.assertEqual(summary["EMS"]["free"], 6914048)

    def test_missing_pool_is_not_zero(self) -> None:
        self.assertEqual(CAPTURE.parse_memory_summary(""), {})

    def test_startup_resource_settings_are_explicit(self) -> None:
        settings = CAPTURE.common_settings(files=20, stack_size=128, environment=256)
        with tempfile.TemporaryDirectory() as temporary:
            config, _ = CAPTURE.write_startup(
                Path(temporary), ["HIDOS=ON"], [], settings
            )
            self.assertEqual(config.read_bytes(), (
                "HIDOS=ON\r\nFILES=20\r\nFCBS=4,0\r\nLASTDRIVE=Z\r\n"
                "STACKS=9,128\r\nSHELL=COMMAND.COM /P /E:256\r\n"
            ).encode("ascii"))

    def test_resource_settings_reject_invalid_values(self) -> None:
        for kwargs in ({"files": 0}, {"files": 256}, {"stack_size": 0},
                       {"stack_size": 513}, {"environment": 0}, {"environment": 32769}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                CAPTURE.common_settings(**kwargs)

    def test_opendos_frame_changes_only_ems_policy(self) -> None:
        baseline = CAPTURE.OPENDOS_VARIANTS["emm-hibuffers"]
        framed = CAPTURE.OPENDOS_VARIANTS["emm-frame"]
        self.assertEqual(framed, [line.replace("/FRAME=NONE", "/FRAME=AUTO")
                                  for line in baseline])
        self.assertEqual(sum("/FRAME=AUTO" in line for line in framed), 1)

    def test_report_does_not_label_changed_reset_stable(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            media = root / "media"
            media.write_bytes(b"fixture")
            screen = root / "screen"
            screen.write_text(SCREEN)
            data = CAPTURE.parse(screen, MEM, CEILING)
            before = CAPTURE.parse_public_interfaces(INTERFACES)
            after = CAPTURE.parse_public_interfaces(INTERFACES.replace("BX=0091", "BX=0081"))
            data["interfaces"] = before
            data["warm_reboot"] = {"before": before, "after": after}
            report = CAPTURE.report({"emm-frame": data}, media, "vc", "test",
                                    {"emm-frame": CAPTURE.OPENDOS_VARIANTS["emm-frame"]}, None, "test", "probe")
            self.assertIn("FAILED: interfaces changed", report)
            self.assertNotIn("**stable**", report)
            data["warm_reboot"]["after"] = before
            report = CAPTURE.report({"emm-frame": data}, media, "vc", "test",
                                    {"emm-frame": CAPTURE.OPENDOS_VARIANTS["emm-frame"]}, None, "test", "probe")
            self.assertIn("**stable**", report)

    def test_report_records_effective_configuration(self) -> None:
        settings = CAPTURE.common_settings(files=20, stack_size=128)
        with tempfile.TemporaryDirectory() as temporary:
            media = Path(temporary) / "media"
            media.write_bytes(b"test fixture")
            report = CAPTURE.report({}, media, "vc", "test", {"high": ["HIDOS=ON"]},
                                    None, "test emulator", "probe", settings)
        self.assertIn("HIDOS=ON\nFILES=20\nFCBS=4,0\nLASTDRIVE=Z\nSTACKS=9,128", report)
        self.assertNotIn("FILES=30", report)

    def test_custom_settings_do_not_use_historical_numeric_expectations(self) -> None:
        release = "Digital Research DR-DOS 6.0"
        CAPTURE.validate_known_results(release, {"emm-frame": {}},
                                       CAPTURE.common_settings(files=20))
        with self.assertRaises(KeyError):
            CAPTURE.validate_known_results(release, {"emm-frame": {}},
                                           CAPTURE.common_settings())

    def test_public_probe_builds(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            probe, qexit, warmboot, digest = CAPTURE.build_public_probe(Path(temporary))
            self.assertGreater(probe.stat().st_size, 0)
            self.assertGreater(qexit.stat().st_size, 0)
            self.assertGreater(warmboot.stat().st_size, 0)
            self.assertEqual(len(digest), 64)

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

    def test_known_drdos6_results_are_enforced(self) -> None:
        fields = CAPTURE.KNOWN_RESULT_FIELDS
        results = {
            name: dict(zip(fields, expected))
            for name, expected in CAPTURE.KNOWN_DRDOS6_RESULTS.items()
        }
        CAPTURE.validate_known_results("Digital Research DR-DOS 6.0", results)
        results["emm-hibuffers"]["largest"] -= 16
        with self.assertRaisesRegex(RuntimeError, "emm-hibuffers: largest"):
            CAPTURE.validate_known_results("Digital Research DR-DOS 6.0", results)

    def test_unknown_release_has_no_pinned_results(self) -> None:
        CAPTURE.validate_known_results("Caldera OpenDOS 7.01", {"low": {}})

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

    def test_public_interface_records_are_normalized(self) -> None:
        result = CAPTURE.parse_public_interfaces(INTERFACES)
        self.assertTrue(result["xms_available"])
        self.assertTrue(result["ems_available"])
        self.assertEqual(result["records"]["XMS_VERSION"]["ax"], 0x0200)
        self.assertEqual(result["records"]["EMS_FRAME"]["bx"], 0xD000)

    def test_successful_hma_transaction_requires_release(self) -> None:
        successful = INTERFACES.replace(
            "HMA_REQUEST CF=0 AX=0000 BX=0091 DX=FFFF",
            "HMA_REQUEST CF=0 AX=0001 BX=0000 DX=FFFF",
        ).replace(
            "A20_FINAL CF=0 AX=0001 BX=0091 DX=FFFF",
            "HMA_RELEASE CF=0 AX=0001 BX=0000 DX=FFFF\n"
            "A20_FINAL CF=0 AX=0001 BX=0091 DX=FFFF",
        )
        self.assertIn(
            "HMA_RELEASE", CAPTURE.parse_public_interfaces(successful)["records"]
        )
        with self.assertRaisesRegex(ValueError, "missing HMA_RELEASE"):
            CAPTURE.parse_public_interfaces(successful.replace(
                "HMA_RELEASE CF=0 AX=0001 BX=0000 DX=FFFF\n", ""
            ))

    def test_public_interface_parser_rejects_duplicates(self) -> None:
        with self.assertRaisesRegex(ValueError, "duplicate"):
            CAPTURE.parse_public_interfaces(INTERFACES.replace(
                "DRDOS_PUBLIC_MEMORY_END", INTERFACES.splitlines()[0]
            ))

    def test_report_includes_identity_and_normalized_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            screen = Path(temporary) / "screen.txt"
            screen.write_text(SCREEN, encoding="utf-8")
            result = CAPTURE.parse(screen, MEM, CEILING)
            result["interfaces"] = CAPTURE.parse_public_interfaces(INTERFACES)
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
                "1" * 64,
            )
        self.assertIn("QEMU emulator version test", report)
        self.assertIn("| 0141h | 2 | 2,048 | EMM386 |", report)
        self.assertIn("Raw evidence SHA-256", report)
        self.assertIn("| XMS_VERSION | 0 | 0200h | 0200h | 0001h |", report)


if __name__ == "__main__":
    unittest.main()
