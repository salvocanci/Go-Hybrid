// Package hybridge: the Spike 3 Go side of the boundary —
//   - a Go-owned handle table (owning-side table: keeps objects alive, hands
//     out integer ids only — the WIT own/borrow shape from research/wit-abi.md);
//   - typed wrappers over the Rust hyarena API (generation-tagged ids);
//   - the pinned-borrow protocol the bridge generator will emit:
//     Pin -> cross -> Unpin + KeepAlive (never a raw pointer outliving a call).
//
// Read paths on the handle table are LOCK-FREE (state word per slot, written
// before the slot goes live with release semantics); the freelist is guarded
// by a mutex (alloc path only). ABA on concurrent Release/re-Acquire of the
// same id is out of scope for the spike (documented; production adds epochs).
package hybridge

import (
	"runtime"
	"sync"
	"sync/atomic"
	"unsafe"

	"spike3/golink"
)

// Invalid is the Rust-side sentinel (u64::MAX): unknown/released/stale id.
const Invalid = uint64(0xFFFFFFFFFFFFFFFF)

// ------------------------------------------------------------ asm trampolines

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

// SPHeadroomForTest exposes the stackguard headroom for the offsets canary test.
func SPHeadroomForTest() uintptr { return spHeadroom() }

// fastStackNeed: headroom required to run a callee on the caller's own
// goroutine stack. Callees must have BOUNDED stack use (the production bridge
// descriptor carries a per-fn stack budget; unbounded callees take the deep
// path unconditionally).
const fastStackNeed = 4096

// needsDeep: sentinel returned by the fast trampoline when headroom is short
// (production design uses a flag register instead of a value sentinel).
const needsDeep = ^uint64(1)

// cross1/2/3: the generated crossing. Fast path = caller's stack (guard
// checked IN the trampoline); deep path = pooled guarded mmap stack.
func cross1(fn unsafe.Pointer, a1 uintptr) uint64 {
	v := callFast1(fn, a1)
	if v == needsDeep {
		i := acquireDeep()
		v = callDeep1(fn, a1, deepTops[i])
		releaseDeep(i)
	}
	return v
}

func cross2(fn unsafe.Pointer, a1, a2 uintptr) uint64 {
	v := callFast2(fn, a1, a2)
	if v == needsDeep {
		i := acquireDeep()
		v = callDeep2(fn, a1, a2, deepTops[i])
		releaseDeep(i)
	}
	return v
}

func cross3(fn unsafe.Pointer, a1, a2, a3 uintptr) uint64 {
	v := callFast3(fn, a1, a2, a3)
	if v == needsDeep {
		i := acquireDeep()
		v = callDeep3(fn, a1, a2, a3, deepTops[i])
		releaseDeep(i)
	}
	return v
}

// crossDeep1: ALWAYS the pooled stack — for callees with unbounded stack use
// (deep recursion, unknown budgets).
func crossDeep1(fn unsafe.Pointer, a1 uintptr) uint64 {
	i := acquireDeep()
	v := callDeep1(fn, a1, deepTops[i])
	releaseDeep(i)
	return v
}

// ------------------------------------------------------------ Go handle table

// Handle is an integer referring to a Go-owned object. Zero is invalid.
type Handle uint64

const tableCap = 1 << 18 // 262,144 slots (spike sizing; P5 uses 100k)

type hslot struct {
	val   any
	state int32 // 0 = dead, 1 = live (atomic; val written before live)
}

var (
	tabMu   sync.Mutex // guards freelist + fresh-index counter only
	tab     = make([]hslot, tableCap)
	tabFr   []uint32 // recycled slot indices
	tabNext uint32   // next never-used index
	tabLive int32
)

// Acquire adds v to the table; the table keeps v alive until Release.
func Acquire(v any) Handle {
	tabMu.Lock()
	var i uint32
	if n := len(tabFr); n > 0 {
		i = tabFr[n-1]
		tabFr = tabFr[:n-1]
	} else if tabNext < tableCap {
		i = tabNext
		tabNext++
	} else {
		tabMu.Unlock()
		panic("spike3: handle table full")
	}
	tabMu.Unlock()
	tab[i].val = v
	atomic.StoreInt32(&tab[i].state, 1) // release: val visible before live
	atomic.AddInt32(&tabLive, 1)
	return Handle(uint64(i) + 1)
}

// Get returns the object for a live handle. Lock-free; correct while the
// caller owns the id (or the owner guarantees no concurrent Release).
func Get(h Handle) (any, bool) {
	if h == 0 || uint64(h) > uint64(len(tab)) {
		return nil, false
	}
	s := &tab[uint64(h)-1]
	if atomic.LoadInt32(&s.state) != 1 { // acquire: see val only if live
		return nil, false
	}
	return s.val, true
}

// Release drops the table's reference; the object may then be collected.
func Release(h Handle) bool {
	if h == 0 || uint64(h) > uint64(len(tab)) {
		return false
	}
	s := &tab[uint64(h)-1]
	if !atomic.CompareAndSwapInt32(&s.state, 1, 0) {
		return false
	}
	s.val = nil
	tabMu.Lock()
	tabFr = append(tabFr, uint32(h-1))
	tabMu.Unlock()
	atomic.AddInt32(&tabLive, -1)
	return true
}

// LiveHandles reports the number of live table entries.
func LiveHandles() int32 { return atomic.LoadInt32(&tabLive) }

// ------------------------------------------------------------ Rust object API

