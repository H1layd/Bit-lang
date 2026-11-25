#!/usr/bin/env python3
"""Measure self-build wall time and the compiler's own mem >> used value."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import statistics
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--compiler", default="bitc")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.label):
        parser.error("--label must contain only letters, digits, underscores, or hyphens")
    if args.runs < 1:
        parser.error("--runs must be positive")
    root = Path(__file__).resolve().parent.parent
    compiler = (root / args.compiler).resolve()
    source = (root / "bitc.bit").read_text()
    anchor = '        print("готово: {exe}");\n        return;'
    if source.count(anchor) != 1:
        parser.error("cannot locate the build completion point in bitc.bit")
    measured = source.replace(
        anchor, '        print("BIT_SELF_MEMORY:{mem >> used}");\n' + anchor
    )
    work = root / "build/memory-profile/work"
    output = root / "build/memory-profile" / args.label
    if (output / "metrics.json").exists():
        parser.error("this label already has measurements; choose a new label")
    work.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    input_path = work / "bitc-measured.bit"
    binary_path = work / "bitc-measured"
    input_path.write_text(measured)
    subprocess.run(
        [str(compiler), "build", str(input_path), "-o", str(binary_path)],
        cwd=root, check=True, stdout=subprocess.DEVNULL,
    )
    samples = []
    for index in range(args.runs):
        started = time.perf_counter()
        result = subprocess.run(
            [str(binary_path), "build", str(input_path), "-o", str(work / "bitc-self")],
            cwd=root, check=True, capture_output=True, text=True,
        )
        elapsed = time.perf_counter() - started
        (output / f"run-{index}.txt").write_text(result.stdout + result.stderr)
        match = re.search(r"^BIT_SELF_MEMORY:(\d+)$", result.stdout, re.MULTILINE)
        if match is None:
            raise RuntimeError("compiler did not report mem >> used")
        sample = {"wall_seconds": round(elapsed, 3), "mem_used_bytes": int(match[1])}
        samples.append(sample)
        print(json.dumps(sample), flush=True)
    report = {
        "label": args.label,
        "compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
        "source_sha256": hashlib.sha256(source.encode()).hexdigest(),
        "samples": samples,
        "median_wall_seconds": statistics.median(s["wall_seconds"] for s in samples),
        "median_mem_used_bytes": statistics.median(s["mem_used_bytes"] for s in samples),
    }
    (output / "metrics.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report), flush=True)


if __name__ == "__main__":
    main()
