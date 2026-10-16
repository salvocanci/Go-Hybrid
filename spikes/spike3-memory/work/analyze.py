#!/usr/bin/env python3
"""Spike 3 bench analysis: median + spread from `go test -bench -count=10` output.

Usage: python3 analyze.py bench.sandbox.out
Same deviation as Spike 1 (no benchstat on this box): python stats instead.
"""
import re
import sys
from collections import defaultdict

RUST_INNER = 1 << 20  # BenchmarkRustSideObjGet inner iterations per op


def main(path):
    pat = re.compile(
        r"^Benchmark(\S+?)(?:-\d+)?\s+\d+\s+([\d.]+) ns/op(?:\s+(\d+) B/op\s+(\d+) allocs/op)?")
    runs = defaultdict(list)
    for line in open(path):
        m = pat.match(line)
        if m:
            name, ns, b, a = m.group(1), float(m.group(2)), m.group(3), m.group(4)
            runs[name].append((ns, int(b or 0), int(a or 0)))

    print(f"{'benchmark':38} {'median ns/op':>13} {'min':>11} {'max':>11} {'B/op':>7} {'allocs':>7}")
    med = {}
    for name in sorted(runs):
        vals = sorted(runs[name])
        ns_sorted = sorted(v[0] for v in vals)
        n = len(ns_sorted)
        mid = ns_sorted[n // 2] if n % 2 else (ns_sorted[n // 2 - 1] + ns_sorted[n // 2]) / 2
        med[name] = mid
        allocs = max(v[2] for v in vals)
        bop = max(v[1] for v in vals)
        print(f"{name:38} {mid:13.2f} {ns_sorted[0]:11.2f} {ns_sorted[-1]:11.2f} {bop:7d} {allocs:7d}")

    # derived figures for RESULTS.md
    print("\nderived:")
    d = []
    if "GoTableCreateRelease" in med and "GoTableGet" in med:
        d.append(f"P1 handle create+release = {med['GoTableCreateRelease']:.2f} ns/op")
        d.append(f"P2 handle get            = {med['GoTableGet']:.2f} ns/op")
    if "CallAdd" in med and "SumPinned1" in med and "SumRaw1" in med:
        d.append(f"P3 pin/unpin delta       = {med['SumPinned1'] - med['SumRaw1']:.2f} ns "
                 f"(pinned {med['SumPinned1']:.2f} vs raw {med['SumRaw1']:.2f}; M4 baseline {med['CallAdd']:.2f})")
    if "RustSideObjGet" in med:
        per = med["RustSideObjGet"] / RUST_INNER
        d.append(f"P4 rust id resolve       = {per:.2f} ns/resolve (inner {RUST_INNER})")
    if "CgoHandleNewDelete" in med and "GoTableCreateRelease" in med:
        d.append(f"cgo.Handle create+delete = {med['CgoHandleNewDelete']:.2f} ns/op "
                 f"({med['CgoHandleNewDelete'] / max(med['GoTableCreateRelease'], 0.01):.1f}x our table)")
    for line in d:
        print("  " + line)


if __name__ == "__main__":
    main(sys.argv[1])
