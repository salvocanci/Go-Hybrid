// Package hybridge — the Hybrid runtime's boundary core (Phase 2).
//
// Lifted from Spike 3's working code (spikes/spike3-memory/work/go/hybridge),
// which passed its pre-registered thresholds both tiers (sandbox + Kaggle
// worker). The spike's handle-table / arena / probe machinery is NOT part of
// the runtime — per-crate bindings live in their own packages and use only:
//
//   - Cross1/2/3: the guarded crossing (fast path on the caller's goroutine
//     stack after an IN-TRAMPOLINE stackguard check; deep path on a pooled
//     1 MiB guarded mmap stack when headroom is short);
//   - the pinned-borrow protocol (runtime.Pinner pin → cross → unpin +
//     KeepAlive) that every binding emits around pointer-typed arguments.
//
// Trampoline discipline (both paths — the rules the bridge generator emits):
//  1. all Go-frame inputs loaded BEFORE any SP adjustment;
//  2. old SP saved in a SysV callee-saved register (RBX), restored BEFORE
//     writing results;
//  3. 16-byte SysV alignment at callee entry (rsp%16==8);
//  4. NOSPLIT: no Go stack growth inside the trampoline;
//  5. no callbacks into Go while on a deep stack; panics abort at the Rust
//     edge (E9) — they never unwind across.
package hybridge

import (
	"sync/atomic"
	"unsafe"
)

//go:noescape
func spHeadroom() uintptr

//go:noescape
func callFast1(fn unsafe.Pointer, a1 uintptr) uint64

//go:noescape
func callFast2(fn unsafe.Pointer, a1, a2 uintptr) uint64

//go:noescape
func callFast3(fn unsafe.Pointer, a1, a2, a3 uintptr) uint64

//go:noescape
func callDeep1(fn unsafe.Pointer, a1 uintptr, stack uintptr) uint64

//go:noescape
func callDeep2(fn unsafe.Pointer, a1, a2 uintptr, stack uintptr) uint64

//go:noescape
func callDeep3(fn unsafe.Pointer, a1, a2, a3 uintptr, stack uintptr) uint64

// fastStackNeed: headroom required to run a callee on the caller's own
// goroutine stack. Callees must have BOUNDED stack use (the descriptor
// carries a per-fn stack budget; unbounded callees take the deep path).
const fastStackNeed = 4096

// needsDeep: sentinel returned by the fast trampoline when headroom is short.
const needsDeep = ^uint64(1)

// Cross1/2/3: the generated crossing. Fast path = caller's stack (guard
// checked IN the trampoline); deep path = pooled guarded mmap stack.

// DeepPathCount — G2 diagnostic (Batch J): how many crossings took the deep
// path. Cold-path atomic (the fast path pays NOTHING); the overhead bench
// reads it to prove which path its number measures. Production code never
// consults it.
var DeepPathCount atomic.Uint64

// DeepCrossCount — row-4 diagnostic: how many crossings took the ALWAYS-deep
// route (CrossDeep1..4 — the class-ledger DEEP class). DeepPathCount only
// sees fast-path RETRIES; the ledger's DEEP class never touches the fast
// trampoline, so this counter is its oracle (tests + the descriptors ledger
// assert on it). Cold-path atomic, same reasoning as DeepPathCount.
var DeepCrossCount atomic.Uint64

// Cross1Raw — DIAGNOSTIC ONLY (G2 bench): the fast trampoline WITHOUT the
// deep-path retry. Returns the needsDeep sentinel when headroom is short —
// callers MUST check; production must use Cross1.
func Cross1Raw(fn unsafe.Pointer, a1 uintptr) uint64 {
	return callFast1(fn, a1)
}

func Cross1(fn unsafe.Pointer, a1 uintptr) uint64 {
	v := callFast1(fn, a1)
	if v == needsDeep {
		DeepPathCount.Add(1)
		i := acquireDeep()
		v = callDeep1(fn, a1, deepTops[i])
		releaseDeep(i)
	}
	return v
}

func Cross2(fn unsafe.Pointer, a1, a2 uintptr) uint64 {
	v := callFast2(fn, a1, a2)
	if v == needsDeep {
		DeepPathCount.Add(1) // diagnostic parity: Cross1 counted; 2-4 were silent before row 4
		i := acquireDeep()
		v = callDeep2(fn, a1, a2, deepTops[i])
		releaseDeep(i)
	}
	return v
}

func Cross3(fn unsafe.Pointer, a1, a2, a3 uintptr) uint64 {
	v := callFast3(fn, a1, a2, a3)
	if v == needsDeep {
		DeepPathCount.Add(1) // diagnostic parity with Cross1 (see row 4)
		i := acquireDeep()
		v = callDeep3(fn, a1, a2, a3, deepTops[i])
		releaseDeep(i)
	}
	return v
}

