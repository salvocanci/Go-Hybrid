#!/usr/bin/env python3
"""Spike 5 bench analysis: median + spread + alloc counts."""
import re
import sys
from collections import defaultdict

RUST_INNER = 1 << 20


def main(path):
    pat = re.compile(
        r"^Benchmark(\S+?)(?:-\d+)?\s+\d+\s+([\d.]+) ns/op\s+(\d+) B/op\s+(\d+) allocs/op")
    runs = defaultdict(list)
    allocs = {}
    for line in open(path):
        m = pat.match(line)
        if m:
            runs[m.group(1)].append(float(m.group(2)))
            allocs[m.group(1)] = int(m.group(4))

    print(f"{'benchmark':24} {'median ns/op':>13} {'min':>10} {'max':>10} {'allocs':>7}")
    med = {}
    for name in sorted(runs):
        v = sorted(runs[name])
        n = len(v)
        m = v[n // 2] if n % 2 else (v[n // 2 - 1] + v[n // 2]) / 2
        med[name] = m
        print(f"{name:24} {m:13.2f} {v[0]:10.2f} {v[-1]:10.2f} {allocs[name]:7d}")

    print("\nderived:")
    if "OkPath" in med:
        print(f"  E1 ok path            = {med['OkPath']:.2f} ns/op, {allocs.get('OkPath', -1)} allocs (wrapped)")
    if "WideDirect" in med:
        print(f"  E1 direct crossing    = {med['WideDirect']:.2f} ns/op, {allocs.get('WideDirect', -1)} allocs")
    if "ErrSentinel" in med:
        print(f"  E2 sentinel error     = {med['ErrSentinel']:.2f} ns/op, {allocs.get('ErrSentinel', -1)} allocs")
    if "ErrDynamic" in med:
        print(f"  E3 dynamic error      = {med['ErrDynamic']:.2f} ns/op, {allocs.get('ErrDynamic', -1)} allocs")
    if "RustResultLoop" in med:
        print(f"  E6 rust Result (ok)   = {med['RustResultLoop'] / RUST_INNER:.3f} ns/iter")
    if "RustResultLoopErr" in med:
        print(f"  E6 rust Result (err)  = {med['RustResultLoopErr'] / RUST_INNER:.3f} ns/iter")
    if "GoNativeOk" in med and "OkPath" in med:
        print(f"  crossing overhead vs native (T,error) = {med['OkPath'] - med['GoNativeOk']:.2f} ns (wrapped API)")


if __name__ == "__main__":
    main(sys.argv[1])
