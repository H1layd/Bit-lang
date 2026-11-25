#!/usr/bin/env python3
"""Exercise private string ownership operations without exposing them in bit."""
import argparse
from pathlib import Path
import platform
import re
import subprocess


def run(args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def write_unwind_probes(root, work, compiler):
    # Observe the ownership invariant after an ordinary compiled program returns:
    # no live strings or stack cleanup records remain after successful calls or recover.
    arm_check = """    adrp x1, Lrt_owned@PAGE
    ldr x1, [x1, Lrt_owned@PAGEOFF]
    cbnz x1, Lprobe_unwind_bad
    adrp x1, Lrt_str_registry@PAGE
    ldr x1, [x1, Lrt_str_registry@PAGEOFF]
    cbz x1, Lprobe_unwind_bad
    mov x2, #1048576
Lprobe_unwind_scan:
    ldr x3, [x1], #8
    cbnz x3, Lprobe_unwind_bad
    subs x2, x2, #1
    b.ne Lprobe_unwind_scan
    mov x0, #0
    b Lprobe_unwind_end
Lprobe_unwind_bad:
    mov x0, #1
Lprobe_unwind_end:
"""
    x86_check = """    cmp qword ptr [rip + Lrt_owned], 0
    jne Lprobe_unwind_bad
    mov rdx, [rip + Lrt_str_registry]
    test rdx, rdx
    jz Lprobe_unwind_bad
    mov ecx, 1048576
Lprobe_unwind_scan:
    cmp qword ptr [rdx], 0
    jne Lprobe_unwind_bad
    add rdx, 8
    dec ecx
    jnz Lprobe_unwind_scan
    xor eax, eax
    jmp Lprobe_unwind_end
Lprobe_unwind_bad:
    mov eax, 1
Lprobe_unwind_end:
"""
    for name, flags, check, zero in (
        ("arm64", ["--arch", "arm64"], arm_check, "    mov x0, #0\n"),
        ("x86_64", ["--arch", "x86_64"], x86_check, "    xor eax, eax\n"),
        ("linux", ["--os", "linux"], x86_check, "    xor eax, eax\n"),
        ("windows", ["--os", "windows"], x86_check, "    xor eax, eax\n"),
    ):
        if platform.system() == "Linux" and name in ("arm64", "x86_64"):
            continue
        asm = subprocess.check_output(
            [str(compiler), "asm", str(root / "tests/rt/string_unwind.bit"), *flags],
            cwd=root, text=True,
        )
        entry, marker, rest = asm.partition("_bit_ginit:")
        if not marker or entry.count(zero) != 1:
            raise RuntimeError(f"cannot locate {name} entry point result")
        (work / f"unwind-{name}.s").write_text(entry.replace(zero, check) + marker + rest)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cross", action="store_true")
    parser.add_argument("--windows-host")
    parser.add_argument("--compiler", default="bitc")
    args = parser.parse_args()
    if args.windows_host and not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", args.windows_host):
        parser.error("use an SSH hostname or config alias")
    root = Path(__file__).resolve().parent.parent
    work = root / "build/string-ref-probe"
    work.mkdir(parents=True, exist_ok=True)
    arm = (root / "tests/rt/string_refs_arm64.s").read_text()
    x86 = (root / "tests/rt/string_refs_x86_64.s").read_text()
    (work / "arm64.s").write_text(arm + "\n" + (root / "rt/arm64.s").read_text())
    targets = [
        ("x86_64", "_main", "_strlen", "_free", "x86_64.s"),
        ("linux", "main", "strlen@PLT", "free@PLT", "x86_64-linux.s"),
        ("windows", "main", "_w_strlen", "_w_free", "x86_64-windows.s"),
    ]
    for name, entry, strlen, free, runtime in targets:
        driver = x86.replace("MAIN", entry).replace("STRLEN", strlen).replace("FREE", free)
        if name == "x86_64":
            driver = driver.replace(".text\n", ".section __TEXT,__text,regular,pure_instructions\n", 1)
        (work / f"{name}.s").write_text(driver + "\n" + (root / "rt" / runtime).read_text())
    write_unwind_probes(root, work, (root / args.compiler).resolve())
    for prefix, description in (
        ("", "reference counts and 1048577 entries with guaranteed collisions"),
        ("unwind-", "compiled calls and recover leave no live string references"),
    ):
        if platform.system() == "Darwin":
            sdk = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
            arches = ("arm64", "x86_64") if platform.machine() == "arm64" else ("x86_64",)
            for arch in arches:
                run(["as", "-arch", arch, "-mmacosx-version-min=13.0",
                     "-o", work / f"{prefix}{arch}.o", work / f"{prefix}{arch}.s"])
                run(["ld", "-arch", arch, "-platform_version", "macos", "13.0", "13.0",
                     "-syslibroot", sdk, "-lSystem", "-e", "_main",
                     "-o", work / f"{prefix}{arch}", work / f"{prefix}{arch}.o"])
                run([work / f"{prefix}{arch}"])
                print(f"{arch}: {description} passed", flush=True)
        elif platform.system() == "Linux":
            run(["as", "--64", "-o", work / f"{prefix}linux.o", work / f"{prefix}linux.s"])
            candidates = [Path(p) for p in (
                "/usr/lib/x86_64-linux-gnu", "/usr/lib64", "/usr/lib", "/lib/x86_64-linux-gnu"
            )]
            library = next((p for p in candidates if (p / "crt1.o").exists()), None)
            if library is None:
                raise SystemExit("Linux probe needs x86-64 libc development files")
            run(["ld", "-o", work / f"{prefix}linux", "-dynamic-linker", "/lib64/ld-linux-x86-64.so.2",
                 library / "crt1.o", library / "crti.o", work / f"{prefix}linux.o", "-lc",
                 library / "crtn.o"])
            run([work / f"{prefix}linux"])
            print(f"Linux: {description} passed", flush=True)
        else:
            raise SystemExit("native probes require macOS or an x86-64 Linux toolchain")
        if args.cross or args.windows_host:
            run(["clang", "-target", "x86_64-linux-gnu", "-c",
                 work / f"{prefix}linux.s", "-o", work / f"{prefix}linux.o"])
            run(["x86_64-w64-mingw32-gcc", "-static", work / f"{prefix}windows.s",
                 "-o", work / f"{prefix}windows.exe", "-lws2_32", "-lbcrypt"])
            print(f"{description}: Linux and Windows probes assembled", flush=True)
        if args.windows_host:
            host = args.windows_host
            run(["scp", "-q", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
                 work / f"{prefix}windows.exe", f"{host}:bit-string-refs-{prefix}probe.exe"], timeout=30)
            try:
                run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
                     host, f"bit-string-refs-{prefix}probe.exe"], timeout=30)
            finally:
                subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
                                host, f"del bit-string-refs-{prefix}probe.exe"], timeout=15, check=False)
            print(f"Windows: {description} passed", flush=True)


if __name__ == "__main__":
    main()
