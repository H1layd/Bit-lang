#!/usr/bin/env python3
"""Verify the x86 stack audit and ensure a regression is detected."""
from pathlib import Path
from audit_x86_stack import audit
from instrument_x86_stack import instrument

root = Path(__file__).resolve().parent.parent
for name in ('x86_64.s', 'x86_64-linux.s', 'x86_64-windows.s'):
    runtime = (root / 'rt' / name).read_text()
    count, problems = audit(runtime)
    assert count >= 100, f'{name}: unexpected function count: {count}'
    assert not problems, '\n'.join(map(str, problems))
    print(f'{name}: {count} functions, stack alignment checked')
runtime = (root / 'rt/x86_64-windows.s').read_text()
original = '_w_malloc:\n    sub rsp, 40\n'
assert runtime.count(original) == 1
broken = runtime.replace(original, '_w_malloc:\n    sub rsp, 32\n', 1)
_, problems = audit(broken)
assert any(name == '_w_malloc' and kind == 'call' for _, name, kind, _, _ in problems), \
    'audit did not detect an intentionally misaligned call'
unknown = '_bit_probe:\n    mov rsp, rax\n    call external\n    ret\n'
_, problems = audit(unknown)
assert any(kind == 'call' and rsp is None for _, _, kind, _, rsp in problems), \
    'audit accepted an unknown stack state'
sample = instrument('7: call first\nlabel_name: call second\n')
assert sample.count('test rsp, 15') == 2 and '7:\n' in sample and 'label_name:\n' in sample
print('x86 stack audit detected deliberately misaligned and unknown stack states')
