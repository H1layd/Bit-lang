#!/usr/bin/env python3
"""Verify Linux HTTP fails cleanly when libcurl cannot be loaded."""
import argparse
import os
from pathlib import Path
import platform
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    if platform.system() != 'Linux':
        raise SystemExit('this test requires Linux')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='bit-http-no-library-') as folder:
        work = Path(folder)
        client = args.client.resolve() if args.client else work / 'client'
        if not args.client:
            subprocess.run([str(ROOT / 'bitc'), 'build', str(ROOT / 'tests/rt/http_native.bit'),
                            '-o', str(client)], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
        source = work / 'nodlopen.s'
        source.write_text('.intel_syntax noprefix\n.text\n.globl dlopen\n.type dlopen, @function\n'
                          'dlopen:\n  xor eax, eax\n  ret\n.section .note.GNU-stack,"",@progbits\n')
        subprocess.run(['as', '--64', str(source), '-o', str(work / 'nodlopen.o')], check=True)
        subprocess.run(['ld', '-shared', '-o', str(work / 'nodlopen.so'), str(work / 'nodlopen.o')], check=True)
        marker = work / 'spawned'
        spy = work / 'curl'
        spy.write_text('#!/bin/sh\nprintf called > "$BIT_HTTP_MARKER"\nexit 99\n')
        spy.chmod(0o755)
        env = dict(os.environ, LD_PRELOAD=str(work / 'nodlopen.so'), PATH=str(work), BIT_HTTP_MARKER=str(marker))
        result = subprocess.run([str(client), 'fetch_error', 'http://127.0.0.1:1/'],
                                env=env, capture_output=True, text=True, timeout=10)
        if result.returncode or 'libcurl.so.4' not in result.stdout or marker.exists():
            raise RuntimeError(f'missing library: rc={result.returncode}, out={result.stdout!r}, '
                               f'err={result.stderr!r}, external curl={marker.exists()}')
        print('Linux: missing libcurl raises a recoverable error without launching curl')


if __name__ == '__main__':
    main()
