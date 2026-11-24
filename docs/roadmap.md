# bit roadmap and principles

**English** · [Русский](roadmap.ru.md)

A living document: where the language is going and by which rules. Updated as work goes on.

## Principles (above any feature)

1. **Simple control over the system, out of the box.** Files, folders, processes, network, memory
   and the terminal are part of the language, not a library to install. A new feature is worth
   adding when it gives a program more control over its computer with less code.
2. **Names you can guess the first time.** No assembler or C abbreviations; plain words in the spirit
   of `keep` / `each` / `has` / `sort`. Example: bit operations are `shift_left` / `shift_right` /
   `bit_and` / `bit_or` / `bit_xor` / `bit_not`, not `shl` / `shr` / `band`.
3. **Its own look.** bit has recognizable constructs, including `>>` chains and the `host` entry
   point. Keep or change each form based on how easily a reader can understand the code.
4. **Effects are visible in code.** Readers should be able to tell which operations change state.
   Assignment keeps the form `do(x >> ch(value));`.
5. **What can be proven is proven at build time:** types, empty variables, index ranges. Array length
   is also checked at run time, because another name can change the array. No new feature may weaken
   this.

## Simplify the whole language first

The first design milestone revisits the basic rules of bit. A small set of consistent rules should
be enough to learn the resulting language. Records, dictionaries, functions as values and modules
already exist; the agreed rules will apply to them as well.

- [ ] **Command names.** Find abbreviations and names whose meaning is hard to guess.
  Start with methods and agree on each new name using examples of how it is called.
- [ ] **Declarations.** Compare explicit and inferred types, uninitialized declarations and
  array creation forms.
- [x] **Blocks.** Keep `host { ... }`. Functions, conditions, loops and error handlers
  support a colon and indentation.
- [ ] **Expressions and actions.** Set one rule for `do`, `>>` and function calls. Some current
  chains can mutate data inside an expression.
- [ ] **Data operations.** Look for shared rules for indexing, slices, fallbacks, type conversions
  and sharing on assignment.
- [ ] **System operations and failures.** Compare files, sockets and processes. Identify which
  differences in passing data, getting results and handling errors can be removed.
- [ ] **Evaluate the result.** Compare before and after on a counter, array processing, copying a
  file and running a process. Count required constructs and rules the reader must remember. Agree
  on what to merge, make optional or remove. For accepted breaking changes, document migration
  and update self-hosting, examples and tests.

### Name readability

- [x] entry point: `fn main() {}` → `host { }`
- [x] bit operations: `shl…` → `shift_left` / `bit_and` / …
- [ ] `dec` — not obvious that it is a fractional number (rename candidate)
- [ ] `mas`, `conn`, `proc` — check that they read without guessing
- [x] `ch` stays in the assignment form `do(x >> ch(value));`

## Small additions — cheap, do not touch self-hosting

- [x] **Bit operations** as `>>` methods.
- [x] **`break` / `next`** (`next` instead of `continue`: shorter, in the style of the language).
- [x] **Array operations**: `insert(i, v)` / `remove(i)` / `pop`, `first` / `last` with an optional
  fallback.
- [x] **Strings**: `split`, `trim`, `replace`, `starts`, `ends`.
- [x] **Math**: `sqrt`, `pow` (whole power), `abs`, `min` / `max`.
- [x] **`random`**: inclusive integer ranges. The seed is a hash of a word generated from OS entropy or set with `seed(word)`.
- [x] **Typed `bytes`**: read and write `u16`, `u32`, `i64`, `f32` and `f64` with explicit byte order.
- [x] **String escapes**: `\r` and escaped whitespace inside interpolated string expressions.

## Control over the system

Goal: the program itself decides how system operations end, how much data to take and how long to
wait.

- [x] **Failures** — `recover { } else { }`: a failed operation goes to `else`, the program goes on;
  `term >> error` gives the error text, `term >> exit(code)` picks the exit code.
