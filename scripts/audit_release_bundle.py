#!/usr/bin/env python3
"""Inspect an app/archive for release packaging gates; does not certify App Store compliance."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import plistlib
import re
import subprocess


def load_plist(path):
    with path.open('rb') as stream:
        return plistlib.load(stream)


def empty_static_linker_stub(bundle):
    """Xcode embeds empty compatibility dylibs for some statically linked SwiftPM targets.

    Require zero symbols and a single zero-length text section, rather than exempting an SDK
    by name or accepting stripped symbols alone. Actual SDK code is audited in the app binary.
    """
    if bundle.suffix != '.framework':
        return False
    info_path = bundle / 'Info.plist'
    if not info_path.exists():
        return False
    executable = bundle / load_plist(info_path).get('CFBundleExecutable', bundle.stem)
    result = subprocess.run(['xcrun', 'otool', '-l', str(executable)], capture_output=True, text=True)
    if result.returncode or not re.search(r'\bnsyms 0\b', result.stdout):
        return False
    sections = re.findall(r'Section\s+sectname (\S+)\s+segname (\S+)\s+addr \S+\s+size (0x[0-9a-fA-F]+)', result.stdout)
    return bool(sections) and all(name == '__text' and segment == '__TEXT' and int(size, 16) == 0
                                  for name, segment, size in sections)


def audit(path):
    if path.suffix == '.xcarchive':
        apps = list((path / 'Products/Applications').glob('*.app'))
        if len(apps) != 1:
            raise ValueError('Expected one application in the archive')
        path = apps[0]
    info = load_plist(path / 'Info.plist')
    blockers = []
    for resource in ('MiniLM.mlmodelc', 'embeddings.bin', 'passages.json', 'vocab.txt', 'library-index.json'):
        if not (path / resource).exists():
            blockers.append(f'Missing required on-device Library/retrieval resource: {resource}')
    if list(path.rglob('*.litertlm')):
        blockers.append('A model is bundled in the app instead of delivered as an asset pack')
    bundles = [path, *path.rglob('*.appex'), *path.rglob('*.framework')]
    manifests = []
    empty_framework_stubs = []
    minimum_os_checks = []
    for bundle in bundles:
        bundle_info = load_plist(bundle / 'Info.plist')
        executable = bundle / bundle_info.get('CFBundleExecutable', bundle.stem)
        commands = subprocess.run(['xcrun', 'otool', '-l', str(executable)], capture_output=True, text=True)
        binary_minimums = re.findall(r'\bminos (\d+(?:\.\d+)*)', commands.stdout)
        binary_minimums += re.findall(r'cmd LC_VERSION_MIN_IPHONEOS\s+cmdsize \d+\s+version (\d+(?:\.\d+)*)', commands.stdout)
        declared = bundle_info.get('MinimumOSVersion')
        label = bundle.relative_to(path).as_posix()
        def os_version(value):
            parts = value.split('.')
            return tuple(int(part) for part in parts) + (0,) * (3 - len(parts))
        minimum_os_checks.append({'bundle': label, 'declaredMinimumOS': declared, 'binaryMinimumOS': binary_minimums})
        if bundle.suffix == '.framework':
            signature = subprocess.run(['codesign', '--verify', '--strict', str(bundle)], capture_output=True, text=True)
            minimum_os_checks[-1]['signatureVerified'] = signature.returncode == 0
            if signature.returncode:
                blockers.append(f'Framework signature verification failed: {label}')
        if commands.returncode or not binary_minimums or not declared:
            blockers.append(f'Minimum OS cannot be verified: {label}')
        else:
            for binary_minimum in binary_minimums:
                if os_version(binary_minimum) > os_version(declared):
                    blockers.append(f'Minimum OS mismatch: {label} declares {declared}, binary requires {binary_minimum}')
                if os_version(binary_minimum) > os_version(info['MinimumOSVersion']):
                    blockers.append(f'Embedded binary requires a newer OS than the app: {label}')
        privacy = bundle / 'PrivacyInfo.xcprivacy'
        if privacy.exists():
            data = load_plist(privacy)
            manifests.append({'bundle': bundle.relative_to(path).as_posix(),
                              'apiCategories': data.get('NSPrivacyAccessedAPITypes', [])})
        elif empty_static_linker_stub(bundle):
            empty_framework_stubs.append({'bundle': bundle.relative_to(path).as_posix(),
                'evidence': 'Zero symbols; only a zero-length text section. Static SDK code belongs to the app API audit.'})
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
            'minimumOSChecks': minimum_os_checks, 'privacyManifests': manifests, 'emptyFrameworkStubs': empty_framework_stubs, 'signedEntitlements': entitlements,
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
