#!/usr/bin/env python3
"""Exercise generated Windows socket routines with pointer-sized fake sockets.

Runs their shared calling-convention code against mock Winsock wrappers on x86-64.
This does not replace testing against Winsock on Windows.
"""
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
NAMES = ('_bit_ip_connect', '_bit_tcp_listen_at', '_bit_tcp_accept',
         '_bit_sock_send', '_bit_sock_send_bytes', '_bit_sock_recv')

C_SOURCE = r'''
#include <assert.h>
#include <setjmp.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define ALIAS(name) __asm__("_" #name)
typedef uint64_t sock;
static const sock handle = UINT64_C(0x1234567880000042);
static int failing, allocated;
static jmp_buf rescue;
static long last_line;

sock w_socket(int a, int b, int c) ALIAS(w_socket);
sock w_socket(int a, int b, int c) { (void)a; (void)b; (void)c; return failing ? UINT64_MAX : handle; }
int w_inet_pton(int a, const char *b, void *c) ALIAS(w_inet_pton);
int w_inet_pton(int a, const char *b, void *c) { (void)a; (void)b; memset(c, 0, 4); return 1; }
int w_connect(sock s, const void *a, int n) ALIAS(w_connect);
int w_connect(sock s, const void *a, int n) { assert(s == handle); (void)a; (void)n; return 0; }
int w_setsockopt(sock s, int a, int b, const void *c, int n) ALIAS(w_setsockopt);
int w_setsockopt(sock s, int a, int b, const void *c, int n) { assert(s == handle); (void)a; (void)b; (void)c; (void)n; return 0; }
int w_bind(sock s, const void *a, int n) ALIAS(w_bind);
int w_bind(sock s, const void *a, int n) { assert(s == handle); (void)a; (void)n; return 0; }
int w_listen(sock s, int n) ALIAS(w_listen);
int w_listen(sock s, int n) { assert(s == handle); (void)n; return 0; }
sock w_accept(sock s, void *a, void *b) ALIAS(w_accept);
sock w_accept(sock s, void *a, void *b) { assert(s == handle); (void)a; (void)b; return failing ? UINT64_MAX : handle; }
int w_closesocket(sock s) ALIAS(w_closesocket);
int w_closesocket(sock s) { assert(s == handle); return 0; }
size_t w_strlen(const char *p) ALIAS(w_strlen);
size_t w_strlen(const char *p) { return strlen(p); }
int w_send(sock s, const void *p, int n, int flags) ALIAS(w_send);
int w_send(sock s, const void *p, int n, int flags) { assert(s == handle); (void)p; (void)flags; return failing == 1 ? -1 : (failing == 2 ? 0 : n); }
int wsa_error(void) __asm__("WSAGetLastError");
int wsa_error(void) { return 999; }
int w_recv(sock s, void *p, int n, int flags) ALIAS(w_recv);
int w_recv(sock s, void *p, int n, int flags) { assert(s == handle); assert(n > 0); (void)flags; if (failing) return -1; *(char *)p = 'x'; return 1; }
void *bit_alloc(size_t n) ALIAS(bit_alloc);
void *bit_alloc(size_t n) { ++allocated; return malloc(n); }
void w_free(void *p) ALIAS(w_free);
void w_free(void *p) { --allocated; free(p); }
void bit_set_errcode(long code) ALIAS(bit_set_errcode);
void bit_set_errcode(long code) { (void)code; }
long bit_errno_code(void) ALIAS(bit_errno_code);
long bit_errno_code(void) { return 0; }
void bit_die(const char *message, long line) ALIAS(bit_die);
void bit_die(const char *message, long line) { (void)message; last_line = line; longjmp(rescue, 1); }

sock bit_ip_connect(const char *, long, int) ALIAS(bit_ip_connect);
sock bit_tcp_listen_at(long, const char *, long) ALIAS(bit_tcp_listen_at);
sock bit_tcp_accept(sock, long) ALIAS(bit_tcp_accept);
void bit_sock_send(sock, const char *, long) ALIAS(bit_sock_send);
char *bit_sock_recv(sock, long) ALIAS(bit_sock_recv);

int main(void) {
    assert(bit_ip_connect("127.0.0.1:1234", 10, 1) == handle);
    assert(bit_tcp_listen_at(1234, "127.0.0.1", 11) == handle);
    assert(bit_tcp_accept(handle, 12) == handle);
    bit_sock_send(handle, "abc", 13);
    char *s = bit_sock_recv(handle, 14);
    assert(strcmp(s, "x") == 0); w_free(s); assert(allocated == 0);
    failing = 1;
    if (!setjmp(rescue)) { bit_sock_recv(handle, 55); abort(); }
    assert(last_line == 55 && allocated == 0);
    if (!setjmp(rescue)) { bit_sock_send(handle, "abc", 56); abort(); }
    assert(last_line == 56);
    failing = 2;
    if (!setjmp(rescue)) { bit_sock_send(handle, "abc", 60); abort(); }
    assert(last_line == 60);
    failing = 1;
    if (!setjmp(rescue)) { bit_tcp_accept(handle, 57); abort(); }
    assert(last_line == 57);
    if (!setjmp(rescue)) { bit_ip_connect("127.0.0.1:1234", 58, 1); abort(); }
    assert(last_line == 58);
    if (!setjmp(rescue)) { bit_tcp_listen_at(1234, "127.0.0.1", 59); abort(); }
    assert(last_line == 59);
    return 0;
}
'''


def main():
    system = platform.system()
    if system not in ('Darwin', 'Linux'):
        print('Windows socket mock test skipped: requires macOS or Linux')
        return
    if not shutil.which('cc'):
        print('Windows socket mock test skipped: requires a C compiler')
        return
    src = (ROOT / 'rt/x86_64-windows.s').read_text()
    functions = []
    for name in NAMES:
        match = re.search(r'^' + re.escape(name) + r':.*?(?=^_bit_[a-z_0-9]+:|\Z)',
                          src, re.MULTILINE | re.DOTALL)
        if not match:
            raise RuntimeError(f'missing {name}')
        functions.append(re.sub(r'//[^\n]*', '', match.group()))
    assembly = ('.intel_syntax noprefix\n.text\n' + ''.join('.globl ' + n + '\n' for n in NAMES)
                + '\n'.join(functions) + '\n.data\n'
                + ''.join(f'{name}: .asciz "error"\n' for name in
                          ('Lrt_enet', 'Lrt_elisten', 'Lrt_elisten_addr', 'Lrt_eaccept',
                           'Lrt_esend', 'Lrt_erecv')))
    with tempfile.TemporaryDirectory(prefix='bit-win-socket-mock-') as folder:
        work = Path(folder)
        (work / 'mock.c').write_text(C_SOURCE)
        (work / 'socket.s').write_text(assembly)
        flags = ['-arch', 'x86_64'] if system == 'Darwin' else []
        subprocess.run(['cc', *flags, str(work / 'mock.c'), str(work / 'socket.s'),
                        '-o', str(work / 'test')], check=True)
        subprocess.run([str(work / 'test')], check=True)
    print('Windows socket routines: 64-bit handles, failures, and receive cleanup passed (mock)')


if __name__ == '__main__':
    main()
