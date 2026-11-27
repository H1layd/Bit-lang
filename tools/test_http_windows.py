#!/usr/bin/env python3
"""Run the local HTTP contract suite on a Windows host over SSH."""
import argparse
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def run(args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('host', help='SSH host or config alias with Python 3')
    parser.add_argument('--stack-check', action='store_true', help='trap on unaligned Windows calls')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', args.host):
        parser.error('use an SSH hostname or config alias')
    openssl = shutil.which('openssl')
    if not openssl:
        raise SystemExit('openssl is required to create an ephemeral test certificate')
    remote = 'bit_http_test_' + secrets.token_hex(8)
    options = ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15']
    created = False
    with tempfile.TemporaryDirectory(prefix='bit-win-http-') as folder:
        work = Path(folder)
        for source, name in (('tests/rt/http_native.bit', 'client.exe'),
                             ('tests/rt/http_threads.bit', 'threads.exe'),
                             ('tests/windows/ping_spy.bit', 'spy.exe')):
            if args.stack_check and name != 'spy.exe':
                command = [sys.executable, ROOT / 'tools/build_windows_stack_checked.py',
                           ROOT / source, work / name]
            else:
                command = [ROOT / 'bitc', 'build', ROOT / source, '--os', 'windows', '-o', work / name]
            run(command, cwd=ROOT, stdout=subprocess.DEVNULL)
        (work / 'test.py').write_bytes((ROOT / 'tools/test_http_native.py').read_bytes())
        run([openssl, 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
             '-keyout', work / 'key.pem', '-out', work / 'cert.pem', '-days', '1',
             '-subj', '/CN=localhost'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=30)
        try:
            run(['ssh', *options, args.host, f'mkdir {remote}'], timeout=30)
            created = True
            files = [work / n for n in ('client.exe', 'threads.exe', 'spy.exe',
                                       'test.py', 'key.pem', 'cert.pem')]
            run(['scp', '-q', *options, *files, f'{args.host}:{remote}/'], timeout=90)
            command = (f'cd {remote} && py -3 test.py --client client.exe --thread-client '
                       'threads.exe --spy spy.exe --cert cert.pem --key key.pem')
            run(['ssh', *options, args.host, command], timeout=180)
        finally:
            if created:
                subprocess.run(['ssh', *options, args.host, f'rmdir /s /q {remote}'],
                               timeout=30, check=False)


if __name__ == '__main__':
    main()
