"""Run the internal direct-child probe on Windows."""
import subprocess
import sys

result = subprocess.run([sys.argv[1], sys.argv[2]], capture_output=True, text=True, timeout=30)
expected = 'child:with spaces\ncode:37\n'
if result.returncode or result.stdout.replace('\r', '') != expected:
    raise SystemExit(f'failed: exit={result.returncode}, output={result.stdout!r}, stderr={result.stderr!r}')
print('Windows: direct child and exit status passed')
