#!/usr/bin/env python3
"""Align the copied SwiftPM compatibility framework's plist with its real binary target."""
import os
from pathlib import Path
import plistlib
import re
import subprocess


def version(value):
    return tuple(int(part) for part in value.split('.')) + (0,) * (3 - len(value.split('.')))


def main():
    if os.environ.get('PLATFORM_NAME') != 'iphoneos':
        return
    framework = Path(os.environ['TARGET_BUILD_DIR']) / os.environ['FRAMEWORKS_FOLDER_PATH'] / 'onnxruntime.framework'
    plist = framework / 'Info.plist'
    data = plistlib.loads(plist.read_bytes())
    binary = framework / data['CFBundleExecutable']
    commands = subprocess.check_output(['xcrun', 'otool', '-l', str(binary)], text=True)
    minimums = re.findall(r'\bminos (\d+(?:\.\d+)*)', commands)
    minimums += re.findall(r'cmd LC_VERSION_MIN_IPHONEOS\s+cmdsize \d+\s+version (\d+(?:\.\d+)*)', commands)
    if not minimums:
        raise RuntimeError('Cannot inspect ONNX framework minimum OS')
    minimum = max(minimums + [data.get('MinimumOSVersion', '0')], key=version)
    if version(minimum) > version(os.environ['IPHONEOS_DEPLOYMENT_TARGET']):
        raise RuntimeError('ONNX binary requires a newer iOS than the app deployment target')
    if data.get('MinimumOSVersion') == minimum:
        return
    print(f"ONNX MinimumOSVersion: {data.get('MinimumOSVersion')} -> {minimum}")
    data['MinimumOSVersion'] = minimum
    plist.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_BINARY, sort_keys=False))
    identity = os.environ.get('EXPANDED_CODE_SIGN_IDENTITY')
    if not identity:
        raise RuntimeError('Expected a signing identity for the copied iPhone framework')
    subprocess.run(['codesign', '--force', '--sign', identity, '--preserve-metadata=identifier,entitlements,flags',
                    '--generate-entitlement-der', str(framework)], check=True)


if __name__ == '__main__':
    main()
