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
- [x] **Text and numbers for real programs**: `find`, `contains`, `upper`, `lower`, `code`,
  `char`, `pad`, `pad_left`, `repeat`; `hex` with a width and `fixed` for decimals;
  padding also works on numbers. Integer division into a `dec` is a build error.
- [x] **Sorting by a field**: `a >> sort(it >> f)` and `sort(it >> f, "down")` order records
  and any values by a `num` or `string` key.
- [x] **Walking a map**: `m >> keys`, `m >> values` and `for k in m` in the order entries
  were added.
- [x] **No limit on parameters**: arguments beyond the register count travel on the stack,
  so functions take as many parameters as they need.
- [x] **`pick`**: a choice by value without fall-through — `pick x { 1 { } 2, 4 { } else { } }`.
- [x] **Threads**: `thread name { ... }` starts a second flow on its own stack and
  `do(name >> wait)` joins it. Threads see globals.
- [x] **Locks**: `lock guard;`, `do(guard >> enter)` and `do(guard >> leave)` protect shared data.
- [x] **Immediate keyboard**: `do(term >> raw(true))` stops waiting for Enter and echoing, and
  `term >> key` returns one UTF-8 character, so interactive programs are possible.

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
- [x] HOME/USERPROFILE ancestor protection passed on live Windows and was committed
  (`95be464`). The former Linux server was deleted; QEMU has intermittent emulator
  crashes, so native Linux remains a separate check.
- [x] **`d >> walk`** — every file inside a folder, nested folders included, without following links
  to folders; **`f >> modified`** — last change time.
- [x] **`connect(ms)`** — a TCP connect with a bound wait: a nonblocking socket,
  `poll`, and `SO_ERROR` on macOS/Linux; a socket timeout on Windows.
  **`term >> error_code`** — a stable numeric code of the last caught failure
  (1 refused, 2 wait ended, 3 no route, 0 no code) on macOS, Linux and Windows;
  a plain `connect` and a timed-out `recv` also fill it.

### Service capabilities and signals

- [x] `net >> listen(port, "address")`, `c >> peer`, `SO_REUSEADDR`, and `os >> clock`.
  Checked on both macOS architectures (217/217), Windows (54/54 plus 53 expected
  compile errors), and Linux under QEMU (109/109 plus the new error-line check).
  Fixed Linux `SO_ERROR` in `connect(ms)`, macOS `O_NONBLOCK`, its `fcntl` argument,
  and the error line. Address and port parsing is bounded. An end-to-end timeout test
  against a guaranteed nonresponding host remains outstanding.
- [ ] After the network milestone, audit stack alignment of the remaining handwritten
  Windows wrappers, as agreed with the author.
- [ ] Signals through `term >> signalled`: test with a separate child bit program
  receiving a signal or console event from an external process.

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

**Author-requested checkpoint:** continue work up to the package manager.
Before implementing the package manager, stop, report progress, and wait for the author.
Do not start the package manager or subsequent milestones until instructed.

**Current work:** after the service-network milestone, complete the agreed Windows-wrapper
audit and signals. Continue the unfinished memory work:
strings first, followed by `mas`, `map`, and records. The items below are directions,
not a commitment to a strictly sequential order; the package-manager checkpoint still
applies. The author chooses the license and new language decisions.

1. ~~**Finish the current work.**~~ HOME/USERPROFILE ancestor protection passed on
   Windows, macOS, and Linux under QEMU and was committed. Native Linux remains a
   separate portability check.
2. **Open the project to people.** A `LICENSE` file (the author picks the license; without one
   nobody may legally use the code). GitHub Actions: build, self-hosting and tests on macOS, Linux
   and Windows on every commit, with a badge in the README. A run on a real Linux machine.
   Compiler and runtime messages in English by default, Russian as an option, like the docs.
3. **Memory and long-running programs.** Define ownership for strings, arrays, maps,
   and records, returned values, and shared assignments. Reclaim objects without leaks
   or premature frees; keep explicit management of `bytes`.
   Author decision: ordinary, non-atomic reference counts. Implement `string` first,
   followed by `mas`, `map`, and records. After each stage compare self-build time and
   peak `mem >> used`; show any significant slowdown before proceeding further.
   Shared-data cycles are not reclaimed automatically. See the [memory plan](memory.md).
4. **Consistent language rules.** Complete the design milestone above: declarations,
   names, values and actions, `do`, `>>`, copying, and shared mutations. Remove ordinary
   programming limits, including six parameters and mutual-recursion inference.
   Syntax and new names are decisions for the language author.
5. **Features for any program.** Concurrency (threads or async — the author decides), so a
   server serves several clients and a monitor watches several things. Enums and "a value or
   nothing" (optional). Raw terminal input without Enter — for interfaces such as an editor.
   Talking to a running process while it works (write its stdin, read its stdout). Built-in HTTP
   and TLS without an external `curl`. Unsigned numbers if data formats need them. Every new name
   and syntax is agreed with the author.
6. **Libraries and convenient package installation.** Extend `use` with module namespaces
   and explicit public interfaces. Add project and dependency metadata, library versions,
   a lockfile, a local cache, and installation with one command.
   Details and the acceptance criterion are below.
7. **A stable release.** Automated macOS, Linux, and Windows checks, self-hosting,
   long-running memory tests, and clear diagnostics. Compiler binaries, simple installation,
   versions and compatibility rules, plus project checking and formatting commands.
   A "bit in an hour" tutorial, an examples gallery, an online playground if possible.
   Debug information (DWARF) so a debugger shows bit lines.
8. **A dedicated IDE for bit.** A project editor with builds, execution, diagnostics,
   navigation, and completion, followed by debugging. Write the tooling core in bit
   and exercise the language with a real application. Details and acceptance criteria follow.
