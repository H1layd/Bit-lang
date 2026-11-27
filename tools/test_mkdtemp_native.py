#!/usr/bin/env python3
"""Check atomic temporary-directory creation with concurrent processes."""
import argparse
import os
from pathlib import Path
import platform
import stat
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', type=Path, help='prebuilt test program')
    parser.add_argument('--compiler', type=Path, default=ROOT / 'bitc')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='bit-mkdtemp-') as folder:
        work = Path(folder)
        if args.client:
            clients = [('prebuilt', args.client.resolve())]
        else:
            arches = ['x86_64'] if platform.system() == 'Linux' else ['arm64', 'x86_64']
            clients = []
            for arch in arches:
                binary = work / f'mkdtemp-{arch}'
                subprocess.run([str(args.compiler.resolve()), 'build', str(ROOT / 'tests/rt/mkdtemp_native.bit'),
                                '--arch', arch, '-o', str(binary)], cwd=ROOT, check=True,
                               stdout=subprocess.DEVNULL)
                clients.append((arch, binary))
        for arch, binary in clients:
            group = work / (arch + ' тест папка')
            group.mkdir()
            template = str(group / 'bitc.XXXXXX')
            processes = [subprocess.Popen([str(binary), template], stdout=subprocess.PIPE,
                                          stderr=subprocess.PIPE, text=True, encoding='utf-8', errors='replace')
                         for _ in range(16)]
            paths = []
            for proc in processes:
                stdout, stderr = proc.communicate(timeout=30)
                path = Path(stdout.strip())
                if proc.returncode or path.parent != group or not path.name.startswith('bitc.') or not path.is_dir():
                    raise RuntimeError(f'{arch}: exit={proc.returncode}, output={stdout!r}, stderr={stderr!r}')
                if os.name != 'nt' and stat.S_IMODE(path.stat().st_mode) & 0o077:
                    raise RuntimeError(f'{arch}: temporary directory accessible to others: {path}')
                paths.append(path)
            if len(set(paths)) != len(paths):
                raise RuntimeError(f'{arch}: concurrent directory names were reused')
            for bad in (str(group / 'bad'), str(group / 'missing' / 'bitc.XXXXXX')):
                result = subprocess.run([str(binary), bad], capture_output=True, text=True, timeout=30)
                if result.returncode or result.stdout.strip() != 'recovered':
                    raise RuntimeError(f'{arch}: failed template {bad!r}: {result.stdout!r} {result.stderr!r}')
            print(f'{arch}: atomic temporary directories and recover passed')


if __name__ == '__main__':
    main()
