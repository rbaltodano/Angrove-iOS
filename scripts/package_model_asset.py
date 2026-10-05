#!/usr/bin/env python3
"""Verify the pinned model and optionally build its essential Apple-hosted asset pack."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import shutil

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'AssetPacks/Gemma4-E4B.json'
EXPECTED_SIZE = 3_659_530_240
EXPECTED_SHA = '0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0'


def verify(path: Path) -> None:
    if path.stat().st_size != EXPECTED_SIZE:
        raise ValueError('Model size differs from the pinned release artifact')
    digest = hashlib.sha256()
    with path.open('rb') as model:
        for chunk in iter(lambda: model.read(8 * 1024 * 1024), b''):
            digest.update(chunk)
    if digest.hexdigest() != EXPECTED_SHA:
        raise ValueError('Model digest differs from the pinned release artifact')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, help='Build an asset-pack archive at this new path')
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    source = ROOT / manifest['fileSelectors'][0]['fileSource']
    verify(source)
    subprocess.run(['xcrun', 'ba-package', 'evaluate', str(MANIFEST)], cwd=ROOT, check=True)
    print('Pinned model size/hash and essential manifest verified.')
    if args.output:
        output = args.output.resolve()
        if output.suffix != '.aar':
            parser.error('Apple asset-pack archives must use the .aar extension')
        if output.exists():
            parser.error('Output already exists; choose a new archive path')
        output.parent.mkdir(parents=True, exist_ok=True)
        # Allow one output plus one staging copy and a gigabyte for the operating system.
        required = EXPECTED_SIZE * 2 + 1024 ** 3
        if shutil.disk_usage(output.parent).free < required:
            parser.error(f'Packaging needs at least {required:,} free bytes including staging/headroom')
        subprocess.run(['xcrun', 'ba-package', 'package', str(MANIFEST), '-o', str(output)], cwd=ROOT, check=True)
        print(f'Packaged: {output}. Upload and TestFlight validation are separate steps.')


if __name__ == '__main__':
    main()
