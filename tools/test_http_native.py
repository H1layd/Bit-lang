#!/usr/bin/env python3
"""Local HTTP contract tests; the client must not launch curl."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import platform
import shutil
import ssl
import socket
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parent.parent
BINARY = bytes([0, 1, 127, 128, 255, 10])
POST = 'x=привет & y=2'.encode()
LARGE = bytes(range(256)) * 8192
LARGE_TEXT = b"a" * (2 * 1024 * 1024)


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *_args):
        pass

    def end_headers(self):
        self.send_header('Connection', 'close')
        self.close_connection = True
        super().end_headers()

    def do_GET(self):
        if self.path == '/redirect':
            self.send_response(302)
            self.send_header('Location', '/plain')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        if self.path == '/credential-redirect':
            self.send_response(302)
            self.send_header('Location', '//bit-user:bit-secret@127.0.0.1:%d/plain' % self.server.server_port)
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        if self.path == '/unsupported-transfer':
            self.send_response(200)
            self.send_header('Transfer-Encoding', 'gzip, chunked')
            self.end_headers()
            self.wfile.write(b'3\r\nabc\r\n0\r\n\r\n')
            return
        if self.path == '/without-length':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'until-close')
            return
        if self.path == '/not-modified':
            self.send_response(304)
            self.send_header('Content-Length', '100')
            self.end_headers()
            return
        if self.path == '/ambiguous-framing':
            self.send_response(200)
            self.send_header('Transfer-Encoding', 'chunked')
            self.send_header('Content-Length', '3')
            self.end_headers()
            self.wfile.write(b'3\r\nabc\r\n0\r\n\r\n')
            self.wfile.flush()
            return
        if self.path == '/conflicting-length':
            self.send_response(200)
            self.send_header('Content-Length', '3')
            self.send_header('Content-Length', '4')
            self.end_headers()
            self.wfile.write(b'abc')
            self.wfile.flush()
            return
        if self.path == '/truncated-chunk':
            self.send_response(200)
            self.send_header('Transfer-Encoding', 'chunked')
            self.end_headers()
            self.wfile.write(b'5\r\nabc')
            self.wfile.flush()
            return
        if self.path == '/missing-final-chunk':
            self.send_response(200)
            self.send_header('Transfer-Encoding', 'chunked')
            self.end_headers()
            self.wfile.write(b'3\r\nabc\r\n')
            self.wfile.flush()
            return
        if self.path == '/truncated':
            self.send_response(200)
            self.send_header('Content-Length', '100')
            self.end_headers()
            self.wfile.write(b'short')
            self.wfile.flush()
            return
        if self.path.startswith('/query?'):
            body = self.path.encode()
            self.send_response(200)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path == '/chunked':
            self.send_response(200)
            self.send_header('Transfer-Encoding', 'chunked')
            self.end_headers()
            for piece in (b'one', b'-', b'two'):
                self.wfile.write(f'{len(piece):x}\r\n'.encode() + piece + b'\r\n')
                self.wfile.flush()
                time.sleep(0.01)
            self.wfile.write(b'0\r\nX-Test: done\r\n\r\n')
            self.wfile.flush()
            return
        body = {'/plain': b'hello-bit', '/binary': BINARY, '/large-binary': LARGE, '/large-text': LARGE_TEXT,
                '/not-found': b'missing-body'}.get(self.path, b'unknown')
        self.send_response(404 if self.path == '/not-found' else 200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        n = int(self.headers.get('Content-Length', '0'))
        body = self.rfile.read(n)
        if self.path == '/post-redirect':
            self.send_response(307)
            self.send_header('Location', '/post')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', type=Path, help='prebuilt test client')
    parser.add_argument('--spy', type=Path, help='Windows executable used as fake curl.exe')
    parser.add_argument('--thread-client', type=Path, help='prebuilt concurrent test client')
    parser.add_argument('--cert', type=Path, help='self-signed test certificate')
    parser.add_argument('--key', type=Path, help='private key for the test certificate')
    parser.add_argument('--allow-external', action='store_true',
                        help='compare the old curl-backed implementation; not a native test')
    args = parser.parse_args()
    if bool(args.cert) != bool(args.key):
        parser.error('--cert and --key must be provided together')
    with tempfile.TemporaryDirectory(prefix='bit-http-native-') as folder:
        work = Path(folder)
        marker = work / 'spawned'
        if not args.allow_external:
            if os.name == 'nt':
                if args.spy is None:
                    parser.error('on Windows pass --spy pointing to a fake curl.exe')
                shutil.copyfile(args.spy, work / 'curl.exe')
            else:
                spy = work / 'curl'
                spy.write_text('#!/bin/sh\nprintf called > "$BIT_HTTP_MARKER"\nexit 99\n')
                spy.chmod(0o755)
        else:
            print('baseline only: external curl is allowed', flush=True)
        path = os.environ.get('PATH', '') if args.allow_external else str(work)
        env = dict(os.environ, PATH=path, BIT_HTTP_MARKER=str(marker), BIT_PING_MARKER=str(marker))
        clients = []
        if args.client:
            clients.append(('prebuilt', args.client.resolve(),
                            args.thread_client.resolve() if args.thread_client else None))
        else:
            arches = ['x86_64'] if platform.system() == 'Linux' else ['arm64', 'x86_64']
            for arch in arches:
                client = work / f'client-{arch}'
                subprocess.run([str(ROOT / 'bitc'), 'build', str(ROOT / 'tests/rt/http_native.bit'),
                                '--arch', arch, '-o', str(client)], cwd=ROOT, check=True,
                               stdout=subprocess.DEVNULL)
                threaded = work / f'threaded-{arch}'
                subprocess.run([str(ROOT / 'bitc'), 'build', str(ROOT / 'tests/rt/http_threads.bit'),
                                '--arch', arch, '-o', str(threaded)], cwd=ROOT, check=True,
                               stdout=subprocess.DEVNULL)
                clients.append((arch, client, threaded))
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        server.daemon_threads = True
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            root = f'http://127.0.0.1:{server.server_port}'
            cases = [('fetch', '/plain', 'hello-bit'), ('fetch', '/chunked', 'one-two'),
                     ('fetch', '/redirect', 'hello-bit'), ('fetch', '/not-found', 'missing-body'),
                     ('fetch', '/plain#not-sent', 'hello-bit'),
                     ('fetch', '/without-length', 'until-close'),
                     ('fetch', '/not-modified', ''),
                     ('fetch', '/query?x=a%2Fb&y=a+b', '/query?x=a%2Fb&y=a+b'),
                     ('fetch_size', '/large-text', str(len(LARGE_TEXT))),
                     ('tls_invalid', '/truncated', 'rejected'),
                     ('tls_invalid', '/truncated-chunk', 'rejected'),
                     ('tls_invalid', '/missing-final-chunk', 'rejected'),
                     ('tls_invalid', '/ambiguous-framing', 'rejected'),
                     ('tls_invalid', '/conflicting-length', 'rejected'),
                     ('post', '/post', POST.decode()), ('post', '/post-redirect', POST.decode()),
                     ('download', '/binary', '<00 01 7f 80 ff 0a>'),
                     ('download_size', '/large-binary', str(len(LARGE)))]
            if platform.system() in ('Darwin', 'Linux') and not args.allow_external:
                cases += [('tls_invalid', '/unsupported-transfer', 'rejected'),
                          ('tls_invalid', '/credential-redirect', 'rejected')]
            openssl = shutil.which('openssl')
            tls_server = None
            tls_thread = None
            if args.cert or openssl:
                key, cert = args.key, args.cert
                if not args.cert:
                    key, cert = work / 'test-key.pem', work / 'test-cert.pem'
                    subprocess.run([openssl, 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                                    '-keyout', str(key), '-out', str(cert), '-days', '1',
                                    '-subj', '/CN=localhost'], stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL, check=True, timeout=30)
                tls_server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
                tls_server.daemon_threads = True
                context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                context.load_cert_chain(cert, key)
                tls_server.socket = context.wrap_socket(tls_server.socket, server_side=True)
                tls_thread = threading.Thread(target=tls_server.serve_forever, daemon=True)
                tls_thread.start()
            else:
                print('self-signed TLS test skipped: openssl is unavailable for the test server', flush=True)
            try:
                for arch, client, threaded in clients:
                    for mode, path, expected in cases:
                        target = work / f'{arch}-файл-🌐.bin'
                        if mode in ('download', 'download_size'):
                            target.write_bytes(b'old-file')
                        result = subprocess.run([str(client), mode, root + path, str(target)], cwd=work,
                                                env=env, capture_output=True, text=True, encoding='utf-8', timeout=15)
                        if marker.exists() or result.returncode or result.stdout.strip() != expected:
                            raise RuntimeError(f'{arch} {mode} {path}: rc={result.returncode}, '
                                               f'out={result.stdout!r}, err={result.stderr!r}, '
                                               f'external curl={marker.exists()}')
                        if mode in ('download', 'download_size') and target.read_bytes() != (BINARY if mode == 'download' else LARGE):
                            raise RuntimeError(f'{arch}: downloaded bytes differ')
                        print(f'{arch}: {mode} {path} passed', flush=True)
                    for broken in ('/truncated', '/truncated-chunk', '/missing-final-chunk'):
                        target = work / f'{arch}-truncated-download'
                        target.write_bytes(b'preserve-this-file')
                        result = subprocess.run([str(client), 'download_invalid', root + broken, str(target)],
                                                cwd=work, env=env, capture_output=True, text=True,
                                                encoding='utf-8', timeout=15)
                        if (marker.exists() or result.returncode or result.stdout.strip() != 'rejected'
                                or target.read_bytes() != b'preserve-this-file'
                                or list(work.glob('.bit-copy-*'))):
                            raise RuntimeError(f'{arch} {broken}: failed download did not preserve the '
                                               f'target or remove the temporary: {result.stdout!r}, {result.stderr!r}')
                        print(f'{arch}: {broken} download preserved the target', flush=True)
                    if threaded:
                        result = subprocess.run([str(threaded), root], cwd=work, env=env,
                                                capture_output=True, text=True, encoding='utf-8', timeout=30)
                        if marker.exists() or result.returncode or result.stdout.strip() != '10 10 10 10':
                            raise RuntimeError(f'{arch}: concurrent HTTP failed: {result.stdout!r}, {result.stderr!r}')
                        print(f'{arch}: concurrent HTTP passed', flush=True)
                    if not args.allow_external:
                        credential_url = f'http://bit-user:bit-secret@127.0.0.1:{server.server_port}/plain'
                        result = subprocess.run([str(client), 'fetch_error', credential_url], cwd=work, env=env,
                                                capture_output=True, text=True, encoding='utf-8', timeout=15)
                        if (marker.exists() or result.returncode or not result.stdout.strip()
                                or result.stdout.strip() == 'accepted'
                                or 'bit-secret' in result.stdout + result.stderr):
                            raise RuntimeError(f'{arch}: unsupported URL credentials were not safely rejected')
                        print(f'{arch}: URL credentials rejected without disclosure', flush=True)
                    class IPv6Server(ThreadingHTTPServer):
                        address_family = socket.AF_INET6
                    try:
                        server6 = IPv6Server(('::1', 0), Handler)
                    except OSError:
                        print(f'{arch}: IPv6 HTTP test skipped: loopback unavailable', flush=True)
                    else:
                        server6.daemon_threads = True
                        thread6 = threading.Thread(target=server6.serve_forever, daemon=True)
                        thread6.start()
                        try:
                            url6 = f'http://[::1]:{server6.server_port}/plain'
                            result = subprocess.run([str(client), 'fetch', url6], cwd=work, env=env,
                                                    capture_output=True, text=True, encoding='utf-8', timeout=15)
                            if marker.exists() or result.returncode or result.stdout.strip() != 'hello-bit':
                                raise RuntimeError(f'{arch}: IPv6 HTTP failed: {result.stdout!r}, {result.stderr!r}')
                            print(f'{arch}: IPv6 HTTP passed', flush=True)
                        finally:
                            server6.shutdown()
                            server6.server_close()
                            thread6.join()
                    if tls_server:
                        url = f'https://127.0.0.1:{tls_server.server_port}/plain'
                        for mode in ('tls_invalid', 'post_invalid', 'download_invalid'):
                            target = work / f'{arch}-protected'
                            target.write_bytes(b'preserve-this-file')
                            result = subprocess.run([str(client), mode, url, str(target)], cwd=work,
                                                    env=env, capture_output=True, text=True,
                                                    encoding='utf-8', timeout=15)
                            if marker.exists() or result.returncode or result.stdout.strip() != 'rejected':
                                raise RuntimeError(f'{arch} {mode}: self-signed TLS certificate was not '
                                                   f'rejected: {result.stdout!r}, {result.stderr!r}')
                            if mode == 'download_invalid' and target.read_bytes() != b'preserve-this-file':
                                raise RuntimeError(f'{arch}: failed TLS download modified the target')
                            print(f'{arch}: {mode} rejected self-signed certificate', flush=True)
            finally:
                if tls_server:
                    tls_server.shutdown()
                    tls_server.server_close()
                    tls_thread.join()
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == '__main__':
    main()
