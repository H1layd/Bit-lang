#!/usr/bin/env python3
"""Build one Windows program with a trap before any unaligned call."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile
from instrument_x86_stack import instrument

if len(sys.argv) != 3:
    raise SystemExit('usage: build_windows_stack_checked.py SOURCE OUTPUT')
root = Path(__file__).resolve().parent.parent
source, output = sys.argv[1:]
compiler = os.environ.get('BITC_STACK_COMPILER', str(root / 'bitc'))
result = subprocess.run([compiler, 'asm', source, '--os', 'windows'],
                        cwd=root, capture_output=True, text=True)
if result.returncode:
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    raise SystemExit(result.returncode)
with tempfile.TemporaryDirectory(prefix='bit-stack-check-') as folder:
    assembly = Path(folder) / 'checked.s'
    assembly.write_text(instrument(result.stdout))
    result = subprocess.run(['x86_64-w64-mingw32-gcc', '-static', str(assembly),
                             '-o', output, '-lws2_32', '-lbcrypt'],
                            cwd=root, capture_output=True, text=True)
    if result.returncode:
        sys.stdout.write('ошибка сборки Windows (mingw):\n' + result.stdout + result.stderr)
        raise SystemExit(result.returncode)