- [x] **Running programs directly** — `mas >> run`, `mas >> run("input")`, `term >> stderr`,
  `term >> status`, `do(cmd >> run)`. Both stdout and
  stderr are read concurrently. The updated Windows capture still needs a native stress test.
- [x] **`file >> move`**.
- [x] **Copy files** through a destination-directory temporary file and handle same-path operations.
- [x] **Check current bounds**, strictly parse `string >> num` and unwind `recover` on control flow.
- [ ] Reclaim strings that may escape their scope.
- [x] **Streaming**: bounded file reads and offset writes; text `recv` with a size and a timeout.
- [ ] Verify streaming on native Linux and Windows.
- [x] **Sorting**: `a >> sort` returns a copy; `do(a >> sort)` sorts in place.
- [x] **`proc` on Windows** through the system API (`OpenProcess`, `ReadProcessMemory`,
  `WriteProcessMemory`, `VirtualQueryEx`), checked on native Windows 11. The same program works on Linux.
- [x] **Native Windows run**: `tests_win.sh` checks 39 runtime tests and 53 expected compiler errors
  on Windows 11. File tests use bit itself; commands, processes, and large stdin/stderr have
  Windows variants. Only the root-directory write-denial test is skipped because it depends
  on the OS and permissions. Unexpected build failures now fail the suite. Fixed Windows exit
  codes being decoded as POSIX wait statuses. Previously fixed: files written in text mode (`\n` became `\r\n`),
  non-ASCII paths, commands and arguments broken by the ANSI code page, transliterated runtime
  messages. Windows programs are now UTF-8 throughout.
- [ ] Run the updated runtimes on native Linux.
- [x] Linux in Colima: Debian, x86-64 under QEMU, unprivileged user;
  95/95 and self-hosting passed, including `remove_all` protection for HOME and its ancestors.
- [ ] Repeat the Windows HOME/USERPROFILE ancestor-protection run when SSH is available.
- [x] **`d >> walk`** — every file inside a folder, nested folders included, without following links
  to folders; **`f >> modified`** — last change time.

## System capability milestones

Status of the milestones already started. Each change ends with checks and documentation updates.

1. **Native test runs.** Done for Windows (`tests_win.sh`), including variants of tests that need
   POSIX tools on macOS/Linux. Next: a native Linux run when the VPS is available again.
2. ~~**Processes on macOS.**~~ Done: `start`, `pid`, `name`, `alive`, `wait`, `kill` and
   `"name" >> proc` work on macOS (libproc, `sysctl` for system processes); memory access is a clear
   build error there. Along the way: `kill` on a missing process (pid `-1`) on Linux would have
   signalled every process of the user — now it is a failure.
3. ~~**Working folder and environment.**~~ Done: `term >> folder`, `do(term >> go(path))`
   (`string` or `dir`), and `do(term >> env("K", "V"))`. New `run` and `start` calls inherit
   the directory and environment. Windows updates both the process environment and CRT copy.
   Tests cover saved `env` values, Unicode, spaces, invalid names, and failed directory changes.
4. ~~**File system to the end.**~~ Done: `read_only` on all three OSes; `permissions` on
   macOS/Linux with strict nine-character strings and build-time literal validation.
   `do(d >> remove_all)` removes trees without traversing link or junction targets.
   `d >> walk("info")` returns `FileInfo` records (`path`, `sz`, `modified`); ordinary files
   need no separate size/time requests. Record arrays are supported. Self-hosting converged;
   macOS: 187/187; Windows: 39 runtime checks and 53 expected compiler errors.

## Next — a stable language and a flagship project

1. **Finish the current work.** Run HOME/USERPROFILE ancestor protection on a real Windows
   machine, then commit the fixes. macOS and Linux in Colima have been checked;
   native Linux remains a separate portability check.
2. **Memory and long-running programs.** Define ownership for strings, arrays, maps,
   and records, returned values, and shared assignments. Reclaim objects without leaks
   or premature frees; keep explicit management of `bytes`.
