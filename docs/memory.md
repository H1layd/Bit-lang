# bit memory: agreed rules and implementation status

Reference counting is not fully integrated yet. This document distinguishes the agreed
contract from behavior already available in ordinary programs.

## Author decisions

- Ordinary reference counts without atomic operations.
- Implement `string` first, then `mas`, `map`, and records; preserve shared ownership.
- Keep explicit `free` for `bytes`.
- Shared-data cycles are not reclaimed automatically; links must be broken explicitly.
- Measure self-build time and `mem >> used` before and after each stage.
- Show significant slowdowns to the author before deciding how to proceed.
- Stop before the package manager and wait for author instruction.

## String implementation checklist

- [x] Capture a baseline and add a repeatable measurement tool.
- [x] Add private adoption, retain, and release operations.
- [x] Test idempotent adoption, multiple owners, last-reference release, null, literals,
  and hash collisions with 1,048,577 strings on macOS ARM64 and x86-64.
- [x] Assemble standalone Linux and Windows probes.
- [x] Update cleanup records on `ch` and `input` for nonescaping local strings; retain
  the replacement before releasing the old value, including self-assignment.
- [x] Borrow immutable, nonescaping parameters from the reference held by the caller.
- [ ] Finish ownership for declarations, assignment, parameters, and returns,
  including aliases and global strings.
- [ ] Cover record fields and container-held strings, including copying and replacement.
- [x] Include string call arguments in `recover` cleanup, covering later-argument
  failures and failures inside the called function; check for remaining references.
- [ ] Balance other temporaries and exits through `return`, loops, and `recover`.
- [ ] Audit internal runtime string buffers and system-call results.
- [ ] Pass functional and long-running checks on three OSes and repeat measurements.

Code generation now adopts known fresh strings, holds string arguments for the duration
of calls, and preserves returned strings when leaving functions. A regression test covers
returns, nested calls, and function values. Integration remains partial: escape analysis
conservatively keeps potentially shared strings alive, leaving leaks. Aliased assignments,
containers, fields, some temporary method receivers, and other expression temporaries
on `recover` exits still need work. String arguments of ordinary and function-value calls
now join the cleanup chain: a failing later argument or called function releases them
automatically when unwinding to `recover`. Nonescaping locals now update their cleanup
records on replacement, retaining the new value before releasing the old one so that
self-assignment is safe. Concatenation, comparisons, copying interpolation, and ordinary
calls no longer require keeping the source string alive forever. Immutable, nonescaping
parameters borrow the reference held by the caller. Temporary string receivers are held
through `sz`, string methods, `get`, and ordinary methods returning independent results; `recover` releases them if an argument or the
method fails. For 50,000 `make(i) >> sz` calls returning roughly 1 KB strings, peak
memory fell from 80,248,832 to 1,785,856 bytes with the same checksum, 51,438,890.
Method arguments, actions, and other temporaries still require separate auditing.
Parameters captured in shared storage still retain a permanent reference: this preserves
correctness but leaks until explicit container-held string ownership is implemented.

## Current internal implementation

Reference counts live in a separate address-indexed registry. This preserves UTF-8 pointer
representation and avoids reading headers before unknown pointers. Unknown pointers
are not freed. The registry is allocated on first adoption; the current version uses
1,048,576 buckets and separate nodes. Pointers outside the conservative address range of
adopted strings are rejected before lookup; the range never shrinks after release.
The compiler emits no ownership operations for literal string arguments.

File names are copied from interior pointers. `file >> get(index)` produces an independent
string and releases its source buffer; empty slices own their memory too. Reference counts
are partially connected to file, network, and string operation results; temporary receivers
and remaining results still need an audit.

Measure the cost after integration. This design still requires distinguishing new strings,
borrowed results, and interior pointers. Integration must retain the owner or create
a separate string before releasing its backing storage.

## Baseline

macOS ARM64, three self-builds using an instrumented compiler copy. Median:

