#!/usr/bin/env python3
"""Deliver signals from a separate process and verify opt-in and restarted reads."""
from pathlib import Path
import os
import platform
import signal
import socket
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parent.parent
if os.name != 'posix':
    raise SystemExit('this test requires POSIX signals')
arches = ['x86_64'] if platform.system() == 'Linux' else ['arm64', 'x86_64']
with tempfile.TemporaryDirectory(prefix='bit-signals-') as folder:
    work = Path(folder)
    for arch in arches:
        binaries = {}
        for name in ('signal_child', 'signal_generic', 'signal_default', 'signal_thread', 'signal_wait', 'signal_recv', 'signal_timeout'):
            source = root / 'tests/rt' / (name + '.bit')
            binary = work / (name + '_' + arch)
            subprocess.run([str(root / 'bitc'), 'build', str(source), '--arch', arch,
                            '-o', str(binary)], cwd=root, check=True, stdout=subprocess.DEVNULL)
            assembly = subprocess.check_output([str(root / 'bitc'), 'asm', str(source),
                                                '--arch', arch], cwd=root, text=True)
            entry = assembly.split('_bit_ginit:', 1)[0]
            if ('_bit_signal_init' in entry) != (name != 'signal_default'):
                raise SystemExit(f'{arch}: unexpected signal setup in {name}')
            binaries[name] = binary
        for signum in (signal.SIGINT, signal.SIGTERM):
            for name, opted_in in (('signal_child', True), ('signal_generic', True), ('signal_thread', True), ('signal_default', False)):
                ready = work / f'ready_{arch}_{signum}_{name}'
                process = subprocess.Popen([str(binaries[name]), str(ready)], cwd=work,
                                           stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                           stderr=subprocess.PIPE, text=True)
                try:
                    deadline = time.monotonic() + 10
                    while not ready.exists():
                        if process.poll() is not None:
                            out, err = process.communicate()
                            raise RuntimeError(f'{arch} {name}: exited early {process.returncode}: {out!r} {err!r}')
                        if time.monotonic() > deadline:
                            raise RuntimeError(f'{arch} {name}: readiness timeout')
                        time.sleep(0.01)
                    # Give the child time to enter its blocking read before the signal.
                    time.sleep(0.1)
                    process.send_signal(signum)
                    if opted_in:
                        time.sleep(0.1)
                        if name in ('signal_child', 'signal_generic') and process.poll() is not None:
                            out, err = process.communicate()
                            raise RuntimeError(f'{arch}: signal ended opt-in program: {process.returncode} {out!r} {err!r}')
                        out, err = process.communicate('x' if name in ('signal_child', 'signal_generic') else None, timeout=10)
                        expected = 'true x true' if name in ('signal_child', 'signal_generic') else 'true'
                        if process.returncode != 0 or out.strip() != expected:
                            raise RuntimeError(f'{arch}: failed restarted read: {process.returncode} {out!r} {err!r}')
                    else:
                        out, err = process.communicate(timeout=10)
                        if process.returncode != -signum:
                            raise RuntimeError(f'{arch}: default signal behavior changed: {process.returncode} {out!r} {err!r}')
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()
                print(f'{arch}: {signal.Signals(signum).name}, {name} passed', flush=True)

        for signum in (signal.SIGINT, signal.SIGTERM):
            for name in ('signal_wait', 'signal_recv'):
                ready = work / f'ready_{arch}_{signum}_{name}'
                listener = socket.socket() if name == 'signal_recv' else None
                connection = None
                try:
                    args = [str(binaries[name])]
                    if listener:
                        listener.bind(('127.0.0.1', 0))
                        listener.listen(1)
                        listener.settimeout(10)
                        args.append(f'127.0.0.1:{listener.getsockname()[1]}')
                    args.append(str(ready))
                    process = subprocess.Popen(args, cwd=work, stdout=subprocess.PIPE,
                                               stderr=subprocess.PIPE, text=True)
                    if listener:
                        connection, _ = listener.accept()
                    deadline = time.monotonic() + 10
                    while not ready.exists():
                        if process.poll() is not None or time.monotonic() > deadline:
                            raise RuntimeError(f'{arch} {name}: child not ready')
                        time.sleep(0.01)
                    time.sleep(0.1)
                    process.send_signal(signum)
                    if connection:
                        time.sleep(0.1)
                        connection.sendall(b'x')
                    out, err = process.communicate(timeout=10)
                    expected = 'true x' if connection else 'true\ntrue'
                    if process.returncode != 0 or out.strip() != expected:
                        raise RuntimeError(f'{arch} {name}: {process.returncode} {out!r} {err!r}')
                finally:
                    if 'process' in locals() and process.poll() is None:
                        process.kill()
                        process.wait()
                    if connection:
                        connection.close()
                    if listener:
                        listener.close()
                print(f'{arch}: {signal.Signals(signum).name}, {name} passed', flush=True)

        # Multiple interrupts must not reset the timeout from scratch.
        ready = work / f'ready_{arch}_timeout'
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            listener.listen(1)
            listener.settimeout(10)
            process = subprocess.Popen([str(binaries['signal_timeout']),
                                        f'127.0.0.1:{listener.getsockname()[1]}', str(ready)],
                                       cwd=work, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                connection, _ = listener.accept()
                with connection:
                    deadline = time.monotonic() + 10
                    while not ready.exists():
                        if process.poll() is not None or time.monotonic() > deadline:
                            raise RuntimeError(f'{arch} signal_timeout: child not ready')
                        time.sleep(0.01)
                    for _ in range(4):
                        time.sleep(0.2)
                        process.send_signal(signal.SIGINT)
                    out, err = process.communicate(timeout=10)
                    if process.returncode != 0 or out.strip() != 'true 2\ntrue\ntrue':
                        raise RuntimeError(f'{arch} signal_timeout: {process.returncode} {out!r} {err!r}')
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
        print(f'{arch}: interrupted timeout retains its deadline', flush=True)
