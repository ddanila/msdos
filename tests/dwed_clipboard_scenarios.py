"""Clipboard fidelity and failure retention through real editor commands."""

import time

from screen_expect import read_screen_text, send_keys
from test_compat_bpb_qemu import put, run

ORIGINAL = b"DWED_MARKER\r\nsecond line\r\n"
LONG_EDGES = b"DWED_MARKER" + b"A" * 189 + b"\r\n" + b"B" * 200 + b"\r\n"
CASES = [
    ("clip-edit-" + kind + "-low", "low", ORIGINAL, False)
    for kind in (
        "mixed",
        "import-large",
        "import-control",
        "import-missing",
        "export-full",
    )
]
CASES += [
    ("clip-edit-" + kind + "-low", "low", LONG_EDGES, False)
    for kind in ("paste-overflow", "replace-newline", "cut-overflow")
]
CASES += [
    (
        "clip-edit-copy-capacity-low",
        "low",
        b"DWED_MARKER\r\n" + (b"R" * 200 + b"\r\n") * 170,
        False,
    ),
    ("clip-edit-mixed-high", "high", ORIGINAL, False),
]
EXISTING = b"EXISTING_EXPORT\r\n"
OLD_BACKUP = b"OLDER_EXPORT_BACKUP\r\n"


def payload(kind):
    return {
        "mixed": b"a\r\nb\rc\n\t\x80\xff",
        "import-large": b"X" * 32768,
        "import-control": b"bad\x00hidden",
        "export-full": b"Q" * 4096,
        "paste-overflow": b"P" * 100,
        "replace-newline": b"\r\n",
    }.get(kind)


def prepare(spec, name):
    if not name.startswith("clip-edit-"):
        return
    kind = name.removeprefix("clip-edit-").rsplit("-", 1)[0]
    data = payload(kind)
    if data is not None:
        put(spec, "DWED/INPUT.TXT", data)
        run(["mattrib", "-i", spec, "+r", "::DWED/INPUT.TXT"])
    put(spec, "DWED/OUT.TXT", EXISTING)
    put(spec, "DWED/OUT.BAK", OLD_BACKUP)


def exercise(q, process, directory, spec, original, name):
    kind = name.removeprefix("clip-edit-").rsplit("-", 1)[0]

    def keys(value):
        send_keys(q, value)
        time.sleep(0.5 if value.endswith(" 200") else 0.25)

    def screen(label):
        value = read_screen_text(q, str(directory / "vram.bin"))
        (directory / (label + ".txt")).write_text(value)
        return value

    def wait_for(predicate, label):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            value = screen(label)
            if predicate(value):
                return value
            time.sleep(0.2)
        raise AssertionError(value)

    def main_screen(label):
        return wait_for(lambda value: value.startswith(" File "), label)

    def error(needle):
        wait_for(lambda value: "Error" in value and needle in value, "error")
        keys("ret")
        return main_screen("after-error")

    def filename(value):
        keys("+".join("dot" if char == "." else char for char in value) + "+ret")

    def import_clip(expected_error=None):
        keys("hmp:sendkey alt-f3")
        wait_for(lambda value: "Load clipboard from file" in value, "import-prompt")
        filename("input.txt")
        if expected_error:
            error(expected_error)
        else:
            main_screen("imported")

    def export_clip(expected_error=None):
        keys("hmp:sendkey alt-f2")
        wait_for(lambda value: "Save clipboard to file" in value, "export-prompt")
        filename("out.txt")
        if expected_error:
            error(expected_error)
        else:
            main_screen("exported")

    def seed_clipboard():
        keys("home")
        for _ in range(2):
            keys("hmp:sendkey shift-right 200")
        keys("hmp:sendkey ctrl-c")
        keys("home")

    def select_newline():
        keys("end")
        keys("hmp:sendkey shift-right 200")

    expected = original
    save_document = False
    exported = None
    if kind == "mixed":
        import_clip()
        keys("home")
        keys("hmp:sendkey ctrl-v")
        keys("hmp:sendkey ctrl-z")
        value = main_screen("paste-undone")
        assert "*" not in value.splitlines()[-1], value
        keys("hmp:sendkey alt-e")
        keys("r")
        expected = b"a\r\nb\r\nc\r\n\t\x80\xff" + original
        save_document = True
    elif kind.startswith("import-"):
        seed_clipboard()
        message = {
            "import-large": "Text exceeds clipboard capacity",
            "import-control": "Unsupported control byte",
            "import-missing": "File not found",
        }[kind]
        import_clip(message)
        keys("end")
        keys("hmp:sendkey ctrl-v")
        expected = original.replace(b"DWED_MARKER", b"DWED_MARKERDW")
        save_document = True
    elif kind == "paste-overflow":
        import_clip()
        keys("home")
        keys("hmp:sendkey ctrl-v")
        value = error("Resulting line exceeds 255 bytes")
        assert "*" not in value.splitlines()[-1], value
        export_clip()
        exported = payload(kind)
    elif kind == "replace-newline":
        import_clip()
        select_newline()
        keys("hmp:sendkey ctrl-v")
        main_screen("newline-replaced")
        keys("hmp:sendkey ctrl-z")
        keys("hmp:sendkey alt-e")
        keys("r")
        save_document = True
    elif kind == "cut-overflow":
        seed_clipboard()
        select_newline()
        keys("hmp:sendkey ctrl-x")
        value = error("Resulting line exceeds 255 bytes")
        assert "*" not in value.splitlines()[-1], value
        export_clip()
        exported = b"DW"
    elif kind == "copy-capacity":
        seed_clipboard()
        for _ in range(8):
            keys("hmp:sendkey shift-pgdn 200")
        wait_for(lambda value: "172/172" in value, "large-selection")
        time.sleep(0.3)
        keys("hmp:sendkey ctrl-x")
        value = error("Text exceeds clipboard capacity")
        assert "*" not in value.splitlines()[-1], value
        export_clip()
        exported = b"DW"
    elif kind == "export-full":
        import_clip()
        export_clip("Disk write error")
        exported = EXISTING
    if save_document:
        keys("f2")
    keys("esc")
    process.wait(timeout=15)
    assert process.returncode == 33, process.returncode
    actual = run(["mtype", "-i", spec, "::SAMPLE.TXT"]).stdout
    backup = run(["mtype", "-i", spec, "::SAMPLE.BAK"]).stdout
    assert actual == expected, (actual, expected)
    assert backup == (original if save_document else b"PREVIOUS_BACKUP\r\n"), backup
    if exported is not None:
        actual_export = run(["mtype", "-i", spec, "::DWED/OUT.TXT"]).stdout
        export_backup = run(["mtype", "-i", spec, "::DWED/OUT.BAK"]).stdout
        assert actual_export == exported, actual_export
        assert export_backup == (OLD_BACKUP if kind == "export-full" else EXISTING), (
            export_backup
        )
    data = payload(kind)
    if data is not None:
        assert run(["mtype", "-i", spec, "::DWED/INPUT.TXT"]).stdout == data
    listing = run(["mdir", "-b", "-i", spec, "::DWED"]).stdout.upper()
    assert b".TMP" not in listing, listing
    return {
        "completed": True,
        "exact_match": True,
        "backup_matches_expected": True,
        "clipboard_flow": kind,
    }
