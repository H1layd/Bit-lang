# bit

**English** · [Русский](README.ru.md)

**bit** is a systems programming language built around one idea:
**simple control over your computer, out of the box.**

Files and folders, processes, the network, memory and the terminal are part of the language
itself — no packages to install, no bindings to write, no setup. A program that walks a folder,
runs a tool and reports the result is a few plain lines:

```
host {
    dir logs = "logs";
    do(logs >> make);
    file report = logs >> file("report.txt");

    string who = "whoami" >> run;                 # a shell command
    mas cmd = ("git", "status", "--short");       # a program with its arguments, no shell
    string changes = cmd >> run;

    do(report >> write("user: {who}\n") >> append(changes));
    print("{os >> host}: {os >> cpus} cores, saved to {report >> name}");
}
```

The compiler is written in bit itself, builds from scratch (no C, no LLVM) and produces
machine code directly through the system `as` and `ld`.

---

## Philosophy

1. **Control over the system, out of the box.** System work is built in and reads as plain words:
   `f >> read`, `d >> list`, `"example.com" >> ping`, `cmd >> run`, `mem >> take(16)`,
   `os >> procs`. One program builds for macOS, Linux and Windows.
2. **You can see what changes the world.** A *value* is just computed; an *action* (writing a file,
   sending data, assigning a variable) is wrapped in `do(...)`, and assignment is `ch` (change).
   Reading top to bottom, you always know where state changes.
3. **Failures are yours to handle.** A failed system call stops the program by default, but inside
   `recover { } else { }` the program decides itself: skip, retry, log, choose an exit code.
4. **The compiler checks what it can prove.** It rejects invalid types, uninitialized reads and
   indexes it cannot prove in range. Array access also checks the current length. With `bytes`,
   the program controls the lifetime of the allocation.
5. **Names you don't have to guess.** `shift_left`, not `shl`; `host { }`, not `fn main() {}`.
   bit keeps its own small vocabulary (`do`, `ch`, `>>`, `keep`, `each`) instead of borrowing
   C, C++ or Rust conventions.
6. **The whole toolchain is its own.** `bitc.bit` compiles itself and emits ARM64 or x86-64 assembly.

---

## Build the compiler

You need the system `as` and `ld` (Command Line Tools on macOS, binutils on Linux).

```bash
./bootstrap.sh
```

This builds `./bitc` from the assembly seeds in `bootstrap/` and checks that the compiler
reproduces itself.

## Build and run a program

```bash
./bitc run hello.bit              # build to a temporary file and run it
./bitc build hello.bit -o hello   # build an executable
./bitc asm hello.bit              # print the assembly
./bitc run prog.bit -- arg1 arg2  # pass arguments to the program
```

Other targets:

```bash
./bitc build hello.bit -o hello.exe --os windows    # needs x86_64-w64-mingw32-gcc
./bitc build hello.bit -o hello --os linux          # assemble on a Linux machine
./bitc build hello.bit -o hello --arch x86_64       # x86-64 on an ARM Mac (runs via Rosetta)
```

---

## A quick tour

```
host {
    num x = 152;                    # whole number
    dec p = 1.5;                    # fractional number
    string s = "Hello";             # text, " or '
    bool ok = true;

    do(x >> ch(x + 1));             # assignment is an action

    mas a = (5, 3, 9, 1, 7);
    print("over 4: {a >> keep(it > 4)}");      # (5, 9, 7)
    print("doubled: {a >> each(it * 2)}");     # (10, 6, 18, 2, 14)
    print("sum: {a >> sum}, has 9: {a >> has(9)}");

    for i in 0:4 {                             # 0..4 inclusive
        print("a[{i}] = {a >> get(i)}");       # in range, proven by the compiler
    }

    file f = "notes.txt";
    recover {
        print(f >> read);
    } else {
        print("could not read: {term >> error}");
    }
}
```

More programs live in [`examples/`](examples/): files, memory, network, system.

---

## Documentation

- **[Language reference](docs/language.md)**: syntax, types, every method by type, failures,
  running programs, compiler checks, how the compiler works.
- **[Roadmap and principles](docs/roadmap.md)**: what is done and what comes next.

## Status

bit supports system utilities, text processing, records, maps, function values and multi-file
programs through `use`. Working directory and environment changes are built into `term` and
inherited by launched programs. File operations include `read_only`, POSIX permissions, recursive
directory removal, and walks with `FileInfo` metadata. TCP connects can be bounded in time
(`connect(ms)`), and the kind of a caught failure is a stable code through `term >> error_code`.
A network service can listen on a specific IPv4 address, inspect the remote endpoint with
`peer`, and measure intervals with `os >> clock`.
The targets are macOS (arm64 and x86-64),
Linux (x86-64) and Windows (x86-64).
Compiler and runtime messages are currently in Russian.

---

## Repository layout

| Path | What it is |
|---|---|
| `bitc.bit` | the compiler, written in bit (lexer, parser, type checks and proofs, code generation) |
| `rt/` | runtime in assembly: `arm64.s`, `x86_64.s`, plus generated Linux and Windows versions |
| `tools/` | `embed_rt.bit` (embeds the runtime into the compiler), runtime generators for Linux and Windows, `build_opt.sh` (experimental optimizing build into `build/`) |
| `bootstrap/`, `bootstrap.sh` | assembly seeds and the from-scratch build with a self-hosting check |
| `tests.sh`, `tests/` | test suite (examples and error checks) on arm64 and x86-64; `tests_win.sh host` runs it on a real Windows machine over SSH |
| `examples/` | example programs |
| `docs/` | documentation in English (`*.md`) and Russian (`*.ru.md`) |
