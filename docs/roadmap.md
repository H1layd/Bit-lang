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
- [x] **Native Windows run**: `tests_win.sh` passes the whole suite on Windows 11 (29 tests; 6 tests
  that need POSIX tools are skipped). Found and fixed: files written in text mode (`\n` became `\r\n`),
  non-ASCII paths, commands and arguments broken by the ANSI code page, transliterated runtime
  messages. Windows programs are now UTF-8 throughout.
- [ ] Run the updated runtimes on native Linux.
- [x] **`d >> walk`** — every file inside a folder, nested folders included, without following links
  to folders; **`f >> modified`** — last change time.

## Next — the plan

In order. Each step ends with tests, updated seeds and both references.

1. **Native test runs.** Done for Windows (`tests_win.sh`). Next: the same for Linux, and Windows
   versions of the tests that now need POSIX tools.
2. ~~**Processes on macOS.**~~ Done: `start`, `pid`, `name`, `alive`, `wait`, `kill` and
   `"name" >> proc` work on macOS (libproc, `sysctl` for system processes); memory access is a clear
   build error there. Along the way: `kill` on a missing process (pid `-1`) on Linux would have
   signalled every process of the user — now it is a failure.
3. **Working folder and environment.** Read and change the current folder; set environment
   variables for programs started by `run` and `start`.
4. **File system to the end.** Permissions (read, change), folder removal with its contents as an
   explicit, visible action, file size and time in `walk` results without a second system call.
5. **Reclaim strings that may escape their scope** — long-running programs should not grow.
6. **The language design milestone** above: names, declarations, one rule for `do` and `>>`. These
   are decisions for the language's author; the code follows them.

## Core language features

- [x] **Records** with typed fields and shared updates.
- [x] **Maps** with string keys, one value type and linear lookup.
- [x] **Function values** with concrete signatures and arrow functions.
- [x] **Multi-file programs** with relative `use` directives and a shared namespace.
- [x] **Optimizing build**: constant positive powers of two use bit operations for `%`.

## Not now — honestly

- **FFI (calling C)** — against the idea that the whole toolchain is its own. That would be another
  language.
- **Threads / async** — one connection at a time is enough for now.
- **Unicode locales, DWARF debug info, a package manager, BSD / wasm, unsigned numbers, dates and time
  zones, `const`, tuples** — growth in width and comfort; we come back when there is a concrete need
  or real users.
