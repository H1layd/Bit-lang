#!/usr/bin/env python3
"""Check that os >> procs lists the running program without ps/tasklist."""
import argparse
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', type=Path, help='prebuilt test program')
    parser.add_argument('--spy', type=Path, help='Windows tasklist.exe trap')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='bit-procs-native-') as folder:
        work = Path(folder)
        marker = work / 'called'
        if os.name == 'nt':
            if not args.spy:
                parser.error('on Windows pass --spy with a tasklist.exe trap')
            shutil.copyfile(args.spy, work / 'tasklist.exe')
            path = str(work) + os.pathsep + os.environ.get('PATH', '')
        else:
            spy = work / 'ps'
            spy.write_text('#!/bin/sh\nprintf called > "$BIT_PROCS_MARKER"\nprintf "fake processes\\n"\n')
            spy.chmod(0o755)
            path = str(work)
        env = dict(os.environ, PATH=path, BIT_PROCS_MARKER=str(marker))
        if args.client:
            clients = [('prebuilt', args.client.resolve())]
        else:
            arches = ['x86_64'] if platform.system() == 'Linux' else ['arm64', 'x86_64']
            clients = []
            for arch in arches:
                binary = work / f'procs-{arch}'
                subprocess.run([str(ROOT / 'bitc'), 'build', str(ROOT / 'tests/rt/os_procs_native.bit'),
                                '--arch', arch, '-o', str(binary)], cwd=ROOT, check=True,
                               stdout=subprocess.DEVNULL)
                clients.append((arch, binary))
        for arch, binary in clients:
            for _ in range(3):
                proc = subprocess.Popen([str(binary)], cwd=work, env=env, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, text=True, encoding='utf-8', errors='replace')
                stdout, stderr = proc.communicate(timeout=30)
                lines = stdout.splitlines()
                if (proc.returncode != 0 or not lines or lines[0] != str(proc.pid) or
                        not any(line.startswith(f'{proc.pid} ') and len(line) > len(str(proc.pid)) + 1
                                for line in lines[1:]) or marker.exists()):
                    raise RuntimeError(f'{arch}: pid={proc.pid}, exit={proc.returncode}, '
                                       f'output={stdout!r}, stderr={stderr!r}, '
                                       f'external utility={marker.exists()}')
            print(f'{arch}: process list contains self without ps/tasklist')


if __name__ == '__main__':
    main()
