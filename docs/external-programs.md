# External programs: bit audit

Status: 27 November 2026. The goal is that bit programs and the compiler do
not implicitly start external utilities. A program may still explicitly start
one through `run` or `start`. OS APIs and libraries are a separate dependency,
not external utility processes.

| Area | Current behavior | Remaining work |
|---|---|---|
| `fetch`, `post`, `download` on macOS/Linux | Launch `curl` | Finish a native HTTP transport with certificate-verified TLS, redirects and safe downloads. Windows uses WinHTTP without `curl`. |
| `os >> procs` | Runs `ps` through a shell on macOS/Linux, `tasklist` through a shell on Windows | Use operating-system interfaces and preserve the result format. |
| `os >> cpus` | No utility: `sysconf` on macOS/Linux, `GetSystemInfo` on Windows | Keep the regression test for absence of `getconf`. |
| `bitc asm` | A shell and `uname` detect the platform; a shell executes `pwd` for relative paths | Obtain the platform and working directory through OS interfaces. |
| `bitc build` and `bitc run` | The above, plus a shell, `mktemp`, `as`, `ld`, `rm`, and on macOS `xcrun`; cross-compiling for Windows invokes `x86_64-w64-mingw32-gcc` | Replace helper commands with OS APIs, then implement native object and executable generation to remove the assembler and linker. |
| `bootstrap.sh` | Shell, `uname`, `mkdir`, `as`, `ld`, `xcrun` on macOS, then compiler and `cmp` | Provide a self-contained initial installation path; the current script requires development tools. |

`bitc run` intentionally starts the compiled program selected by the user.
Similarly, `string >> run`, `mas >> run`, and `start` start programs explicitly
requested by bit code. String commands use a shell; argument arrays start a
program directly. Runtime generators, Python tests and developer build scripts
are not automatically executed by a finished bit program.

The audit inspected process-launch calls in the compiler and all four runtime
variants, and ran probes using substitute utilities. On both macOS architectures
and Linux under QEMU, the old `os >> cpus` returned the fake value `12345`, and
`os >> procs` returned fake `ps` output. On real Windows, `os >> procs` ran a
fake `tasklist`. After the fix, `os >> cpus` is checked against the system count
with a `getconf` trap.

Inspect actual calls rather than just assembly string constants: some unused
command names remain in the runtime. For example, Windows HTTP does not call
`curl`.
