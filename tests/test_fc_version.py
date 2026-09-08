#!/usr/bin/env python3
"""Exercise FC comparisons across its supported DOS version range."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix='fc-version-') as temporary:
        directory = Path(temporary)
        (directory/'LEFT.BIN').write_bytes(bytes(range(256)))
        (directory/'RIGHT.BIN').write_bytes(bytes(range(256)))
        rows = []
        for version in ('3.9', '3.10', '5.0', '6.0', '6.22', '6.23'):
            result = subprocess.run([ROOT/'kvikdos/kvikdos-soft', f'--dos-version={version}',
                f'--mount=c:{directory}/', '--drive=c', ROOT/'src/CMD/FC/FC.EXE',
                '/B', 'C:\\LEFT.BIN', 'C:\\RIGHT.BIN'], capture_output=True, timeout=10)
            supported = version not in ('3.9', '6.23')
            assert result.returncode == (0 if supported else 1), result.stdout
            assert (b'no differences encountered' if supported else b'Incorrect DOS version') in result.stdout
            rows.append(dict(version=version, accepted=supported))
        print(json.dumps(rows))


if __name__ == '__main__':
    main()
