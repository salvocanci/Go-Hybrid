// Spike 3 benchmarks (thresholds P1-P4 in ../RESULTS.md).
package spike3

import (
	"runtime"
	"runtime/cgo"
	"testing"

	"spike3/hybridge"
)

// P1: Go-side handle create + release (one stable object, table ops only).
func BenchmarkGoTableCreateRelease(b *testing.B) {
	v := new(uint64)
	*v = 1
	for i := 0; i < b.N; i++ {
		h := hybridge.Acquire(v)
		hybridge.Release(h)
	}
}

// P2: Go-side handle get (lock-free read path).
func BenchmarkGoTableGet(b *testing.B) {
	v := new(uint64)
	h := hybridge.Acquire(v)
	defer hybridge.Release(h)
	for i := 0; i < b.N; i++ {
		got, ok := hybridge.Get(h)
		if !ok {
			b.Fatal("get failed")
		}
		_ = got
	}
}

// cgo.Handle comparison for P1/P2 (the stdlib indirection, needs a crossing
// to create but is a plain map read to use).
func BenchmarkCgoHandleNewDelete(b *testing.B) {
	v := new(uint64)
	for i := 0; i < b.N; i++ {
		h := cgo.NewHandle(v)
		h.Delete()
	}
}

func BenchmarkCgoHandleValue(b *testing.B) {
	v := new(uint64)
	h := cgo.NewHandle(v)
	defer h.Delete()
	for i := 0; i < b.N; i++ {
		_ = h.Value()
	}
}

// M4 baseline replica: one guarded-stack crossing, add.
func BenchmarkCallAdd(b *testing.B) {
	for i := 0; i < b.N; i++ {
		hybridge.Add(uint64(i), 1)
	}
}

// P3 legs: 1-element borrow crossing, unpinned vs pinned.
func BenchmarkSumRaw1(b *testing.B) {
	buf := []uint64{42}
	for i := 0; i < b.N; i++ {
		if got := hybridge.SumRaw(buf); got != 42 {
			b.Fatal("sum mismatch")
		}
	}
}

func BenchmarkSumPinned1(b *testing.B) {
	buf := []uint64{42}
	for i := 0; i < b.N; i++ {
		if got := hybridge.SumPinned(buf); got != 42 {
			b.Fatal("sum mismatch")
		}
	}
}

// Larger buffer (8KiB) to show the borrow cost is length-dominated.
func BenchmarkSumPinned1024(b *testing.B) {
	buf := make([]uint64, 1024)
	for i := range buf {
		buf[i] = uint64(i)
	}
	for i := 0; i < b.N; i++ {
		hybridge.SumPinned(buf)
	}
}

// Crossing + Rust-side id resolve (per-op through the boundary).
func BenchmarkObjGetCross(b *testing.B) {
	o := hybridge.NewRustObj(7)
	defer o.Release()
	for i := 0; i < b.N; i++ {
		if o.Get() != 7 {
			b.Fatal("get mismatch")
		}
	}
}

// P4 reference: the resolve loop runs INSIDE Rust (1<<20 iterations per op);
// divide ns/op by 1048576 in analysis to get per-resolve ns.
const rustInner = 1 << 20

func BenchmarkRustSideObjGet(b *testing.B) {
	o := hybridge.NewRustObj(9)
	defer o.Release()
	for i := 0; i < b.N; i++ {
		hybridge.BenchObjGet(rustInner, o.ID())
	}
}

// Rust-object create + release round trip through the boundary.
func BenchmarkRustObjCreateRelease(b *testing.B) {
	for i := 0; i < b.N; i++ {
		o := hybridge.NewRustObj(uint64(i))
		o.Release()
	}
	runtime.KeepAlive(nil)
}

// Scoped arena: slot alloc + read + scope exit per op.
func BenchmarkArenaScopedSlot(b *testing.B) {
	for i := 0; i < b.N; i++ {
		s := hybridge.ArenaScopeEnter()
		sl := hybridge.ArenaSlot(s, uint64(i))
		hybridge.ArenaSlotRead(sl)
		hybridge.ArenaScopeExit(s)
	}
}
