#!/usr/bin/env python3
"""Exercise thread identity, concurrent waiters, and termination without hangs."""
from pathlib import Path
import platform
import subprocess

root = Path(__file__).resolve().parent.parent
work = root / 'build/thread-lifecycle'
work.mkdir(parents=True, exist_ok=True)
arches = ['x86_64'] if platform.system() == 'Linux' else ['arm64', 'x86_64']
for arch in arches:
    for case in ('thread_token_reuse', 'thread_wait_shared'):
        binary = work / f'{case}_{arch}'
        subprocess.run([str(root / 'bitc'), 'build', str(root / 'tests/rt' / (case + '.bit')),
                        '--arch', arch, '-o', str(binary)], cwd=root, check=True,
                       stdout=subprocess.DEVNULL)
        for attempt in range(5):
            try:
                result = subprocess.run([str(binary)], cwd=work, capture_output=True,
                                        text=True, timeout=10)
            except subprocess.TimeoutExpired as error:
                raise SystemExit(f'{arch}: {case} hung on attempt {attempt + 1}') from error
            if result.returncode or result.stdout.strip() != '42':
                raise SystemExit(f'{arch}: {case} failed: {result.returncode} '
                                 f'{result.stdout!r} {result.stderr!r}')
        print(f'{arch}: {case} passed', flush=True)
