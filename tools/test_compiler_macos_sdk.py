#!/usr/bin/env python3
"""Check macOS SDK selection without xcrun using harmless assembler/linker traps."""
import argparse
import os
from pathlib import Path
import platform
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    if platform.system() != 'Darwin':
        print('macOS SDK selection: skipped on non-macOS')
        return
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=ROOT / 'bitc')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='bit-sdk-selection-') as folder:
        work = Path(folder)
        tools = work / 'bin'
        tools.mkdir()
        (work / 'main.bit').write_text('host { print("ok"); }\n', encoding='utf-8')
        scripts = {
            'xcrun': '#!/bin/sh\nprintf called > "$BIT_XCRUN_MARKER"\nexit 97\n',
            'as': '#!/bin/sh\nwhile [ "$#" -gt 0 ]; do if [ "$1" = -o ]; then shift; : > "$1"; fi; shift; done\n',
            'ld': '#!/bin/sh\nprintf "%s\\n" "$@" > "$BIT_LD_ARGS"\nexit 0\n',
        }
        for name, source in scripts.items():
            target = tools / name
            target.write_text(source)
            target.chmod(0o755)
        sdk = work / 'SDK path with space'
        sdk.mkdir()
        developer = work / 'developer dir'
        (developer / 'SDKs' / 'MacOSX.sdk').mkdir(parents=True)
        (developer / 'SDKs' / 'MacOSX13.3.sdk').mkdir()
        app = work / 'Fake Xcode.app' / 'Contents' / 'Developer'
        (app / 'SDKs' / 'MacOSX.sdk').mkdir(parents=True)
        cases = [
            ('SDKROOT', {'SDKROOT': str(sdk), 'DEVELOPER_DIR': str(developer)}, sdk),
            ('DEVELOPER_DIR', {'SDKROOT': '', 'DEVELOPER_DIR': str(developer)}, developer / 'SDKs' / 'MacOSX.sdk'),
            ('named SDK', {'SDKROOT': 'macosx13.3', 'DEVELOPER_DIR': str(developer)},
             developer / 'SDKs' / 'MacOSX13.3.sdk'),
            ('app path', {'SDKROOT': '', 'DEVELOPER_DIR': str(work / 'Fake Xcode.app') + '/'},
             app / 'SDKs' / 'MacOSX.sdk'),
        ]
        for label, overrides, expected in cases:
            env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ.get('PATH', ''),
                       BIT_XCRUN_MARKER=str(work / 'ran-xcrun'), BIT_LD_ARGS=str(work / 'ld-args'),
                       **overrides)
            result = subprocess.run([str(args.compiler.resolve()), 'build', 'main.bit', '-o', str(work / 'app')],
                                    cwd=work, env=env, capture_output=True, text=True, timeout=60)
            if result.returncode:
                raise RuntimeError(f'{label}: exit={result.returncode}, {result.stdout!r} {result.stderr!r}')
            ld_args = (work / 'ld-args').read_text().splitlines()
            if '-syslibroot' not in ld_args or ld_args.index('-syslibroot') + 1 >= len(ld_args):
                raise RuntimeError(f'{label}: missing syslibroot: {ld_args!r}')
            selected = Path(ld_args[ld_args.index('-syslibroot') + 1])
            if selected != expected or (work / 'ran-xcrun').exists():
                raise RuntimeError(f'{label}: selected={selected}, expected={expected}, '
                                   f'xcrun={(work / "ran-xcrun").exists()}')
            print(f'{label}: selected without xcrun')


if __name__ == '__main__':
    main()
