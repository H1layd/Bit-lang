#!/usr/bin/env python3
"""Regenerate the macOS HTTP bridge embedded in both runtimes."""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
BEGIN = '// BEGIN GENERATED MACOS HTTP BRIDGE'
END = '// END GENERATED MACOS HTTP BRIDGE'
SOURCE = ROOT / 'rt/http/native.c'


def generate(arch):
    with tempfile.TemporaryDirectory(prefix='bit-macos-http-') as folder:
        output = Path(folder) / 'http.s'
        command = ['clang', '-arch', arch, '-mmacosx-version-min=11.0', '-O1',
                   '-fno-stack-protector', '-fno-asynchronous-unwind-tables',
                   '-Wno-deprecated-declarations', '-S', str(SOURCE), '-o', str(output)]
        if arch == 'x86_64':
            command += ['-masm=intel']
        subprocess.run(command, check=True)
        assembly = output.read_text()
    assembly = re.sub(r'^\s*\.(?:build_version|macosx_version_min|subsections_via_symbols|cfi_\w+)\b[^\n]*\n', '', assembly, flags=re.M)
    return BEGIN + '\n' + assembly.rstrip() + '\n' + END


def update(path, assembly):
    text = path.read_text()
    if BEGIN in text:
        assert text.count(BEGIN) == text.count(END) == 1
        text = text[:text.index(BEGIN)] + assembly + text[text.index(END) + len(END):]
    else:
        for name in ('_bit_fetch', '_bit_http_post', '_bit_download'):
            pattern = r'^' + name + r':.*?(?=^_bit_[a-z_0-9]+:|^\.section|\Z)'
            text, count = re.subn(pattern, '', text, count=1, flags=re.M | re.S)
            if count != 1:
                raise RuntimeError(f'{path}: missing {name}')
        text = text.rstrip() + '\n\n' + assembly + '\n'
    path.write_text(text)


if __name__ == '__main__':
    for arch, filename in (('arm64', 'rt/arm64.s'), ('x86_64', 'rt/x86_64.s')):
        update(ROOT / filename, generate(arch))
        print(f'{filename}: macOS HTTP bridge generated')