9. **Recognition on GitHub.** GitHub detects languages with the Linguist library; a language is
   added by pull request, and only once it is already used widely. The requirements as stated in
   the Linguist contribution guide: at least 2000 files per extension indexed by GitHub Search
   in the last year, forks excluded, spread over different repositories — and the primary
   author's own repositories are subtracted from that count (`-user:`). Linguist says outright
   that pull requests for very new or hobby languages are closed. Also required: a TextMate
   grammar under one of the approved free licenses, added with `script/add-grammar` as a
   submodule, at least two samples with the license stated, and a link to the GitHub search
   results in the pull request. `.bit` is not taken in `languages.yml`, so no other format has
   to be told apart. Path: real users and projects → grammar for editors → PR to Linguist,
   in that order; the count grows from other people's code, not from the author's own repos.
10. **BitOS — a working name for the flagship project.** Build a system environment in bit
    and develop it into an experimental OS with a kernel, processes, and a filesystem.
    Use the project to exercise the language, extract reusable libraries, and install them
    through the package manager.

### Libraries and packages

Author-approved package handoff decisions: one command, `bit`, with `bitc` retained as
an alias; the registry is **nibble**. Initially it is a GitHub index repository without
a dedicated server; packages are published through pull requests to the index.
The intended workflow is `bit add json`, making the dependency available without manual
configuration. These details do not override the checkpoint before package-manager work.

- [ ] First agree on namespaces, public and internal declarations, libraries without
  `host`, and access to library functions. Current `use` merges file namespaces.
  Present examples to the author, then implement modules and their tests.
- [ ] Agree on package imports (proposal: `use json;` alongside `use "path.bit";`),
  the library entry point (proposal: `lib.bit`), and project filenames and formats.
- [ ] Proposals requiring agreement: `bit.deps` with “name version” lines (`1.2` selects
  the latest `1.2.x`); `bit.lock` with exact versions, HTTPS sources, and full commit SHAs;
  `index/<name>` entries containing “version git-url full-SHA”. Defer more complex version
  ranges. Define transitive dependency resolution and conflict diagnostics before
  implementing the format.
- [ ] After the checkpoint and the author's instruction: a package module written in bit,
  linked into the compiler; a unified `bit` command preserving `bitc` compatibility.
  Proposed subcommands: `add`, `remove`, `update`, `search`, `publish`; `build` / `run`
  automatically fetch missing dependencies recorded in the lockfile.
- [ ] A local offline test index: adding packages, locking, rebuilding from cache,
  mismatched SHAs, invalid names, and missing `git`. Then system-git downloads, caching,
  and checks on macOS, Windows, and Linux. Pass git arguments as an array, without a shell.
- [ ] HTTPS only; no installation scripts. Package names contain 1–64 characters from
  `a-z`, `0-9`, `-`, with no paths. Verify full downloaded commit SHAs and report the index
  revision used. A mismatch produces a clear error and stops the build.
- [ ] An immutable cache at `~/.bit/nibble/<name>/<version>-<commit>/`
  (Windows: `%USERPROFILE%\.bit\nibble\...`); offline builds when every verified locked
  dependency is cached. Agree on the cache location before implementing it.
- [ ] `update`, `remove`, `search`; `publish` checks the build, entry point, and version tag,
  then prepares an index entry and PR text. The package author submits the PR.
- [ ] Prepare the index structure, publication rules, and an example package; the author
  creates the GitHub repository. Update the reference, README, and roadmap in both languages.
- [ ] First standard nibble packages: `json`, date and time (formatting, parsing, time zones),
  search patterns or regular expressions, hashes and encodings (sha256, base64, hex),
  cryptographically secure random bytes.
- [ ] Standard libraries in bit: data handling, configuration, file formats, and algorithms.
  A dedicated registry server, mirror, search, and website in bit are a later milestone.
- [ ] Acceptance criterion: a new project installs a library with one command, imports its
  public interface, and builds on another machine using the same lockfile; cached rebuilds
  work offline. Record missing language features and discuss them with the author instead
  of replacing them with external implementations.

### A dedicated IDE for bit

A separate product before the OS milestone. Agree on its name, interface, and graphics
implementation with the author before development. An existing editor extension can
validate tooling along the way, but the deliverable is a dedicated IDE. Write the tooling
core in bit; plan missing UI and system facilities as language work without FFI.

1. **Prepare the compiler.** Machine-readable diagnostics with files and positions,
   symbol and type information, and resilient parsing of incomplete code. Extract shared
   compiler modules so the editor can reuse them.
2. **Editor and projects.** Open folders, browse a file tree, edit tabs, search and replace,
   save files, restore unsaved text, and configure projects. Check Russian text, Unicode,
   keyboard navigation, and large source files.
3. **Everyday development.** Build and run through `bit`, view output, stop programs,
   jump from diagnostics to source, format code, and inspect nibble dependencies.
4. **Code understanding.** Go to definition, find references, inspect types, complete code,
   and rename symbols respecting scope. Refresh information during editing without a full
   compiler self-build on each keystroke.
5. **Debugging.** First add debug information and the required compiler support, then
   breakpoints, stepping, call stacks, and value inspection. Select platform facilities
   and a debugger protocol separately; launching a program alone does not complete debugging.
6. **Acceptance criterion.** On macOS, Windows, and Linux, open the compiler source,
   edit it, build and run the result, follow diagnostics, and debug a small program.
   Reproduce IDE builds from its own source.

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
- **Unicode locales, BSD / wasm, `const`, tuples** — growth in width and comfort; we come back
  when there is a concrete need or real users. Threads, unsigned numbers, dates and time moved
  into the plan above.
