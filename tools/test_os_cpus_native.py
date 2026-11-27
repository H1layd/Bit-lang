#!/usr/bin/env python3
"""Check os >> cpus against the OS without starting getconf."""
import argparse
import os
from pathlib import Path
import platform
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', type=Path, help='prebuilt test program')
    args = parser.parse_args()
    expected = os.cpu_count()
    if expected is None:
        raise RuntimeError('system CPU count unavailable')
    with tempfile.TemporaryDirectory(prefix='bit-cpus-native-') as folder:
        work = Path(folder)
        marker = work / 'called'
        spy = work / 'getconf'
        spy.write_text('#!/bin/sh\nprintf called > "$BIT_CPUS_MARKER"\nprintf "12345\\n"\n')
        spy.chmod(0o755)
        env = dict(os.environ, PATH=str(work), BIT_CPUS_MARKER=str(marker))
        if args.client:
            clients = [('prebuilt', args.client.resolve())]
        else:
            arches = ['x86_64'] if platform.system() == 'Linux' else ['arm64', 'x86_64']
            clients = []
            for arch in arches:
                binary = work / f'cpus-{arch}'
                subprocess.run([str(ROOT / 'bitc'), 'build', str(ROOT / 'tests/rt/os_cpus_native.bit'),
                                '--arch', arch, '-o', str(binary)], cwd=ROOT, check=True,
                               stdout=subprocess.DEVNULL)
                clients.append((arch, binary))
        for arch, binary in clients:
            result = subprocess.run([str(binary)], env=env, capture_output=True, text=True,
                                    timeout=10, check=True)
            if result.stdout.strip() != str(expected) or marker.exists():
                raise RuntimeError(f'{arch}: expected {expected}, got {result.stdout!r}; '
                                   f'external getconf={marker.exists()}, stderr={result.stderr!r}')
            print(f'{arch}: {expected} online processors without getconf')


if __name__ == '__main__':
    main()