3. **Consistent language rules.** Complete the design milestone above: declarations,
   names, values and actions, `do`, `>>`, copying, and shared mutations. Remove ordinary
   programming limits, including six parameters and mutual-recursion inference.
   Syntax and new names are decisions for the language author.
4. **Libraries and convenient package installation.** Extend `use` with module namespaces
   and explicit public interfaces. Add project and dependency metadata, library versions,
   a lockfile, a local cache, and installation with one command.
   Details and the acceptance criterion are below.
5. **A stable release.** Automated macOS, Linux, and Windows checks, self-hosting,
   long-running memory tests, and clear diagnostics. Compiler binaries, simple installation,
   versions and compatibility rules, plus project checking and formatting commands.
6. **BitOS — a working name for the flagship project.** Build a system environment in bit
   and develop it into an experimental OS with a kernel, processes, and a filesystem.
   Use the project to exercise the language, extract reusable libraries, and install them
   through the package manager.

### Libraries and packages

- [ ] Namespaces, public and internal declarations, and libraries without a `host` block.
- [ ] Standard libraries written in bit over the built-in system facilities: data handling,
  configuration, file formats, and common algorithms.
- [ ] A project manifest: name, version, entry point, dependencies, supported targets,
  and compatible compiler versions.
- [ ] One-command package installation, version selection, dependency updates and removal.
  Agree on command names and the manifest format before implementation.
- [ ] Local folders and Git sources pinned to revisions first; then a registry with search,
  descriptions, versions, and publishing of personal libraries.
- [ ] Transitive dependency resolution, clear conflict errors, and a lockfile recording exact
  versions, sources, and checksums.
- [ ] A shared download cache, offline rebuilds, and reproducible dependency resolution
  on a clean machine.
- [ ] Acceptance criterion: a new project installs a library, imports its public interface,
  and builds on another machine using the same lockfile.

### BitOS: from a system environment to an operating system

The working name can change. This is a long-term goal with independently testable
milestones; the first stable bit release does not require a finished OS.

1. **A Linux system environment.** A shell written in bit, service launching and supervision,
   an event log, and file, network, and package management. Run the environment in a virtual
   machine as a usable, integrated product.
2. **Prepare for a kernel.** A separate freestanding compilation target without libc or
   host OS dependencies, a boot entry, code and memory layout, a minimal runtime, hardware
   access, and interrupt handling. The current runtime depends on system APIs;
   this milestone requires compiler and platform-layer changes.
3. **Boot a kernel in QEMU, x86-64.** Booting, serial output, memory allocation, and a timer.
   The first result is a reproducibly built image that boots and executes kernel code
   written in bit.
4. **A minimal standalone OS.** Virtual memory and process isolation, scheduling, system
   calls, basic drivers, a filesystem, and a user shell. Install and run bit programs
   inside BitOS.
5. **Self-host inside BitOS.** Port the compiler and tools: obtain source and packages,
   build programs, and rebuild the compiler from within the OS.

Each milestone must deliver a runnable result and identify concrete language limitations
encountered during development. New language mechanisms and names require author agreement.


## Core language features

- [x] **Records** with typed fields and shared updates.
- [x] **Maps** with string keys, one value type and linear lookup.
- [x] **Function values** with concrete signatures and arrow functions.
- [x] **Multi-file programs** with relative `use` directives and a shared namespace.
- [x] **Optimizing build**: constant positive powers of two use bit operations for `%`.

## Not now — honestly

- **Windows ACLs** — a separate permissions model; the `read_only` attribute is available for now.
- **FFI (calling C)** — against the idea that the whole toolchain is its own. That would be another
  language.
- **Threads / async** — one connection at a time is enough for now.
- **Unicode locales, DWARF debug info, BSD / wasm, unsigned numbers, dates and time
  zones, `const`, tuples** — growth in width and comfort; we come back when there is a concrete need
  or real users.
