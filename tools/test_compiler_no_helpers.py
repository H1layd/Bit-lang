#!/usr/bin/env python3
"""Check compiler path resolution and temporary cleanup without running rm."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

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
        mktemp_marker = work / 'ran-mktemp'
        rm = trapdir / 'rm'
        rm.write_text('#!/bin/sh\nprintf called > "$BIT_COMPILER_RM_MARKER"\nexec /bin/rm "$@"\n')
        rm.chmod(0o755)
        mktemp = trapdir / 'mktemp'
        mktemp.write_text('#!/bin/sh\nprintf called > "$BIT_COMPILER_MKTEMP_MARKER"\nexit 97\n')
        mktemp.chmod(0o755)
        (work / 'lib файл.bit').write_text('fn helper() { return "работает https://example.test/a//b"; }\n', encoding='utf-8')
        (work / 'main.bit').write_text('use "lib файл.bit";\nhost { print(helper()); }\n', encoding='utf-8')
        env = dict(os.environ, PATH=str(trapdir) + os.pathsep + os.environ.get('PATH', ''),
                   TMPDIR=str(tmpdir), BIT_COMPILER_RM_MARKER=str(marker),
                   BIT_COMPILER_MKTEMP_MARKER=str(mktemp_marker))
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
        if result.returncode or marker.exists() or mktemp_marker.exists() or list(tmpdir.iterdir()):
            raise RuntimeError(f'normal build: exit={result.returncode}, stdout={result.stdout!r}, '
                               f'stderr={result.stderr!r}, rm={marker.exists()}, '
                               f'mktemp={mktemp_marker.exists()}, '
                               f'temporary files={list(tmpdir.iterdir())}')
        actual = subprocess.run([str(binary)], cwd=work, env=env, capture_output=True,
                                text=True, timeout=10, check=True)
        if actual.stdout.strip() != 'работает https://example.test/a//b':
            raise RuntimeError(f'relative module: {actual.stdout!r} {actual.stderr!r}')
        (work / 'arguments.bit').write_text(
            'host { string line >> input; print("input:{line}"); '
            'for a in term >> args { print("arg:{a}"); } do(term >> exit(37)); }\n',
            encoding='utf-8')
        values = ['', 'привет мир', "a'b", 'a"b', '$HOME', '$(echo not-a-command)',
                  '--looks-like-flag', 'line one\nline two']
        run = subprocess.run([str(compiler), 'run', 'arguments.bit', '--', *values],
                             cwd=work, env=env, input='вход\n', capture_output=True,
                             text=True, timeout=60)
        expected = 'input:вход\n' + ''.join('arg:' + value + '\n' for value in values)
        if (run.returncode != 37 or run.stdout != expected or run.stderr or marker.exists()
                or mktemp_marker.exists() or list(tmpdir.iterdir())):
            raise RuntimeError(f'direct run: exit={run.returncode}, output={run.stdout!r}, '
                               f'expected={expected!r}, stderr={run.stderr!r}')
        (work / 'interrupt.bit').write_text(
            'host { file f = term >> args >> get(0, ""); do(f >> write("ready")); '
            'do(term >> wait(30000)); }\n', encoding='utf-8')
        ready = work / 'child-ready'
        child = subprocess.Popen([str(compiler), 'run', 'interrupt.bit', '--', str(ready)],
                                 cwd=work, env=env, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, start_new_session=True)
        try:
            deadline = time.monotonic() + 30
            while not ready.exists() and child.poll() is None and time.monotonic() < deadline:
                time.sleep(0.02)
            if not ready.exists():
                raise RuntimeError('compiled program did not start for interrupt test')
            os.killpg(child.pid, signal.SIGINT)
            stdout, stderr = child.communicate(timeout=20)
            if child.returncode != 130 or list(tmpdir.iterdir()):
                raise RuntimeError(f'interrupted run: exit={child.returncode}, '
                                   f'stdout={stdout!r}, stderr={stderr!r}, '
                                   f'temporary files={list(tmpdir.iterdir())}')
        finally:
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGKILL)
                child.communicate()
        fake_as = trapdir / 'as'
        fake_as.write_text('#!/bin/sh\nprintf "intentional assembler failure\\n" >&2\nexit 1\n')
        fake_as.chmod(0o755)
        failure = subprocess.run([str(compiler), 'build', 'main.bit', '-o', str(binary)],
                                 cwd=work, env=env, capture_output=True, text=True, timeout=60)
        if not failure.returncode or marker.exists() or mktemp_marker.exists() or list(tmpdir.iterdir()):
            raise RuntimeError(f'failed build cleanup: exit={failure.returncode}, '
                               f'output={failure.stdout!r}, rm={marker.exists()}, '
                               f'temporary files={list(tmpdir.iterdir())}')
        print('compiler: helper-free paths, direct run and interrupt cleanup passed')


if __name__ == '__main__':
    main()
