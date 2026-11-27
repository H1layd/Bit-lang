#!/usr/bin/env python3
"""Test Windows ICMP and prove no ping executable is launched over SSH."""
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
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', args.host):
        parser.error('use an SSH hostname or config alias')
    remote = 'bit_ping_test_' + secrets.token_hex(8)
    options = ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15']
    created = False
    with tempfile.TemporaryDirectory(prefix='bit-win-ping-') as folder:
        work = Path(folder)
        for source, name in (('tests/rt/ping_native.bit', 'ping-test.exe'),
                             ('tests/rt/ping_threads.bit', 'ping-threads.exe'),
                             ('tests/windows/ping_spy.bit', 'ping.exe')):
            run([ROOT / 'bitc', 'build', ROOT / source, '--os', 'windows', '-o', work / name],
                cwd=ROOT, stdout=subprocess.DEVNULL)
        (work / 'test.bat').write_bytes((ROOT / 'tests/windows/ping_native.bat').read_bytes())
        try:
            run(['ssh', *options, args.host, f'mkdir {remote}'], timeout=30)
            created = True
            run(['scp', '-q', *options, work / 'ping-test.exe', work / 'ping-threads.exe',
                 work / 'ping.exe', work / 'test.bat', f'{args.host}:{remote}/'], timeout=90)
            run(['ssh', *options, args.host, f'cd {remote} && test.bat'], timeout=120)
        finally:
            if created:
                subprocess.run(['ssh', *options, args.host, f'rmdir /s /q {remote}'],
                               timeout=30, check=False)


if __name__ == '__main__':
    main()
