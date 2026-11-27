#!/usr/bin/env python3
"""Check compiler path resolution and temporary cleanup without running rm."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=ROOT / 'bitc')
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    with tempfile.TemporaryDirectory(prefix='bit compiler helpers ') as folder:
        work = Path(folder)
        trapdir = work / 'bin'
        trapdir.mkdir()
        tmpdir = work / 'temporary files'
        tmpdir.mkdir()
        marker = work / 'ran-rm'
        rm = trapdir / 'rm'
        rm.write_text('#!/bin/sh\nprintf called > "$BIT_COMPILER_RM_MARKER"\nexec /bin/rm "$@"\n')
        rm.chmod(0o755)
        (work / 'lib файл.bit').write_text('fn helper() { return "работает https://example.test/a//b"; }\n', encoding='utf-8')
        (work / 'main.bit').write_text('use "lib файл.bit";\nhost { print(helper()); }\n', encoding='utf-8')
        env = dict(os.environ, PATH=str(trapdir) + os.pathsep + os.environ.get('PATH', ''),
                   TMPDIR=str(tmpdir), BIT_COMPILER_RM_MARKER=str(marker))
        uname_marker = work / 'ran-uname'
        uname = trapdir / 'uname'
        uname.write_text('#!/bin/sh\nprintf called > "$BIT_COMPILER_UNAME_MARKER"\nexit 97\n')
        uname.chmod(0o755)
        asm_env = dict(env, BIT_COMPILER_UNAME_MARKER=str(uname_marker))
        asm = subprocess.run([str(compiler), 'asm', 'main.bit'], cwd=work, env=asm_env,
                             capture_output=True, text=True, timeout=60)
        if asm.returncode or uname_marker.exists():
            raise RuntimeError(f'asm without uname: exit={asm.returncode}, '
                               f'error={asm.stderr!r}, uname={uname_marker.exists()}')
        uname.unlink()
        binary = work / 'built program'
        result = subprocess.run([str(compiler), 'build', 'main.bit', '-o', str(binary)],
                                cwd=work, env=env, capture_output=True, text=True, timeout=60)
        if result.returncode or marker.exists() or list(tmpdir.iterdir()):
            raise RuntimeError(f'normal build: exit={result.returncode}, stdout={result.stdout!r}, '
                               f'stderr={result.stderr!r}, rm={marker.exists()}, '
                               f'temporary files={list(tmpdir.iterdir())}')
        actual = subprocess.run([str(binary)], cwd=work, env=env, capture_output=True,
                                text=True, timeout=10, check=True)
        if actual.stdout.strip() != 'работает https://example.test/a//b':
            raise RuntimeError(f'relative module: {actual.stdout!r} {actual.stderr!r}')
        fake_as = trapdir / 'as'
        fake_as.write_text('#!/bin/sh\nprintf "intentional assembler failure\\n" >&2\nexit 1\n')
        fake_as.chmod(0o755)
        failure = subprocess.run([str(compiler), 'build', 'main.bit', '-o', str(binary)],
                                 cwd=work, env=env, capture_output=True, text=True, timeout=60)
        if not failure.returncode or marker.exists() or list(tmpdir.iterdir()):
            raise RuntimeError(f'failed build cleanup: exit={failure.returncode}, '
                               f'output={failure.stdout!r}, rm={marker.exists()}, '
                               f'temporary files={list(tmpdir.iterdir())}')
        print('compiler: relative modules and operation without uname/rm passed')


if __name__ == '__main__':
    main()