// CrossDeep1: ALWAYS the pooled stack — for callees with unbounded stack use.
func CrossDeep1(fn unsafe.Pointer, a1 uintptr) uint64 {
	DeepCrossCount.Add(1)
	i := acquireDeep()
	v := callDeep1(fn, a1, deepTops[i])
	releaseDeep(i)
	return v
}

// CrossDeep2..4: the always-pooled crossings for higher arities (row 4's
// class ledger routes recursive serde_json fns here — parse/clone/drop/
// serialize walk the value tree, so no guard number is ever a sound bound).
func CrossDeep2(fn unsafe.Pointer, a1, a2 uintptr) uint64 {
	DeepCrossCount.Add(1)
	i := acquireDeep()
	v := callDeep2(fn, a1, a2, deepTops[i])
	releaseDeep(i)
	return v
}

func CrossDeep3(fn unsafe.Pointer, a1, a2, a3 uintptr) uint64 {
	DeepCrossCount.Add(1)
	i := acquireDeep()
	v := callDeep3(fn, a1, a2, a3, deepTops[i])
	releaseDeep(i)
	return v
}

func CrossDeep4(fn unsafe.Pointer, a1, a2, a3, a4 uintptr) uint64 {
	DeepCrossCount.Add(1)
	i := acquireDeep()
	v := callDeep4(fn, a1, a2, a3, a4, deepTops[i])
	releaseDeep(i)
	return v
}

// SPHeadroomForTest exposes the stackguard headroom for the offsets canary.
func SPHeadroomForTest() uintptr { return spHeadroom() }

//go:noescape
func callFast4(fn unsafe.Pointer, a1, a2, a3, a4 uintptr) uint64

//go:noescape
func callDeep4(fn unsafe.Pointer, a1, a2, a3, a4 uintptr, stack uintptr) uint64

func Cross4(fn unsafe.Pointer, a1, a2, a3, a4 uintptr) uint64 {
	v := callFast4(fn, a1, a2, a3, a4)
	if v == needsDeep {
		DeepPathCount.Add(1) // diagnostic parity with Cross1 (see row 4)
		i := acquireDeep()
		v = callDeep4(fn, a1, a2, a3, a4, deepTops[i])
		releaseDeep(i)
	}
	return v
}

// SmallGuard: the headroom the SMALL-class trampolines require. Callees whose
// descriptor budget is <= 1 KiB (bounded, non-recursive — the class ledger
// lives in interfaces/descriptors.md with per-fn justification) take the fast
// path on shallower stacks than the default 4096 B guard allows: a fresh
// goroutine (2 KiB min stack) fan-in no longer pays the pooled deep path for
// tiny callees. (Row 4, gates/G2.md follow-up #2.)
const SmallGuard = 1024

//go:noescape
func callFast1S(fn unsafe.Pointer, a1 uintptr) uint64

//go:noescape
func callFast2S(fn unsafe.Pointer, a1, a2 uintptr) uint64

//go:noescape
func callFast3S(fn unsafe.Pointer, a1, a2, a3 uintptr) uint64

//go:noescape
func callFast4S(fn unsafe.Pointer, a1, a2, a3, a4 uintptr) uint64

// Cross1S..4S: the SMALL-class crossings — same deep-path retry, same
// DeepPathCount diagnostic; only the in-trampoline guard differs (1024 vs
// 4096). The default-class crossings are untouched so G2's measured evidence
// stays valid.
func Cross1S(fn unsafe.Pointer, a1 uintptr) uint64 {
	v := callFast1S(fn, a1)
	if v == needsDeep {
		DeepPathCount.Add(1)
		i := acquireDeep()
		v = callDeep1(fn, a1, deepTops[i])
		releaseDeep(i)
	}
	return v
}

func Cross2S(fn unsafe.Pointer, a1, a2 uintptr) uint64 {
	v := callFast2S(fn, a1, a2)
	if v == needsDeep {
		DeepPathCount.Add(1)
		i := acquireDeep()
		v = callDeep2(fn, a1, a2, deepTops[i])
		releaseDeep(i)
	}
	return v
}

func Cross3S(fn unsafe.Pointer, a1, a2, a3 uintptr) uint64 {
	v := callFast3S(fn, a1, a2, a3)
	if v == needsDeep {
		DeepPathCount.Add(1)
		i := acquireDeep()
		v = callDeep3(fn, a1, a2, a3, deepTops[i])
		releaseDeep(i)
	}
	return v
}

func Cross4S(fn unsafe.Pointer, a1, a2, a3, a4 uintptr) uint64 {
	v := callFast4S(fn, a1, a2, a3, a4)
	if v == needsDeep {
		DeepPathCount.Add(1)
		i := acquireDeep()
		v = callDeep4(fn, a1, a2, a3, a4, deepTops[i])
		releaseDeep(i)
	}
	return v
}
