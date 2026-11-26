# bit language reference

**English** · [Русский](language.ru.md)

The complete description of the language: philosophy, syntax, types, every method by type,
failures, running programs, compiler checks and building for other platforms.
For a short overview see the [README](../README.md).

> Compiler and runtime messages are currently in Russian.

## Contents

- [Philosophy: do and ch](#philosophy-do-and-ch)
- [Syntax basics](#syntax-basics)
- [Types](#types)
- [Declaring variables](#declaring-variables)
- [Chains and it](#chains-and-it)
- [Operators](#operators)
- [Control flow](#control-flow)
- [Functions](#functions)
- [Failures: recover and else](#failures-recover-and-else)
- [Methods by type](#methods-by-type)
  - [num and dec](#num-and-dec)
  - [string](#string)
  - [mas (array)](#mas-array)
  - [file](#file)
  - [dir (folder)](#dir-folder)
  - [bytes (raw memory)](#bytes-raw-memory)
  - [mem (computer memory)](#mem-computer-memory)
  - [os (system)](#os-system)
  - [term (terminal)](#term-terminal)
  - [Running programs](#running-programs)
  - [Network](#network)
  - [proc: other processes](#proc-other-processes)
- [Compiler checks](#compiler-checks)
- [Building for other platforms](#building-for-other-platforms)
- [How the compiler works](#how-the-compiler-works)

---

## Philosophy: do and ch

bit is about **simple control over your computer, out of the box**, and about seeing what a program
does. There are no hidden overloads, implicit conversions or concealed effects, so the language
separates two things:

- a **value** is something computed: `2 + 2`, `a >> get(0)`, `mem >> free`;
- an **action** changes the world: writing a file, sending data, **assigning a variable**.

Every action is wrapped in `do(...)`, and assignment itself is written `ch` (change):

```
num x = 10;
do(x >> ch(x + 1));     # x is now 11
```

So the code always shows where something is merely computed and where state changes. `do` and `ch`
are there on purpose: they are a signature under every change, not noise.

---

## Syntax basics

- **Comments** start with `#` and run to the end of the line.
- **Strings** use double `"..."` or single `'...'` quotes.
- **Interpolation**: `{expression}` inside a string inserts a value. A literal brace is `{{` or `}}`.
- **Escapes**: `\n` (line feed), `\r` (carriage return), `\t` (tab), `\\`, `\"` and `\'`. Escapes also work in string expressions inside interpolation.
- **Numbers**: `152`, `-7`, hex `0xFF`, fractions `1.5`.
- **Statements** end with `;`.
- **Blocks** for functions, `if`, `else if`, `else`, `for`, `while` and `recover` can open
  with a colon. The body starts on the next line and is indented. Returning to the header's
  indentation ends the block. The existing `{ ... }` syntax is also supported.
- **Entry point** is the `host { … }` block. The program starts there; there is no `main` function.

```
host {
    string who = "world";
    print("hello, {who}!");          # hello, world!
    print("brace: {{ not interpolation }}");
}
```

In `for i in 0:3:`, the first colon forms the range and the second opens the block.
With colon blocks, `else if` and `else` align with their `if` or `recover` header.

```
fn sum_to(num limit):
    num total = 0;
    for i in 0:limit:
        do(total >> ch(total + i));
    return total;

host {
    if sum_to(3) == 6:
        print("matched");
    else:
        print("failed");
}
```

---

## Types

| Type | Holds | Example |
|---|---|---|
| `num` | whole number (64-bit) | `num x = 152;` |
| `dec` | fractional number | `dec p = 1.5;` |
| `string` | text (UTF-8) | `string s = "Hello";` |
| `bool` | `true` / `false` | `bool ok = true;` |
| `mas` | array of values of one kind | `mas a = (1, 2, 3);` |
| `bytes` | a block of raw memory | `bytes b = mem >> take(16);` |
| `file` | a path to a file | `file f = "data.txt";` |
| `dir` | a path to a folder | `dir d = "logs";` |
| `conn` | a network connection | `conn c = "host:port" >> connect;` |
| `server` | a listening socket | `server s = net >> listen(9100);` |
| `proc` | another process | see [proc](#proc-other-processes) |
| `all` | type taken from the value | `all n = a >> get(0);` |

`all` means "work it out": the compiler takes the real type from the right-hand side.

---

## Declaring variables

```
num x = 152;              # with a starting value
num e();                  # empty: cannot be read until something is assigned
all s = add(2, 3);        # type taken from the call

string g = "global";      # declared outside functions: global
mas names = (string);     # empty array of strings (kind in parentheses)
mas a = (1, 2, 3);        # array with elements
mas b(3) = (10, 20);      # with a capacity limit of 3
mas c = ();               # empty; kind comes from the first add
```

An empty variable (`num e();`) has no value, and the compiler refuses to read it until data is
assigned with `ch`:

```
num e();
do(e >> ch(x * 2));       # now it can be read
```

Declarations outside functions are **global** and visible in every function.

---

## Chains and it

`>>` passes a value from left to right; read it as "then". A chain can be as long as you like:

```
mas top = a >> sort >> get(3:4);                 # sort, then take a slice
num n = path >> open >> append("x\n") >> sz;
```

When an action chain is assigned to a variable, `do` is not needed — the declaration wraps it:

```
mas even = nums >> keep(it % 2 == 0);      # a declaration, no do
do(c >> add(7) >> add(8));                 # a pure action, needs do
```

`it` is the current element inside array methods (`keep`, `each`):

```
a >> keep(it > 4)          # keep elements greater than 4
a >> each(it * 2)          # replace each with its double
```

---

## Operators

- **Arithmetic**: `+` `-` `*` `/` `%`
- **Comparison**: `==` `!=` `<` `>` `<=` `>=`
- **Logic**: `and` `or` `not`
- **Range**: `a:b` — from `a` to `b` inclusive (in `for`, slices and `input`)
- **Bits** are methods, not symbols: see [num and dec](#num-and-dec).

```
print("{x / 3}, remainder {x % 7}");
if x > 100 and ok { print("yes"); }
for i in 0:4 { ... }           # 0, 1, 2, 3, 4
s >> get(0:5)                  # characters 0 to 5
```

---

## Control flow

```
if x > 100 and ok {
    print("big");
} else {
    print("small");
}

for v in a {                   # over the elements of an array
    do(sum >> ch(sum + v));
}

for i in 0:4 {                 # over a range (inclusive)
    print(a >> get(i));
}

num k = 0;
while k < 3 {
    do(k >> ch(k + 1));
}
```

`break` leaves the nearest loop; `next` skips to its next iteration:

```
for v in a {
    if v == 0 { next; }        # skip and go on
    if v > 100 { break; }      # leave the loop
    do(sum >> ch(sum + v));
}
```

---

## Functions

```
fn fib(num n) {
    if n < 2 { return n; }
    return fib(n - 1) + fib(n - 2);
}

fn add(num a, num b) {
    return a + b;
}

fn show(mas m) {
    print("{m >> sz} elements");
}
```

Parameters are `type name`, separated by commas. `return` returns a value. A function without
`return` returns nothing and is called through `do(...)` when it is an action.

---

## Records, maps and function values

`record` declares a record. The constructor takes values in field order. `p >> x` reads a field,
and `do(p >> x(7))` updates it. Assignment gives the same record another name, and `ch` rebinds
the variable. Fields can use concrete types, earlier record types and collections with an
element type such as `mas(string)` or `map(num)`.

A `map` has string keys and one value type. `set` adds or replaces an entry. `remove` ignores a
missing key. `has` checks for a key and `sz` gives the key count. `get(key)` raises an error for
a missing key. `get(key, fallback)` computes the fallback only when needed. Lookup is linear.

A named function with concrete parameter types can be assigned to an `all` variable, passed
or returned. In `x -> ...`, the parameter has type `num`. Supply types explicitly with
`(num x, dec y) -> ...`. Anonymous functions can read globals. Pass local values as arguments.

```bit
record Point:
    num x;
    num y;

fn apply(all operation, num value):
    return operation(value);

host {
    Point p = Point(2, 3);
    do(p >> x(7));
    map counts = (num);
    do(counts >> set("x", p >> x));

    all twice = x -> x * 2;
    print(apply(twice, counts >> get("x", 0)));
}
```

## Including files

`use "lib/math.bit";` resolves paths relative to the file that contains the directive.
Included files share a namespace. Each path is loaded once, and cycles are errors.
Only the entry file can contain `host { }`.

## Failures: recover and else

When a system operation fails (no such file, no such folder, no connection), the program stops by
default with exit code 1 and a message. To decide yourself — skip, retry, log — wrap the operations
in `recover`:

```
for p in files {
    file f = p;
    recover {
        string d = f >> read;
        do(report >> append(d));
    } else {
        do(report >> append("not read: {p}\n"));
    }
}
```

If anything inside `recover` fails, execution jumps to `else` and the program goes on. `recover`
blocks can be nested; the nearest one catches the failure. Changes made inside `recover` before the
failure are kept.

`term >> error` tells what failed: the text of the last caught error (an empty string if nothing
failed). The program picks its own exit code with `term >> exit(code)`:

```
recover {
    do(f >> write(data));
} else {
    print("failed: {term >> error}");
    do(term >> exit(3));
}
```

---

## Methods by type

Methods are called with `>>`. The main ones for each type follow.

### num and dec

Arithmetic and comparison use operators. `num` is a signed 64-bit integer, and `dec` is a
floating-point number. A `num` overflow that occurs at runtime can be handled with `recover`.

| Method | What it does |
|---|---|
| `n >> abs` | absolute value (`num` or `dec`) |
| `n >> sqrt` | square root, result is `dec` |
| `n >> pow(k)` | `n` to the whole power `k` (`num` only) |
| `a >> min(b)` / `a >> max(b)` | smaller / larger of two (`num` or `dec`) |

Bit operations on `num`:

| Method | What it does |
|---|---|
| `n >> shift_left(k)` | shift bits left by `k` |
| `n >> shift_right(k)` | shift bits right by `k` (logical) |
| `a >> bit_and(b)` / `bit_or(b)` / `bit_xor(b)` | bitwise AND / OR / XOR |
| `n >> bit_not` | invert all bits |

```
num m = n >> shift_left(3) >> bit_and(0xFF);
dec r = 2 >> sqrt;                 # 1.4142135623730951
num c = 3 >> pow(4);               # 81
```

### string

| Method | What it does |
|---|---|
| `s >> sz` | length in characters (not bytes) |
| `s >> get(i)` | character at an index |
| `s >> get(a:b)` | substring (by characters) |
| `s >> num` | parse a signed decimal integer, with surrounding ASCII whitespace allowed |
| `s >> lines` | `mas` of lines |
| `s >> split(sep)` | `mas` of parts between separators |
| `s >> trim` | without spaces, tabs and line breaks at both ends |
| `s >> replace(from, to)` | every `from` replaced with `to` |
| `s >> starts(p)` / `s >> ends(p)` | `true` if the text starts / ends with `p` |
| `s >> bytes` | `mas` of the string's bytes |
| `s >> run` | run as a shell command, return the output |

Invalid input or a value outside the `num` range raises an error that `recover` can handle.

Network methods of strings are under [Network](#network).

```
string s = "Hello, world";
print("{s >> get(0)} | {s >> get(0:4)} | length {s >> sz}");
mas parts = "a,b,c" >> split(",");            # (a, b, c)
string t = "  text  " >> trim;                # "text"
bool web = url >> starts("http://");
```

### mas (array)

| Method | What it does |
|---|---|
| `a >> sz` | number of elements |
| `a >> get(i)` | element at an index |
| `a >> get(i, fallback)` | element, or the fallback if there is no such index |
| `a >> get(a:b)` | slice (a new array) |
| `a >> first` / `a >> last` | first / last element |
| `a >> first(d)` / `a >> last(d)` | the same, or `d` if the array is empty |
| `a >> add(v)` | append an element |
| `a >> insert(i, v)` | insert `v` before index `i` |
| `a >> remove(i)` | remove the element at index `i` |
| `a >> pop` | remove the last element |
| `a >> set(i, v)` | replace an element |
| `a >> ch(other)` | replace the whole array |
| `a >> keep(it ...)` | keep matching elements (filter) |
| `a >> each(it ...)` | transform every element |
| `a >> find(v)` | index of the first `v` (or -1) |
| `a >> has(v)` | whether `v` is present |
| `a >> sum` | sum (numbers) |
| `a >> sort` | return a sorted copy |
| `do(a >> sort)` | sort the original array in place |
| `a >> join(sep)` | join strings with a separator |
| `a >> text(from, to)` | decode a slice of bytes as a string |

`insert`, `remove`, `pop`, `add` and `set` are actions and go inside `do(...)`. Indexes for `get`,
`set`, `insert` and `remove` must be provably in range. `first` and `last` without a fallback need
an array the compiler knows is not empty. Use `first(d)` or `last(d)` for a fallback. If an
alias shrinks an array, access checks its current length and raises a recoverable error. A
`for` loop over an array checks both the original and current lengths.

A `mas` is data, not a copy: `mas b = a` gives the same elements a second name. `>> add` and
`>> set` change the data itself, visible through any name; `>> ch` rebinds the variable (other names
keep looking at the old data). So an array passed to a function can be changed there, and everyone
who holds it sees the change.

Sorting in an expression creates a separate array. The original and its aliases keep their element
order. In an action chain inside `do(...)`, sorting changes the receiver in place.

```
mas a = (5, 3, 9, 1, 7);
print(a >> keep(it > 4));          # (5, 9, 7)
print(a >> each(it * 2));          # (10, 6, 18, 2, 14)
do(a >> insert(0, 42) >> pop);
mas words = ("cat", "dog", "ant");
print(words >> sort >> join(", "));
```

### file

| Method | What it does |
|---|---|
| `f >> write(text)` | write (overwrite) |
| `f >> append(text)` | add to the end |
| `f >> read` | the whole text |
| `f >> lines` | `mas` of lines |
| `f >> get(i)` / `get(a:b)` | line(s) by number |
| `f >> sz` | size in bytes |
| `f >> exists` | whether it exists |
| `f >> modified` | last change time (seconds since 1970, like `os >> now`) |
| `f >> delete` | delete the file |
| `f >> copy(path)` / `move(path)` | copy / move |
| `f >> save(bytes)` | write bytes as they are |
| `f >> load` | read as `bytes` |
| `f >> load(offset, count)` | read up to `count` bytes starting at the zero-based offset |
| `f >> save(bytes, offset)` | write a chunk at the zero-based offset, creating the file if needed |
| `f >> name` / `path` | name / full path |

`copy` streams data to a temporary file in the destination directory and replaces the destination
after the write succeeds. `move` uses a system rename and falls back to copying and deleting the
source across file systems. Passing the exact source path to either operation leaves the file in place.

Both the offset and the count are non-negative. `load(offset, count)` returns a buffer
whose size is the number of bytes actually read. At or past EOF it returns an empty
buffer. Free each chunk with `do(chunk >> free)` when done. `save(chunk, offset)` preserves
existing bytes outside the written range. Use `save(bytes)` to replace the entire file.

```
file f = "notes.txt";
do(f >> write("first\n") >> append("second\n"));
print("{f >> lines >> sz} lines, {f >> sz} bytes");
do(f >> delete);
```

### dir (folder)

| Method | What it does |
|---|---|
| `d >> make` | create (with any missing parents) |
| `d >> list` | `mas` of names inside (sorted) |
| `d >> walk` | `mas` of paths to every file inside, nested folders included |
| `d >> walk("info")` | `mas` of `FileInfo` records: path, size, and modification time |
| `d >> file(name)` | a `file` inside the folder |
| `d >> dir(name)` | a nested `dir` |
| `d >> exists` | whether it exists |
| `d >> remove` | delete an empty folder |
| `do(d >> remove_all)` | delete the folder and all its contents |
| `d >> name` / `path` | name / path |

```
dir d = "logs";
do(d >> make);
file f = d >> file("today.txt");
do(f >> write("..."));
print(d >> list);
```

`walk` goes into nested folders depth first, each folder in alphabetical order. Paths start with
the folder's own path. Links to folders are not followed, so a link back to a parent cannot loop;
links to files are listed.

```
dir src = "src";
for p in src >> walk {
    file f = p >> open;
    if os >> now - f >> modified < 3600 {
        print("changed in the last hour: {p}");
    }
}
```

`walk("info")` keeps the same traversal order as `walk`. The `"info"` argument must
be a literal so the result type is known at build time. Each item is a built-in record
(already defined; do not redeclare it):

```
record FileInfo:
    string path;
    num sz;
    num modified;
```

`path` starts with the original directory path, `sz` is measured in bytes, and
`modified` is in seconds since 1970. Records are snapshots; later file changes do
not update them. For ordinary files, size and time come from the same type check on
POSIX or from directory enumeration on Windows, with no separate request per field.
Links to files expose target metadata and may require another request; broken links
are skipped. Links to directories inside the tree are not followed.

```
dir src = "src";
for entry in src >> walk("info") {
    print("{entry >> path}: {entry >> sz} bytes, modified {entry >> modified}");
}
```

Record arrays support `for`, `get`, `first`, `last`, `add`, `set`, `keep`, `each`,
and slices. Create an empty array with `mas entries = (FileInfo);`.
For printing or sorting, select fields: `entries >> each(it >> sz) >> sort`.
Printing or sorting the records themselves is rejected at build time.

`remove_all` is a separate action; `remove` and `delete` still require an empty
folder. Nested symbolic links and Windows junctions are removed without traversing
their targets. A root path pointing to a directory link removes the link itself.
A regular file in place of the root directory, filesystem roots, empty paths, and
final `.` / `..` components are rejected. Home directories are protected: POSIX
compares canonical target and `HOME` paths; Windows resolves paths through file handles
and checks both `USERPROFILE` and `HOME`, ignoring case. Removal is rejected for home
itself and any ancestor containing it. Component boundaries matter: `home` does not
block deletion of its sibling `homeX`. Failures include the path where removal
stopped, including nested files, and can be caught with `recover`;
content already deleted is not restored. Windows READONLY is not cleared automatically:
call `read_only(false)` first when needed.

### Permissions (file and dir)

| Form | What it does |
|---|---|
| `f/d >> read_only` | macOS/Linux: none of the write bits are set; Windows: READONLY is set |
| `do(f/d >> read_only(true))` | clear all three write bits on macOS/Linux; set READONLY on Windows |
| `do(f/d >> read_only(false))` | set all three write bits on macOS/Linux; clear READONLY on Windows |
| `f/d >> permissions` | POSIX permission string, for example `"rw-r-----"` |
| `do(f/d >> permissions("rw-r-----"))` | replace permissions on macOS/Linux |

`f/d` means a file or directory. `read_only(false)` grants write permission to the owner,
group, and others; it does not restore a saved mode. Other POSIX mode bits are preserved.
On Windows this is a file attribute: it does not describe ACLs and does not prevent
writing inside a directory.

`permissions` is available only on macOS/Linux; using it on Windows gives a clear build
error. ACLs are not supported yet. The string has exactly nine characters: `rwxrwxrwx`,
with any character replaced by `-` in the same position. Invalid literals are rejected
at build time; invalid dynamic strings fail at runtime and can be caught with `recover`.
Setting permissions replaces the nine ordinary bits and clears setuid, setgid, and sticky.
POSIX permission operations follow symbolic links to their targets. Windows `read_only`
uses the path attributes returned by the system API.

```
file f = "data.txt";
do(f >> read_only(true));
print(f >> read_only);
do(f >> read_only(false));
```

### bytes (raw memory)

`bytes` is a raw block of memory. Indexed operations check the offset against its length.

| Method | What it does |
|---|---|
| `mem >> take(n)` | allocate `n` zeroed bytes |
| `b >> set(i, v)` | write the byte `v` at offset `i` |
| `b >> write(off, num)` | write a number (8 bytes) at an offset |
| `b >> get(i)` | the byte at an offset |
| `b >> read(off)` | the number (8 bytes) at an offset |
| `b >> read(off, format, order)` | read a value in the specified format |
| `do(b >> write(off, value, format, order))` | write a value in the specified format |
| `b >> text` | the contents as a string |
| `b >> sz` | size in bytes |
| `b >> addr` | address of the data as a `num` |
| `b >> free` | release the memory (buffer and descriptor) |

The format and byte order are string literals. `"u16"`, `"u32"` and `"i64"` return `num`.
`"f32"` and `"f64"` return `dec`. Use `"little"` or `"big"` for byte order.
For example, `b >> read(0, "u16", "big")` reads the first two bytes. Bounds errors and
out-of-range unsigned writes can be handled with `recover`.

`bytes` is raw memory and is **not** released automatically. When it is no longer needed, release it
explicitly, like any other action:

```
bytes b = mem >> take(1024);
do(b >> set(0, 42));
print("byte 0: {b >> get(0)}");
do(b >> free);                       # do not touch b after free
```

Free a buffer once through any name that refers to it. All aliases and addresses into the buffer
become invalid at that point. Keeping them valid up to the point of use is the program's responsibility.
The compiler releases temporary strings and strings in local declarations when it can prove they
stay within scope. Strings that may escape their scope can stay allocated for the life of the process.

The chosen model is ordinary reference counting: strings first, then arrays, maps,
and records. Compiler integration is not finished yet, so the current limitation above
still applies. A known limitation of the chosen model is that shared-data cycles are
not reclaimed automatically; those links must be broken explicitly. `bytes` retains
explicit `free`, and reference counts will not use atomic operations.

### mem (computer memory)

| Method | What it does |
|---|---|
| `mem >> total` | total memory (bytes) |
| `mem >> free` | free memory (a value; not the same as `b >> free`) |
| `mem >> used` | memory used by the program |
| `mem >> take(n)` | allocate `n` bytes → `bytes` |

### random

`random >> get(min, max)` returns an integer in the inclusive range. On first use the
generator creates a word with system entropy and uses the word's hash as its seed.
`do(random >> seed("word"))` sets the word explicitly. The same seed and range calls
produce the same sequence across architectures.

### os (system)

| Method | What it does |
|---|---|
| `os >> host` | computer name |
| `os >> user` | user name |
| `os >> cpus` | number of cores |
| `os >> now` | time (seconds since 1970) |
| `os >> clock` | monotonic milliseconds for measuring intervals |
| `os >> procs` | list of processes (text) |

### term (terminal)

| Value | What it gives |
|---|---|
| `term >> args` | command-line arguments (`mas`) |
| `term >> env("NAME")` | an environment variable |
| `term >> folder` | the current working directory (`dir`, absolute path) |
| `term >> pid` | the current process id |
| `term >> status` | exit code of the last command or program |
| `term >> error` | text of the last error caught by `recover` |
| `term >> error_code` | numeric code of the last caught failure |
| `term >> stderr` | stderr of the last `mas >> run` |

| Action | What it does |
|---|---|
| `term >> clear` | clear the screen |
| `term >> wait(ms)` | pause for milliseconds |
| `term >> exit(code)` | exit with a code |
| `term >> go(path)` | change the current directory; accepts `string` or `dir` |
| `term >> env("NAME", "value")` | set an environment variable in the current program |

`go` changes the base for all subsequent relative paths. Future `string >> run`,
`mas >> run`, and `string >> start` inherit the current directory and environment;
processes already running are unaffected. Changes do not affect the parent shell.
A saved `term >> env("NAME")` value remains valid after the environment changes.
An empty value reads as `""`; names must be nonempty and must not contain `=`.
Failures in `go` or environment updates can be caught with `recover`; a failed `go`
leaves the current directory unchanged. Windows updates both the process environment
and the CRT copy so `env` reads and all launch forms see the new value.

```
dir previous = term >> folder;
dir work = "working directory";
do(work >> make);
do(term >> go(work));
do(term >> env("BIT_MODE", "test"));
string mode = term >> env("BIT_MODE");
do(term >> go(previous));
```

Console input is a declaration with `input`:

```
num i >> input(0:4);           # read a number 0..4 (asks again if out of range)
string s >> input;             # read a line
```

The range of `input` is also a proof: after `num i >> input(0:4)` the compiler knows `i` is in 0..4,
so `a >> get(i)` on a five-element array passes the build-time check. The current length is still
checked when the program runs, because another name for the same array may have shortened it.

### Running programs

A shell command is `string >> run`; it returns the output:

```
string who = "whoami" >> run;
```

A program **directly**, without a shell, is `mas >> run`. The first element is the program, the rest
are its arguments; each arrives exactly as written, so spaces and quotes break nothing:

```
mas cmd = ("convert", "my photo.jpg", "out.png");
string out = cmd >> run;              # the program's stdout
string res = cmd >> run("input");     # the same, with text on stdin
num code = term >> status;            # exit code (127 — program not found)
string err = term >> stderr;          # stderr, separate from stdout
do(cmd >> run);                       # output straight to the terminal, code in term >> status
```

The runtime reads stdout and stderr while feeding stdin. macOS and Linux use `poll`.
On Windows two worker threads read the output streams.

### Network

Network calls that start external programs (`fetch`, `ping`, `post`, `download`) work **without a
shell**: arguments are passed as an array, so a URL may safely contain any characters. HTTP uses
`curl` and `ping` uses the system `ping`.

**HTTP:**

| Method | What it does |
|---|---|
| `"url" >> fetch` | GET — return the response body |
| `"url" >> post(data)` | POST — return the response |
| `"url" >> download("file")` | download into a file |
| `"host" >> ping` | `true` if the host answers |

**DNS:**

| Method | What it does |
|---|---|
| `"host" >> ip` | resolve a name to an IP address |

**TCP and UDP (sockets directly):**

| Method | What it does |
|---|---|
| `net >> listen(port)` | listen on all IPv4 interfaces → `server` |
| `net >> listen(port, "address")` | listen on a specified IPv4 address → `server` |
| `s >> accept` | accept a connection → `conn` |
| `c >> peer` | remote address and port as an `ip:port` string |
| `"ip:port" >> connect` | connect over TCP → `conn` |
| `"ip:port" >> connect(ms)` | connect over TCP, waiting no longer than `ms` milliseconds |
| `"ip:port" >> udp` | open UDP → `conn` |
| `c >> send("...")` | send |
| `c >> recv` | receive a string |
| `c >> recv(count, timeout_ms)` | receive up to `count` bytes as text, with a timeout |
| `c >> close` / `s >> close` | close |

```
# server
server s = net >> listen(9100);
conn c = s >> accept;
string msg = c >> recv;
do(c >> send("echo: {msg}"));
do(c >> close);
do(s >> close);

# client
conn c = "127.0.0.1:9100" >> connect;
do(c >> send("hello"));
print(c >> recv);
do(c >> close);
```

`listen` takes a port from 0 to 65535 and a numeric IPv4 address such as `"127.0.0.1"`;
hostnames and IPv6 are not supported here yet. Without an address it listens on all
interfaces. The socket uses `SO_REUSEADDR`; failures close it and can be caught by `recover`.
`connect` and `udp` take a numeric IPv4 address and port such as `"127.0.0.1:9100"`;
the port must contain only digits and be in 0–65535. Invalid addresses raise an error.
`peer` returns the remote end of a connected socket; a lookup failure is an error.

`os >> clock` returns monotonic milliseconds from an arbitrary origin. Subtract two
values to measure an interval; this is not calendar time, and values cannot be compared
across reboots or computers.

`recv` returns what a single read from the system gives; over TCP a long message may arrive in parts.
In `recv(count, timeout_ms)`, the count is in bytes (1–2147483647) and the timeout is in
milliseconds (0–2147483647). A zero timeout checks for data without waiting. A timeout
is an error that `recover` can handle, while a clean TCP close returns an empty string.
Join the chunks before processing text when a UTF-8 character can span two reads.

`connect(ms)` bounds the connection wait. macOS and Linux use a nonblocking socket
and `poll`; Windows uses a socket timeout.
What happened is told by `term >> error_code`: `1` the target refused, `2` the wait ended,
`3` no route to the target, `0` the failure has no code. The codes are the same on macOS,
Linux and Windows. A plain `connect` also fills `error_code` for refused and unreachable
targets, and a timed-out `recv` gives `2`.

### proc: other processes

Find, start, wait for and stop processes — on macOS, Linux and Windows. On Linux and Windows `proc`
also reads and writes another process's memory, like a debugger: on Linux through `/proc/<pid>/mem`,
on Windows through the system API (`OpenProcess`, `ReadProcessMemory`, `WriteProcessMemory`,
`VirtualQueryEx`). macOS closes other processes' memory without debugger rights, so there `read`,
`grab`, `scan`, `maps`, `write` and `paste` are a build error with a clear message.

| Form | What it does |
|---|---|
| `"name" >> proc` | find a process by name (pid `-1` if there is none); on Windows with or without `.exe` |
| `1234 >> proc` | a process by its pid |
| `"command" >> start` | start a process and return it |
| `p >> pid` / `name` / `alive` | pid / name / whether it is running |
| `p >> wait` | wait for it to finish, return the exit code |
| `p >> read(addr)` | the number (8 bytes) at an address |
| `p >> grab(addr, n)` | `n` bytes at an address → `bytes` |
| `p >> scan(value)` | `mas` of addresses where this 8-byte number lies |
| `p >> maps` | `mas` of memory regions, each line starting with `start-end rwxp` |
| `do(p >> write(addr, num))` | write a number (8 bytes) |
| `do(p >> paste(addr, bytes))` | write bytes |
| `do(p >> kill)` | stop the process; `wait` then returns 143 |

```
proc p = "exec ./target" >> start;
num v = p >> read(addr);
do(p >> write(addr, 0x00DEADBEEF000000));
mas hits = p >> scan(0x1122334455667788);
print("exit code {p >> wait}");
```

Reading or writing an address the process does not have is a failure that `recover` catches.

Differences between the systems: on macOS and Linux `start` runs the command through the shell
(`exec` makes the shell become the program, so the pid and name are the program's), on Windows the
program starts directly and a leading `exec ` is ignored — `"exec ./target"` works everywhere.
On macOS and Linux `wait` works for processes the program started itself (otherwise `-1`), and
`maps` lines on Linux carry more fields after the permissions. `kill` asks the process to finish;
right after it `alive` may still be `true`, `wait` waits for the end. A missing process (pid `-1`)
is never signalled: `kill` on it is a failure that `recover` catches. Examples: [`examples/linux/`](../examples/linux/),
[`examples/win/`](../examples/win/). In `gold_game.bit` and `gold_hack.bit` one program finds
another by name, scans its memory for a value and replaces it.

---

## Compiler checks

The compiler checks types, initialization and index ranges before generating code.

- **Array bounds.** `a >> get(i)` needs a provable index, for example from `for i in 0:a>>sz-1`
  or a check such as `if i >= 0 and i < a >> sz`. The generated code checks the current length
  before accessing the element.
- **`num` overflow.** Arithmetic that goes beyond 64 bits is caught.
- **Empty variables.** `num e();` cannot be read before it is assigned.
- **Types.** A type mismatch is a build error.

---

## Building for other platforms

One source builds for every supported platform:

```bash
./bitc build prog.bit -o prog                  # current OS and architecture
./bitc build prog.bit -o prog --arch x86_64     # x86-64 (on an ARM Mac — via Rosetta)
./bitc build prog.bit -o prog --os linux        # Linux (assemble on Linux)
./bitc build prog.bit -o prog.exe --os windows  # Windows (needs mingw-w64)
```

Inside, the language uses one calling convention (System V) everywhere; the differences of Windows
(another calling convention, Winsock, argument quoting) are hidden in thin runtime wrappers.

On Windows a program behaves like on macOS and Linux: text is UTF-8 everywhere — in paths, commands,
arguments and the console (the program embeds a manifest and switches the console to UTF-8 while it
runs, Windows 10 1903 or newer). Files are written byte for byte, `\n` stays `\n`. Runtime messages
are the same as on the other systems.

`./tests_win.sh host` builds the test suite for Windows, runs it on a real machine over SSH and
compares the output.

---

## How the compiler works

- `bitc.bit` is the compiler itself, written in bit: lexer → parser → type checks and proofs →
  ARM64 or x86-64 assembly.
- `rt/arm64.s`, `rt/x86_64.s` are the runtime in assembly (printing, strings, arrays, files, memory,
  network, processes). The Linux and Windows runtimes are generated from them by the scripts in
  `tools/`; the generated files are committed, so building needs no extra tools.
- `tools/embed_rt.bit` embeds the runtime into the compiler, so a built `bitc` is self-contained.
- `bootstrap/` holds the assembly of the compiler; `bootstrap.sh` builds everything from scratch
  (`as` + `ld`) and checks that the compiler, building itself, gives the same result.
- `tools/build_opt.sh` builds an experimental optimizing variant of the compiler into `build/`.

Neither C nor LLVM takes part in the build.
