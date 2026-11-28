#!/usr/bin/env python3
"""Test binary TCP and UDP, split reads, EOF and timeout using loopback servers."""
import argparse
from pathlib import Path
import platform
import socket
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parent.parent
PAYLOAD = bytes([0, 65, 66, 0, 255])
REPLY = bytes([0, 128, 255, 0, 42])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', type=Path)
    parser.add_argument('--compiler', type=Path, default=ROOT / 'bitc')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='bit-socket-bytes-') as folder:
        work = Path(folder)
        if args.client:
            clients = [('prebuilt', args.client.resolve())]
        else:
            arches = ['x86_64'] if platform.system() == 'Linux' else ['arm64', 'x86_64']
            clients = []
            for arch in arches:
                binary = work / f'client-{arch}'
                subprocess.run([str(args.compiler.resolve()), 'build', str(ROOT / 'tests/rt/socket_bytes.bit'),
                                '--arch', arch, '-o', str(binary)], cwd=ROOT, check=True,
                               stdout=subprocess.DEVNULL)
                clients.append((arch, binary))
        for arch, client in clients:
            for mode in ('roundtrip', 'large', 'timeout'):
                server = socket.socket()
                server.bind(('127.0.0.1', 0))
                server.listen(1)
                server.settimeout(5)
                port = server.getsockname()[1]
                received, errors = [], []
                def serve():
                    try:
                        conn, _ = server.accept()
                        conn.settimeout(5)
                        with conn:
                            if mode == 'timeout':
                                time.sleep(0.2)
                            else:
                                payload = bytearray()
                                wanted = bytes(range(256)) * 1024 if mode == 'large' else PAYLOAD
                                while len(payload) < len(wanted):
                                    chunk = conn.recv(len(wanted) - len(payload))
                                    if not chunk:
                                        break
                                    payload.extend(chunk)
                                received.append(bytes(payload))
                                conn.sendall(REPLY)
                    except Exception as exc:
                        errors.append(repr(exc))
                    finally:
                        server.close()
                thread = threading.Thread(target=serve)
                thread.start()
                result = subprocess.run([str(client), f'127.0.0.1:{port}', mode],
                                        capture_output=True, text=True, timeout=10)
                thread.join(6)
                expected = 'timeout:2' if mode == 'timeout' else '<00 80 ff 00 2a>'
                wanted = bytes(range(256)) * 1024 if mode == 'large' else PAYLOAD
                if (thread.is_alive() or errors or result.returncode or result.stdout.strip() != expected
                        or (mode != 'timeout' and received != [wanted])):
                    raise RuntimeError(f'{arch} {mode}: exit={result.returncode}, output={result.stdout!r}, '
                                       f'error={result.stderr!r}, received={received!r}, server={errors!r}')
            for mode in ('udp', 'udp_empty'):
                server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                server.bind(('127.0.0.1', 0))
                server.settimeout(5)
                port = server.getsockname()[1]
                received, errors = [], []
                def serve_udp():
                    try:
                        packet, peer = server.recvfrom(32)
                        received.append(packet)
                        server.sendto(b'\x00\xff', peer)
                    except Exception as exc:
                        errors.append(repr(exc))
                    finally:
                        server.close()
                thread = threading.Thread(target=serve_udp)
                thread.start()
                result = subprocess.run([str(client), f'127.0.0.1:{port}', mode],
                                        capture_output=True, text=True, timeout=10)
                thread.join(6)
                expected_packet = PAYLOAD if mode == 'udp' else b''
                if (thread.is_alive() or errors or result.returncode or result.stdout.strip() != '<00 ff>'
                        or received != [expected_packet]):
                    raise RuntimeError(f'{arch} {mode}: exit={result.returncode}, output={result.stdout!r}, '
                                       f'error={result.stderr!r}, received={received!r}, server={errors!r}')
            print(f'{arch}: binary TCP/UDP, empty datagram, partial reads, EOF and timeout passed')


if __name__ == '__main__':
    main()
