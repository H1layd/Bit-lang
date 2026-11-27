#!/usr/bin/env python3
"""Check ICMP locally and prove that bit does not execute a ping program."""
from pathlib import Path
import os
import platform
import resource
import socket
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def available(family, address):
    protocol = socket.IPPROTO_ICMP if family == socket.AF_INET else socket.IPPROTO_ICMPV6
    packet = struct.pack('!BBHHH', 8 if family == socket.AF_INET else 128,
                         0, 0xf135 if family == socket.AF_INET else 0, 0, 0x5162) + b'bit-ping'
    try:
        with socket.socket(family, socket.SOCK_DGRAM, protocol) as sock:
            sock.settimeout(1)
            sock.connect((address, 0))
            sock.send(packet)
            for _ in range(4):
                data = sock.recv(256)
                if family == socket.AF_INET and data and data[0] >> 4 == 4:
                    data = data[(data[0] & 15) * 4:]
                if len(data) >= 16 and data[0] == (0 if family == socket.AF_INET else 129) and data[6:8] == b'Qb' and data[8:16] == b'bit-ping':
                    return True
    except OSError:
        pass
    return False


def main():
    if os.name != 'posix':
        raise SystemExit('this test requires POSIX sockets')
    with tempfile.TemporaryDirectory(prefix='bit-native-ping-') as folder:
        work = Path(folder)
        spy = work / 'ping'
        spy.write_text('#!/bin/sh\nprintf called > "$BIT_PING_MARKER"\n')
        spy.chmod(0o755)
        marker = work / 'spawned'
        env = dict(os.environ, PATH=str(work), BIT_PING_MARKER=str(marker))
        archs = ['x86_64'] if platform.system() == 'Linux' else ['arm64', 'x86_64']
        cases = [('', False)]
        for family, address in ((socket.AF_INET, '127.0.0.1'), (socket.AF_INET6, '::1')):
            if available(family, address):
                cases.append((address, True))
            else:
                print(f'{address}: local ICMP unavailable, test skipped', flush=True)
        both_families = len(cases) == 3
        if both_families:
            cases.append(('localhost', True))
        for arch in archs:
            binary = work / f'bit-ping-{arch}'
            subprocess.run([str(ROOT / 'bitc'), 'build', str(ROOT / 'tests/rt/ping_native.bit'),
                            '--arch', arch, '-o', str(binary)], cwd=ROOT, check=True,
                           stdout=subprocess.DEVNULL)
            for address, expected in cases:
                result = subprocess.run([str(binary), address], cwd=work, env=env,
                                        capture_output=True, text=True, timeout=10, check=True)
                if result.stdout.strip() != str(expected).lower() or marker.exists():
                    raise RuntimeError(f'{arch} {address!r}: output={result.stdout!r}, '
                                       f'error={result.stderr!r}, external ping={marker.exists()}')
                print(f'{arch}: native ping {address!r} passed', flush=True)
            if both_families:
                threads = work / f'bit-ping-threads-{arch}'
                subprocess.run([str(ROOT / 'bitc'), 'build', str(ROOT / 'tests/rt/ping_threads.bit'),
                                '--arch', arch, '-o', str(threads)], cwd=ROOT, check=True,
                               stdout=subprocess.DEVNULL)
                def limit_fds():
                    soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
                    resource.setrlimit(resource.RLIMIT_NOFILE, (min(64, soft), hard))
                result = subprocess.run([str(threads)], cwd=work, env=env, capture_output=True,
                                        text=True, timeout=60, check=True, preexec_fn=limit_fds)
                if result.stdout.strip() != '64 64 64 64' or marker.exists():
                    raise RuntimeError(f'{arch} threaded ping: {result.stdout!r} '
                                       f'{result.stderr!r}, external ping={marker.exists()}')
                print(f'{arch}: threaded IPv4/IPv6 ping with bounded file descriptors passed', flush=True)


if __name__ == '__main__':
    main()
