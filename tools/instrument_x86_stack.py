#!/usr/bin/env python3
"""Insert a trap before any x86-64 call made with a misaligned stack."""
from pathlib import Path
import re
import sys


def instrument(text):
    lines = []
    count = 0
    for line in text.splitlines():
        match = re.match(r'^(\s*)(?:([A-Za-z_.$][\w.$]*|\d+):\s*)?(call\s+.*)$', line)
        if match:
            indent, label, instruction = match.groups()
            if label:
                lines.append(f'{label}:')
            marker = f'Lstack_alignment_check_{count}'
            count += 1
            lines.extend((f'{indent}test rsp, 15', f'{indent}jz {marker}',
                          f'{indent}ud2', f'{marker}:', f'{indent}{instruction}'))
        else:
            lines.append(line)
    if not count:
        raise ValueError('no call instructions found in generated assembly')
    return '\n'.join(lines) + '\n'


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('usage: instrument_x86_stack.py INPUT OUTPUT')
    Path(sys.argv[2]).write_text(instrument(Path(sys.argv[1]).read_text()))
