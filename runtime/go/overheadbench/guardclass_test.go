package overheadbench

// Row 4 (per-callee fast-path stack budgets) regression tests.
//
// The class discipline (interfaces/descriptors.md): the fast path's guard
// proves headroom AT ENTRY and nothing after, so a callee may take a guarded
// fast path only if its worst-case stack use is an upper bound below the
// guard. The SMALL class (guard 1024) widens fast-path eligibility to
// shallower stacks for callees whose budget is ≤ 1 KiB; the DEFAULT class
// (guard 4096) is the G2-measured discipline, unchanged.
//
// DeepPathCount is the oracle: it counts deep-path retries (Cross2/3/4 now
// count too — the row-4 diagnostic-parity fix).

import (
	"testing"

	"hybrid.program/hybridge"
)

// fastStackNeedDefault is hybridge's DEFAULT guard (fastStackNeed there is
// package-private; the value is pinned by hybridge's own TestNeedsDeep-
// SentinelShape and gates/G2.md — do not change it here or there without
// re-running the G2 bench).
const fastStackNeedDefault = 4096

// TestSmallClassOnShallowStack: at a controlled headroom inside the
// (SmallGuard, default-guard) window — exactly the range where the two
// classes DISAGREE — the SMALL-class crossing must take the fast path while
// the DEFAULT class must take the deep path. This is the row-4 property:
// shallow-goroutine fan-in stops paying the deep-path cost for tiny callees.
func TestSmallClassOnShallowStack(t *testing.T) {
	var pad [1024]byte
	var sink byte

	// hit runs at a recursion depth whose headroom sits in the window; the
	// margins absorb the trampolines' own frames and the probe's call frame.
	var hit func()
	var descend func(depth int)
	descend = func(depth int) {
		pad[depth%1024]++
		sink = pad[depth%1024]
		h := hybridge.SPHeadroomForTest()
		if h < hybridge.SmallGuard+512 {
			t.Fatalf("descended past the window (headroom %d < %d) without hitting — recursion step too coarse",
				h, hybridge.SmallGuard+512)
		}
		if h < fastStackNeedDefault-512 {
			hit()
			return
		}
		descend(depth + 1)
	}
	hit = func() {
		h := hybridge.SPHeadroomForTest()
		if h >= fastStackNeedDefault-256 || h <= hybridge.SmallGuard+256 {
			t.Fatalf("hit outside the disagreement window: headroom %d", h)
		}

		// SMALL class: headroom > SmallGuard → the fast path, DeepPathCount frozen.
		before := hybridge.DeepPathCount.Load()
		if got := hybridge.Cross1S(FnNop, 42); got != 42 {
			t.Fatalf("Cross1S(42) = %d", got)
		}
		if after := hybridge.DeepPathCount.Load(); after != before {
			t.Fatalf("SMALL class took the deep path at headroom %d (guard %d) — the small trampoline regressed",
				h, hybridge.SmallGuard)
		}

		// DEFAULT class: headroom < 4096 → the deep path, count +1.
		if got := hybridge.Cross1(FnNop, 42); got != 42 {
			t.Fatalf("Cross1(42) = %d", got)
		}
		if after := hybridge.DeepPathCount.Load(); after != before+1 {
			t.Fatalf("DEFAULT class did not take the deep path at headroom %d (guard 4096): count %d → %d",
				h, before, after)
		}

		// The 2-arg small trampoline passes payloads correctly on the fast path.
		if got := hybridge.Cross2S(FnNop, 7, 0); got != 7 {
			t.Fatalf("Cross2S(7,0) = %d", got)
		}
	}
	descend(0)
	_ = sink
}

// TestSmallClassAfterStackGrowth: the G2 path-proof shape, for the SMALL
// class — after the stack has grown, every crossing (either class) is fast,
// DeepPathCount frozen across both loops.
func TestSmallClassAfterStackGrowth(t *testing.T) {
	var pad [256]byte
	var grow func(depth int) byte
	grow = func(depth int) byte {
		if depth == 0 {
			return pad[0]
		}
		pad[depth%256]++
		return grow(depth-1) + pad[depth%256]
	}
	_ = grow(200)

	before := hybridge.DeepPathCount.Load()
	for i := 0; i < 10_000; i++ {
		if got := hybridge.Cross1S(FnNop, uintptr(i)); got != uint64(i) {
			t.Fatalf("Cross1S(%d) = %d", i, got)
		}
	}
	if after := hybridge.DeepPathCount.Load(); after != before {
		t.Fatalf("DeepPathCount moved %d → %d across a grown-stack SMALL loop: the fast path did not hold",
			before, after)
	}
}

// TestStackAlignmentContract (row 17, fleet-found): the Win64 fast-path
// trampolines must keep RSP 16-aligned at the CALL — a misaligned-8 callee
// frame crashed the first `movaps` in gcc-built sha3 (the fleet bisected
// the 0xc0000005 to TestStreamChecksumDeterministic, then to
// hy_sha3_digest256+0x5c; two fixed-sub attempts each failed on a
// different callee because Go's ABI0 entry residue VARIES with the
// caller's frame). The probe returns a 16-byte-aligned local's address
// mod 16: 0 = the ABI held, 8 = the frame is misaligned. Runs on every
// platform through the exact fast trampoline shapes the small guard uses.
func TestStackAlignmentContract(t *testing.T) {
	if got := hybridge.Cross1S(FnAlign, 0); got != 0 {
		t.Fatalf("Cross1S: callee frame misaligned by %d (Win64 ABI contract broken)", got)
	}
	if got := hybridge.Cross2S(FnAlign, 0, 0); got != 0 {
		t.Fatalf("Cross2S: callee frame misaligned by %d", got)
	}
	if got := hybridge.CrossDeep1(FnAlign, 0); got != 0 {
		t.Fatalf("CrossDeep1: callee frame misaligned by %d", got)
	}
}
