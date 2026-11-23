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
3. **Its own look, not C / C++ / Rust.** bit builds on its own vocabulary (`do` / `ch` / `>>` / `host`)
   instead of borrowing other conventions. Familiar syntax (braces, `;`) is not a problem in itself
   and is not broken just to look different.
4. **Everything visible and in order.** Actions (that change the world) go through `do` and `ch`;
   values are simply computed. No hidden effects.
5. **Safety is proven at build time,** not checked at run time. No new feature may break this.

## Name readability pass

- [x] entry point: `fn main() {}` → `host { }`
- [x] bit operations: `shl…` → `shift_left` / `bit_and` / …
- [ ] `dec` — not obvious that it is a fractional number (rename candidate)
- [ ] `mas`, `conn`, `proc` — check that they read without guessing
- [ ] `ch` — short, but not obvious to everyone that it means "change"

## Small additions — cheap, do not touch self-hosting

- [x] **Bit operations** as `>>` methods.
- [x] **`break` / `next`** (`next` instead of `continue`: shorter, in the style of the language).
- [x] **Array operations**: `insert(i, v)` / `remove(i)` / `pop`, `first` / `last` with an optional
  fallback.
- [x] **Strings**: `split`, `trim`, `replace`, `starts`, `ends`.
- [x] **Math**: `sqrt`, `pow` (whole power), `abs`, `min` / `max`.
- [ ] **`rand`** — needs a choice of generator and seed (fixed seed / time / `/dev/urandom`).
- [ ] **Typed `bytes`**: read `u16` / `u32` / `float` at an offset, byte order.
- [ ] **Parser details**: no `\r` escape; a string with `\n` inside `{...}` of another string does not
  parse (workaround: use a variable).

## Control over the system

Goal: the program itself decides how system operations end, how much data to take and how long to
wait.

- [x] **Failures** — `recover { } else { }`: a failed operation goes to `else`, the program goes on;
  `term >> error` gives the error text, `term >> exit(code)` picks the exit code.
- [x] **Running programs directly** — `mas >> run`, `mas >> run("input")`, `term >> stderr`,
  `term >> status`, `do(cmd >> run)`. Arguments arrive exactly as written on every OS; stdout and
  stderr never block each other on macOS and Linux.
- [x] **`file >> move`**.
- [ ] **Streaming**: read a file in chunks and at an offset; `recv` with a chunk size and a timeout,
  assembling a message from several reads.
- [ ] **`a >> sort` changes the array inside an expression** — decide: change only through
  `do(a >> sort)`, or return a copy in an expression.
- [ ] Run the Linux runtime on real hardware again after the latest changes (macOS and Windows 11
  are checked).

## Larger work — order matters

Touches the parser, types, code generation and memory; must survive self-hosting.

1. **Structs (records)** — the main gap: today everything is modelled with parallel arrays.
2. **map (dictionary)** — almost free once structs exist.
3. **Memory and sharing rules** — the current model is written in the reference (strings are freed
   automatically, `bytes` explicitly with `free`, `mas` is shared on assignment). Structs and maps
   must follow the same rules.
4. **Functions as values** — `x -> x * 2`; the arrow `->` is reserved for this.
5. **Modules** — for the compiler's own sake (17k+ lines in one file).
6. **Optimizer** — an experimental optimizing build already exists (`tools/build_opt.sh`).

## Not now — honestly

- **FFI (calling C)** — against the idea that the whole toolchain is its own. That would be another
  language.
- **Threads / async** — one connection at a time is enough for now.
- **Unicode locales, DWARF debug info, a package manager, BSD / wasm, unsigned numbers, dates and time
  zones, `const`, tuples** — growth in width and comfort; we come back when there is a concrete need
  or real users.