| Stage | Time | Peak `mem >> used` |
|---|---:|---:|
| Before string reference counting | 2.939 s | 518,176,768 bytes |
| Partial call and return integration | 4.914 s | 595,476,480 bytes |
| Early rejection outside the string address range | 4.466 s | 597,753,856 bytes |
| Additionally skip literal argument ownership | 4.706 s | 589,725,696 bytes |
| Clean up call arguments on `recover` unwinding | 4.579 s | 594,001,920 bytes |
| Local replacement and copying reads | 3.714 s | 553,943,040 bytes |
| Borrow immutable parameters | 3.744 s | 553,353,216 bytes |
| Account for call argument and result ownership | 3.618 s | 549,437,440 bytes |
| Partially integrate runtime string results | 5.351 s | 607,928,320 bytes |
| Expand the string registry | 3.422 s | 615,383,040 bytes |
| Clean up temporary method receivers | 3.622 s | 616,448,000 bytes |

The first partial integration increased time by 67% and memory by 15%; those figures
were shown to the author. Partially integrating runtime results increased median time from 3.618 to 5.351 s (+48%)
and peak memory from 549,437,440 to 607,928,320 bytes (+11%). Compared with baseline,
that is about 82% slower and 17% higher peak memory. The figures were shown to the author;
profiling was the next step. Registry lookup accounted for about 60% of self-build
samples. Expanding the table from 65,536 to 1,048,576 buckets lowered the median to
3.422 s but raised the peak by another 7,454,720 bytes. A small example with one dynamic
string peaked at 1,703,936 bytes in either version; other programs may differ.
After receiver cleanup, three self-build runs took 5.307, 3.583, and 3.622 s; median
3.622 s and peak 616,448,000 bytes. The first run was markedly slower than the others. Small differences between adjacent measurements are
not treated as guaranteed speedups because individual run times vary. Finish string
ownership and reassess its cost before starting arrays.

A returned-string example reached 2,015,232 bytes of peak RSS at 10,000 calls and
11,337,728 bytes at 300,000 calls before integration. After partial integration, both
sizes reached 1,785,856 bytes with matching checksums. This validates one scenario,
not the absence of all string leaks. At this stage macOS ARM64/x86-64 functional checks
passed 203/203 after temporary receiver cleanup and self-hosting converged. Windows 11
via SSH passed 47/47 runtime checks, 53 expected compile errors, and both registry and
cleanup probes. `remove_all` tests cover HOME and USERPROFILE, their ancestors, a sibling,
and the failure path. Linux x86-64 under QEMU in Colima: self-hosting converged,
the latest full run passed 102/102 tests, as did both private probes. One earlier full run had an unexplained
`envaction` mismatch; 100 isolated repetitions and subsequent full runs passed.
Subsequent checks showed intermittent SIGSEGV of the ARM `qemu-x86_64` process:
2 of 1,000 runs for the current compiler and 6 of 1,500 on the previous commit.
The underlying cause is unknown and limits confidence in emulated runs. The author confirmed the previous native Linux server was deleted; no replacement native
host is currently available for checks. Linux checks ran as an unprivileged user.

Repeat with `python3 tools/measure_self.py --label NAME --runs 3`.
JSON and individual run output are saved under `build/memory-profile/`.
The instrumented copy reads `mem >> used` at build completion without modifying
the primary source. Measurements cover command wall time and compiler peak memory.

Run private-operation checks with `python3 tools/test_string_refs.py --cross`.
The tool also checks that successful calls, function-value calls, and caught failures
leave no live string references or cleanup records. The pre-fix compiler fails this
probe; the fixed compiler passes on both macOS architectures. In a stress case with
50,000 caught failures following creation of a roughly 1 KB argument, peak `mem >> used`
fell from 72,384,512 to 1,818,624 bytes.
A stress case with 50,000 replacements of a roughly 1 KB local string and self-assignment
reduced peak memory from 72,400,896 to 1,802,240 bytes; both checksums were 51,438,890.
The expanded private probe covers local replacement, mutable parameters, returning from
`recover` handlers, and the absence of remaining references after program completion.
Add `--windows-host dtwin` to execute the probe on a real Windows machine.
