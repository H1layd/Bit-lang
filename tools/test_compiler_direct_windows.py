#!/usr/bin/env python3
"""Run the compiler's direct-child helper on a Windows host over SSH."""
import argparse
from pathlib import Path
import re
import secrets
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def run(args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('host', help='SSH host or config alias')
    parser.add_argument('--stack-check', action='store_true')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', args.host):
        parser.error('use an SSH hostname or config alias')
    remote = 'bit_direct_test_' + secrets.token_hex(8)
    options = ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15']
    created = False
    with tempfile.TemporaryDirectory(prefix='bit-win-direct-') as folder:
        work = Path(folder)
        child = work / 'child.exe'
        parent = work / 'parent.exe'
        run([ROOT / 'bitc', 'build', ROOT / 'tests/rt/compiler_direct_child.bit',
             '--os', 'windows', '-o', child], cwd=ROOT, stdout=subprocess.DEVNULL)
        if args.stack_check:
            run(['python3', ROOT / 'tools/build_windows_stack_checked.py',
                 ROOT / 'tests/rt/compiler_direct_parent.bit', parent], cwd=ROOT, stdout=subprocess.DEVNULL)
        else:
            run([ROOT / 'bitc', 'build', ROOT / 'tests/rt/compiler_direct_parent.bit',
                 '--os', 'windows', '-o', parent], cwd=ROOT, stdout=subprocess.DEVNULL)
        try:
            run(['ssh', *options, args.host, f'mkdir {remote}'], timeout=30)
            created = True
            run(['scp', '-q', *options, child, parent, ROOT / 'tests/windows/compiler_direct_probe.py',
                 f'{args.host}:{remote}/'], timeout=90)
            run(['ssh', *options, args.host,
                 f'cd {remote} && python compiler_direct_probe.py parent.exe child.exe'], timeout=90)
        finally:
            if created:
                subprocess.run(['ssh', *options, args.host, f'rmdir /s /q {remote}'], timeout=30, check=False)


if __name__ == '__main__':
    main()
