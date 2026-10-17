#!/usr/bin/env python3
"""Verify a pinned model and optionally build its Apple-hosted asset pack.

Packs: `ios-e4b` (default, the iPhone's essential E4B pack), `mac-e4b` (the Mac's essential E4B
pack) and `mac-12b` (the Mac's on-demand Large pack). `--source` reads the model from another
path, such as the 12B download outside this repository, without copying it into the checkout.
For an experimental model, pass `--manifest AssetPacks/Mac-<name>.json --size N --sha256 HEX`
instead of `--pack`; its pack ID and path must match the app's `AngroveModelAssetPack`.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import shutil

ROOT = Path(__file__).resolve().parents[1]
E4B = (3_659_530_240, '0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0')
PACKS = {
    'ios-e4b': ('AssetPacks/Gemma4-E4B.json', *E4B),
    'mac-e4b': ('AssetPacks/Mac-Gemma4-E4B.json', *E4B),
    'mac-12b': ('AssetPacks/Mac-Gemma4-12B.json', 6_883_278_368,
                '58fd31b778ca2c21c80d634fb34fc5a89d11d563a38dfd3cbf1b40dbf252a8b6'),
}


def verify(path: Path, expected_size: int, expected_sha: str) -> None:
    if path.stat().st_size != expected_size:
        raise ValueError('Model size differs from the pinned release artifact')
    digest = hashlib.sha256()
    with path.open('rb') as model:
        for chunk in iter(lambda: model.read(8 * 1024 * 1024), b''):
            digest.update(chunk)
    if digest.hexdigest() != expected_sha:
        raise ValueError('Model digest differs from the pinned release artifact')


def staged_manifest(manifest_path: Path, manifest: dict, source: Path, expected_size: int, expected_sha: str) -> Path:
    """A copy of the manifest whose source root holds an APFS clone of `source` (no extra space)."""
    stage = ROOT / 'build/asset-pack-sources' / manifest['assetPackID']
    relative = manifest['fileSelectors'][0]['fileSource']
    target = stage / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        try:
            verify(target, expected_size, expected_sha)
        except ValueError:
            target.unlink()
    if not target.exists():
        subprocess.run(['cp', '-c', str(source), str(target)], check=True)
    verify(target, expected_size, expected_sha)
    staged = dict(manifest, sourceRoot='.')
    path = stage / manifest_path.name
    path.write_text(json.dumps(staged, indent=2) + '\n')
    return path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, help='Build an asset-pack archive at this new path')
    parser.add_argument('--pack', choices=sorted(PACKS), default='ios-e4b')
    parser.add_argument('--manifest', type=Path, help='Any pack manifest (needs --size and --sha256)')
    parser.add_argument('--size', type=int, help='Pinned byte count for --manifest')
    parser.add_argument('--sha256', help='Pinned SHA-256 for --manifest')
    parser.add_argument('--source', type=Path, help='Read the model from this path instead')
    args = parser.parse_args()
    packager = subprocess.check_output(['xcrun', '--find', 'ba-package'], text=True).strip()
    packager_version = subprocess.check_output([packager, '--version'], text=True).strip()
    if args.output and 'beta' in packager_version.lower():
        parser.error('App Store asset packs require a release ba-package tool; select stable Xcode with DEVELOPER_DIR')
    print(f'Asset pack tool: {packager} ({packager_version})', flush=True)
    if args.manifest:
        if args.size is None or not args.sha256:
            parser.error('--manifest needs --size and --sha256')
        manifest_path, expected_size, expected_sha = args.manifest.resolve(), args.size, args.sha256.lower()
    else:
        relative_manifest, expected_size, expected_sha = PACKS[args.pack]
        manifest_path = ROOT / relative_manifest
    manifest = json.loads(manifest_path.read_text())
    source = args.source.resolve() if args.source else ROOT / manifest['fileSelectors'][0]['fileSource']
    verify(source, expected_size, expected_sha)
    MANIFEST = staged_manifest(manifest_path, manifest, source, expected_size, expected_sha) if args.source else manifest_path
    subprocess.run([packager, 'evaluate', str(MANIFEST)], cwd=ROOT, check=True)
    print(f'Pinned model size/hash and {manifest_path.name} verified.')
    if args.output:
        output = args.output.resolve()
        if output.suffix != '.aar':
            parser.error('Apple asset-pack archives must use the .aar extension')
        if output.exists():
            parser.error('Output already exists; choose a new archive path')
        output.parent.mkdir(parents=True, exist_ok=True)
        # Allow one output plus one staging copy and a gigabyte for the operating system.
        required = expected_size * 2 + 1024 ** 3
        if shutil.disk_usage(output.parent).free < required:
            parser.error(f'Packaging needs at least {required:,} free bytes including staging/headroom')
        subprocess.run([packager, 'package', str(MANIFEST), '-o', str(output)], cwd=ROOT, check=True)
        print(f'Packaged: {output}. Upload and TestFlight validation are separate steps.')


if __name__ == '__main__':
    main()
