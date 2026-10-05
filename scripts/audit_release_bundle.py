#!/usr/bin/env python3
"""Inspect an app/archive for release packaging gates; does not certify App Store compliance."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import plistlib
import subprocess


def load_plist(path):
    with path.open('rb') as stream:
        return plistlib.load(stream)


def audit(path):
    if path.suffix == '.xcarchive':
        apps = list((path / 'Products/Applications').glob('*.app'))
        if len(apps) != 1:
            raise ValueError('Expected one application in the archive')
        path = apps[0]
    info = load_plist(path / 'Info.plist')
    blockers = []
    if list(path.rglob('*.litertlm')):
        blockers.append('A model is bundled in the app instead of delivered as an asset pack')
    bundles = [path, *path.rglob('*.appex'), *path.rglob('*.framework')]
    manifests = []
    for bundle in bundles:
        privacy = bundle / 'PrivacyInfo.xcprivacy'
        if privacy.exists():
            data = load_plist(privacy)
            manifests.append({'bundle': bundle.relative_to(path).as_posix(),
                              'apiCategories': data.get('NSPrivacyAccessedAPITypes', [])})
        else:
            blockers.append(f'Missing privacy manifest: {bundle.relative_to(path).as_posix()} (audit SDK/API usage)')
    downloader = path / 'Extensions/AngroveModelDownloader.appex'
    if not downloader.exists():
        blockers.append('Managed downloader is not embedded in Extensions')
    for key in ('BAHasManagedAssetPacks', 'BAUsesAppleHosting'):
        if info.get(key) is not True:
            blockers.append(f'{key} is not enabled')
    if not info.get('BAAppGroupID'):
        blockers.append('Missing Background Assets App Group identifier')
    entitlements = None
    signed_bundles = []
    for bundle in [path, *path.rglob('*.appex')]:
        label = bundle.relative_to(path).as_posix()
        signature = subprocess.run(['codesign', '--display', '--entitlements', ':-', str(bundle)],
                                   capture_output=True, text=True)
        record = {'bundle': label, 'entitlements': None}
        if signature.returncode:
            blockers.append(f'Unsigned bundle: {label}; distribution signing/provisioning remains unverified')
        else:
            xml = signature.stdout or signature.stderr
            start = xml.find('<?xml')
            end = xml.find('</plist>', start)
            if start >= 0 and end >= 0:
                data = plistlib.loads(xml[start:end + len('</plist>')].encode())
                record['entitlements'] = data
                if bundle == path:
                    entitlements = data
                if data.get('get-task-allow'):
                    blockers.append(f'Development signing permits debugging: {label}; requires distribution export')
                if data.get('com.apple.developer.kernel.increased-debugging-memory-limit'):
                    blockers.append(f'Debugging memory entitlement is present: {label}')
                if info.get('BAAppGroupID') not in data.get('com.apple.security.application-groups', []):
                    blockers.append(f'Background Assets App Group missing from signed entitlements: {label}')
                verify = subprocess.run(['codesign', '--verify', '--strict', str(bundle)],
                                        capture_output=True, text=True)
                record['signatureVerified'] = verify.returncode == 0
                if verify.returncode:
                    blockers.append(f'Signature verification failed: {label}')
            else:
                blockers.append(f'Signed entitlements could not be inspected: {label}')
        profile = bundle / 'embedded.mobileprovision'
        if profile.exists():
            decoded = subprocess.run(['security', 'cms', '-D', '-i', str(profile)], capture_output=True)
            if decoded.returncode:
                blockers.append(f'Provisioning profile could not be decoded: {label}')
            else:
                data = plistlib.loads(decoded.stdout)
                profile_entitlements = data.get('Entitlements', {})
                expires = data.get('ExpirationDate')
                record['provisioning'] = {
                    'name': data.get('Name'),
                    'expires': expires.isoformat() if expires else None,
                    'permitsDebugging': profile_entitlements.get('get-task-allow', False),
                    'hasDeviceList': 'ProvisionedDevices' in data,
                    'allDevices': data.get('ProvisionsAllDevices', False),
                    'groups': profile_entitlements.get('com.apple.security.application-groups', []),
                }
                if not expires or expires.replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
                    blockers.append(f'Provisioning profile is expired or has no expiry: {label}')
                if 'ProvisionedDevices' in data or data.get('ProvisionsAllDevices'):
                    blockers.append(f'Provisioning is not App Store distribution: {label}')
                signed = record['entitlements'] or {}
                if signed.get('application-identifier') != profile_entitlements.get('application-identifier'):
                    blockers.append(f'Signed application identifier disagrees with provisioning: {label}')
                if info.get('BAAppGroupID') not in profile_entitlements.get('com.apple.security.application-groups', []):
                    blockers.append(f'Background Assets App Group missing from provisioning: {label}')
        elif record['entitlements']:
            blockers.append(f'No embedded provisioning profile: {label}')
        signed_bundles.append(record)
    if 'ITSAppUsesNonExemptEncryption' not in info:
        blockers.append('Encryption export declaration has not been set after a complete crypto audit')
    size = sum(p.stat().st_size for p in path.rglob('*') if p.is_file())
    return {'bundleID': info.get('CFBundleIdentifier'), 'version': info.get('CFBundleShortVersionString'),
            'build': info.get('CFBundleVersion'), 'minimumOS': info.get('MinimumOSVersion'),
            'deviceFamilies': info.get('UIDeviceFamily'), 'uncompressedFileBytes': size,
            'privacyManifests': manifests, 'signedEntitlements': entitlements,
            'signedBundles': signed_bundles,
            'blockers': blockers,
            'scope': 'Packaging inspection only. Hosting, phone behavior, rights and App Privacy answers require separate verification.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = audit(args.bundle.resolve())
    content = json.dumps(report, indent=2) + '\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(content)
    print(content)


if __name__ == '__main__':
    main()