// RustObj is the Go-side wrapper of a Rust-owned hyarena object. Its id is
// generation-tagged: releasing twice (explicit + cleanup) is detected by CAS
// locally, and a STALE release on a reused Rust slot reads as INVALID on the
// Rust side instead of corrupting the new object.
type RustObj struct {
	id       uint64
	released int32 // CAS guard: 0 live, 1 released
}

// NewRustObj creates a Rust-owned object (rc=1 on the Rust side) and installs
// a cleanup so the Rust reference is released when the wrapper becomes
// unreachable (SPEC §12 finalizer rule: safe to run late, idempotent).
func NewRustObj(init uint64) *RustObj {
	id := cross1(golink.FnObjCreate, uintptr(init))
	o := &RustObj{id: id}
	runtime.AddCleanup(o, releaseRustObj, id)
	return o
}

func releaseRustObj(id uint64) { cross1(golink.FnObjRelease, uintptr(id)) }

// Get reads the payload through the boundary (crossing + id resolve).
func (o *RustObj) Get() uint64 { return cross1(golink.FnObjGet, uintptr(o.id)) }

// Retain bumps the Rust-side refcount (both sides now hold references).
func (o *RustObj) Retain() uint64 { return cross1(golink.FnObjRetain, uintptr(o.id)) }

// Release drops the Go side's reference exactly once (CAS); the Rust object
// dies only when its own references are gone too.
func (o *RustObj) Release() bool {
	if !atomic.CompareAndSwapInt32(&o.released, 0, 1) {
		return false
	}
	releaseRustObj(o.id)
	return true
}

// ID exposes the raw generation-tagged id (for probes/benches only).
func (o *RustObj) ID() uint64 { return o.id }

// -------------------------------------------------------- raw extern helpers

func ObjGet(id uint64) uint64        { return cross1(golink.FnObjGet, uintptr(id)) }
func ObjRetain(id uint64) uint64     { return cross1(golink.FnObjRetain, uintptr(id)) }
func ObjRelease(id uint64) uint64    { return cross1(golink.FnObjRelease, uintptr(id)) }
func ViewHold(p uintptr) uint64      { return cross1(golink.FnViewHold, p) }
func ViewHoldStack(p uintptr) uint64 { return cross1(golink.FnViewHoldStack, p) }
func ViewRead(id uint64) uint64      { return cross1(golink.FnViewRead, uintptr(id)) }
func ViewRelease(id uint64) uint64   { return cross1(golink.FnViewRelease, uintptr(id)) }
func ArenaScopeEnter() uint64        { return cross1(golink.FnArenaEnter, 0) }
func ArenaSlot(s, v uint64) uint64   { return cross2(golink.FnArenaSlot, uintptr(s), uintptr(v)) }
func ArenaSlotRead(s uint64) uint64  { return cross1(golink.FnArenaSlotRead, uintptr(s)) }
func ArenaScopeExit(s uint64) uint64 { return cross1(golink.FnArenaExit, uintptr(s)) }
func LiveObjects() uint64            { return cross1(golink.FnStatsObj, 0) }
func LiveViews() uint64              { return cross1(golink.FnStatsView, 0) }
func LiveArenaSlots() uint64         { return cross1(golink.FnStatsArena, 0) }
func AllocLiveBytes() int64 {
	return int64(cross1(golink.FnStatsAlloc, 0))
}
func Add(a, b uint64) uint64 { return cross2(golink.FnAdd, uintptr(a), uintptr(b)) }

// BenchObjGet runs the Rust-side id-resolve loop internally (P4 reference).
func BenchObjGet(iters, id uint64) uint64 {
	return cross2(golink.FnBenchObjGet, uintptr(iters), uintptr(id))
}

// DeepRec: deep-recursion callee that ONLY runs on the pooled guarded stacks
// (unbounded stack use class — the generator's always-deep path).
func DeepRec(depth uint64) uint64 {
	return crossDeep1(golink.FnDeepRec, uintptr(depth))
}

// ------------------------------------------------------------ pinned borrows

// SumPinned: the SAFE borrow protocol (what the bridge generator emits) —
// pin the backing array, cross with ptr+len for ONE call, unpin, keep alive.
func SumPinned(b []uint64) uint64 {
	if len(b) == 0 {
		return 0
	}
	var p runtime.Pinner
	p.Pin(&b[0]) // pins the backing array; it cannot move or be freed
	v := cross2(golink.FnSumSlice, uintptr(unsafe.Pointer(&b[0])), uintptr(len(b)))
	p.Unpin()
	runtime.KeepAlive(&p) // pinner alive across the call (belt and braces)
	runtime.KeepAlive(b)
	return v
}

// SumRaw: the measurement-only variant WITHOUT pinning (the caller keeps the
// slice alive by holding it — legal for a bench, NOT the generated protocol).
func SumRaw(b []uint64) uint64 {
	if len(b) == 0 {
		return 0
	}
	v := cross2(golink.FnSumSlice, uintptr(unsafe.Pointer(&b[0])), uintptr(len(b)))
	runtime.KeepAlive(b)
	return v
}

// ReadPinnedU64 pins a single u64 for one read call (P3 single-element leg).
func ReadPinnedU64(v *uint64) uint64 {
	var p runtime.Pinner
	p.Pin(v)
	out := cross1(golink.FnReadU64, uintptr(unsafe.Pointer(v)))
	p.Unpin()
	runtime.KeepAlive(&p)
	runtime.KeepAlive(v)
	return out
}
