#!/usr/bin/env python3
"""Check stack alignment in generated x86-64 runtimes.

Follow local branches from each runtime function's standard x86-64 entry. Calls
must have RSP aligned to 16 bytes; direct tail calls must retain entry alignment.
Unknown stack states fail the audit. This does not prove shadow-space size,
register preservation, or the correctness of indirect call targets.
"""
from collections import deque
from pathlib import Path
import argparse
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
FUNCTION = re.compile(r'^(_(?:bit|w)_[a-zA-Z0-9_]+):')
LABEL = re.compile(r'^\s*([\w.]+):')
TAIL = re.compile(r'_(?:bit|w)_[a-z0-9_]+')


def audit(text):
    lines = text.splitlines()
    functions = [(i, match.group(1)) for i, line in enumerate(lines)
                 if (match := FUNCTION.match(line))]
    if not functions:
        raise ValueError('no runtime functions found')
    functions.append((len(lines), '<end>'))
    problems = set()
    for (start, name), (end, _) in zip(functions, functions[1:]):
        code = lines[start:end]
        labels = {}
        for index, line in enumerate(code):
            match = LABEL.match(line)
            if match:
                labels.setdefault(match.group(1), []).append(index)

        def destination(token, index):
            numeric = re.fullmatch(r'(\d+)([fb])', token)
            if numeric:
                choices = labels.get(numeric.group(1), [])
                forward = numeric.group(2) == 'f'
                candidates = [n for n in choices if (n > index if forward else n < index)]
                return (min(candidates) if forward else max(candidates)) if candidates else None
            choices = labels.get(token, [])
            return choices[0] if choices else None

        # (instruction, RSP mod 16, RBP mod 16); None denotes unknown.
        pending = deque([(1, 8, None)])
        seen = set()
        while pending:
            index, rsp, rbp = pending.popleft()
            state = (index, rsp, rbp)
            if index >= len(code) or state in seen:
                continue
            seen.add(state)
            raw = code[index].split('//')[0].split('#')[0].strip()
            raw = re.sub(r'^[A-Za-z0-9_.]+:\s*', '', raw).strip()
            if not raw or raw.startswith('.'):
                pending.append((index + 1, rsp, rbp))
                continue
            match = re.match(r'(\w+)\s*(.*)', raw)
            if not match:
                pending.append((index + 1, rsp, rbp))
                continue
            op, args = match.group(1).lower(), match.group(2).strip().lower()
            if op == 'push':
                rsp = (rsp - 8) % 16 if rsp is not None else None
            elif op == 'pop':
                rsp = (rsp + 8) % 16 if rsp is not None and args != 'rsp' else None
                if args == 'rbp':
                    rbp = None
            elif op in ('pushf', 'pushfq'):
                rsp = (rsp - 8) % 16 if rsp is not None else None
            elif op in ('popf', 'popfq'):
                rsp = (rsp + 8) % 16 if rsp is not None else None
            elif op in ('sub', 'add') and args.startswith('rsp,'):
                try:
                    amount = int(args.split(',', 1)[1].strip(), 0)
                    rsp = (rsp + (-amount if op == 'sub' else amount)) % 16 if rsp is not None else None
                except ValueError:
                    rsp = None
            elif op == 'and' and args.startswith('rsp,'):
                value = args.split(',', 1)[1].strip()
                rsp = 0 if value in ('-16', '0xfffffffffffffff0') else None
            elif op == 'mov' and args == 'rbp, rsp':
                rbp = rsp
            elif op == 'mov' and args == 'rsp, rbp':
                rsp = rbp
            elif op == 'lea' and args.startswith('rsp,'):
                form = re.fullmatch(r'rsp,\s*\[rbp\s*([+-])\s*(\d+)\]', args)
                rsp = ((rbp + int(form.group(2)) * (1 if form.group(1) == '+' else -1)) % 16
                       if form and rbp is not None else None)
            elif op == 'leave':
                rsp, rbp = ((rbp + 8) % 16 if rbp is not None else None), None
            elif op in ('mov', 'lea', 'xor', 'or', 'add', 'sub', 'and', 'xchg') and re.match(r'^(rsp|esp|sp)\s*,', args):
                rsp = None
            elif op in ('mov', 'lea', 'xor', 'or', 'add', 'sub', 'and', 'xchg') and args.startswith('rbp,'):
                rbp = None
            elif op == 'xchg' and re.search(r'\b(rsp|esp|sp)\b', args):
                rsp = None
            elif op == 'enter':
                rsp, rbp = None, None

            line = start + index + 1
            if op == 'call' and rsp != 0:
                problems.add((line, name, 'call', args, rsp))
            if (op.startswith('j') and TAIL.fullmatch(args)
                    and args not in ('_bit_die', '_bit_oom') and rsp != 8):
                problems.add((line, name, 'tail', args, rsp))
            if op in ('ret', 'retq') and rsp != 8:
                problems.add((line, name, 'return', args, rsp))
            if op in ('ret', 'retq', 'ud2'):
                continue
            if op == 'jmp':
                target = destination(args, index)
                if target is not None:
                    pending.append((target, rsp, rbp))
                continue
            if op.startswith('j'):
                target = destination(args, index)
                if target is not None:
                    pending.append((target, rsp, rbp))
            pending.append((index + 1, rsp, rbp))
    return len(functions) - 1, sorted(problems)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', type=Path, default=ROOT / 'rt/x86_64-windows.s')
    args = parser.parse_args()
    count, problems = audit(args.runtime.read_text())
    for line, name, kind, target, rsp in problems:
        print(f'{args.runtime}:{line}: {name}: {kind} {target}: RSP mod 16 = {rsp}')
    print(f'{args.runtime.name}: {count} functions; {len(problems)} stack-alignment issues')
    return int(bool(problems))


if __name__ == '__main__':
    sys.exit(main())
