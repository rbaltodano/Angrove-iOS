#!/usr/bin/env python3
"""Inventory a pinned Mach-O SDK; findings require source/call-path interpretation."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

APIS = ('_connect', '_socket', '_socketpair', '_gethostname', '_stat', '_fstat',
        '_fstatat', '_lstat', '_mach_absolute_time', '_CCRandomGenerateBytes')


def audit(binary):
    digest = hashlib.sha256()
    with binary.open('rb') as stream:
        while chunk := stream.read(8 * 1024 * 1024):
            digest.update(chunk)
    symbols = subprocess.check_output(['xcrun', 'nm', '-g', str(binary)], text=True)
    imports = sorted(set(re.findall(r'\bU (\S+)', symbols)))
    crypto = sorted(set(line.split()[-1] for line in symbols.splitlines()
                        if re.search(r'ChaCha|chacha|poly1305|CCCrypt|CCRandom|SecRandom|SSL_|AES_|SHA256|unzOpenCurrentFilePassword', line)))
    callers = {api: [] for api in APIS}
    zip_entry = []
    process = subprocess.Popen(['xcrun', 'otool', '-tvV', str(binary)],
                               stdout=subprocess.PIPE, text=True)
    function = 'unknown'
    try:
        for line in process.stdout:
            if line.endswith(':\n') and not line.startswith(' '):
                function = line.strip()[:-1]
            if function in ('_unzOpenCurrentFile3', '_unzOpenCurrentFilePassword') and len(zip_entry) < 80:
                zip_entry.append(line.rstrip())
            if '\tbl\t' not in line and '\tb\t' not in line:
                continue
            target = line.split('symbol stub for: ')[-1].strip()
            if target in callers and function not in callers[target]:
                callers[target].append(function)
    finally:
        process.stdout.close()
    if process.wait():
        raise RuntimeError('otool failed')
    return {'binary': str(binary), 'sha256': digest.hexdigest(), 'imports': imports,
            'reviewedAPICallers': callers, 'cryptoRelatedSymbols': crypto,
            'zipEntryDisassembly': zip_entry,
            'scope': 'Static inventory, not reachability, telemetry, export classification or compliance certification.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    report = audit(args.binary)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(f"SHA-256 {report['sha256']}; inventory saved to {args.output}")


if __name__ == '__main__':
    main()
