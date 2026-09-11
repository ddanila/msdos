"""Read embedded help topics and return to a dirty editor document."""

import time

from screen_expect import read_screen_text, send_keys
from test_compat_bpb_qemu import run

CASES = [
    ("help-" + mode, mode, b"DWED_MARKER\r\nsecond line\r\n", False)
    for mode in ("low", "high")
]
CASES.append(("help-mono-low", "low", b"DWED_MARKER\r\nsecond line\r\n", False))


def exercise(q, process, directory, spec, original, name):
    def keys(value):
        send_keys(q, value)
        time.sleep(0.25)

    def expect(needle, label):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            text = read_screen_text(q, str(directory / "vram.bin"))
            (directory / (label + ".txt")).write_text(text)
            if needle in text:
                return text
            time.sleep(0.2)
        raise AssertionError(text)

    keys("home+z+f1")
    expect("real-mode DOS text editor", "about")
    keys("home+down+down+down+ret")
    expect("Interrupted save", "recovery")
    keys("end+ret")
    first = expect("MIT License", "license-first")
    body_x = next(
        line.index("MIT License")
        for line in first.splitlines()
        if "MIT License" in line
    )
    pages = [first]
    for index in range(5):
        keys("right")
        page = expect("LICENSE", "license-page-" + str(index))
        if page == pages[-1]:
            break
        pages.append(page)
    content = " ".join(
        " ".join(line[body_x:].split())
        for page in pages
        for line in page.splitlines()[4:-1]
    )
    content = " ".join(content.split())
    assert (
        len(pages) > 1
        and "AUTHORS OR COPYRIGHT HOLDERS" in content
        and "DEALINGS IN THE SOFTWARE." in content
    ), content
    for _ in pages:
        keys("left")
    expect("MIT License", "license-return")
    keys("esc")
    text = expect("zDWED_MARKER", "editor-return")
    assert "*" in text.splitlines()[-1], text
    keys("f2+esc")
    process.wait(timeout=15)
    assert process.returncode == 33
    assert run(["mtype", "-i", spec, "::SAMPLE.TXT"]).stdout == b"z" + original
    assert run(["mtype", "-i", spec, "::SAMPLE.BAK"]).stdout == original
    return {
        "completed": True,
        "exact_match": True,
        "backup_matches_expected": True,
        "help_pages": len(pages),
        "help_flow": name,
    }
