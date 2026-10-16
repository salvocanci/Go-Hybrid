// Spike 3 probe suite (see ../RESULTS.md for the pre-registered thresholds).
//
// Safe probes run under -race. The hazard probes (P7/P8) are deliberate
// use-after-free/dangling-stack demonstrations and are gated behind
// SPIKE3_UNSAFE=1 (never run with -race).
package spike3

import (
	"fmt"
	"os"
	"runtime"
	"sync"
	"sync/atomic"
	"testing"
	"time"
	"unsafe"

	"spike3/hybridge"
)

// ---------------------------------------------------------------- sanity

func TestTrampolineSanity(t *testing.T) {
	if got := hybridge.Add(2, 40); got != 42 {
		t.Fatalf("Add(2,40) = %d", got)
	}
}

// TestConcurrentCrossing is the REGRESSION for the shared-stack collision
// crash: multiple cleanup goroutines crossing simultaneously on different Ms
// overwrote each other's Rust frames on Spike 1's single mmap stack. The new
// crossing runs shallow callees on each goroutine's OWN stack, so this must
// stay green under -race with GOMAXPROCS>1.
func TestConcurrentCrossing(t *testing.T) {
	const g = 8
	const per = 5000
	var wg sync.WaitGroup
	errCh := make(chan error, g)
	for k := 0; k < g; k++ {
		wg.Add(1)
		go func(k int) {
			defer wg.Done()
			for i := 0; i < per; i++ {
				a, b := uint64(k)*1000+uint64(i), uint64(i)
				if got := hybridge.Add(a, b); got != a+b {
					errCh <- fmt.Errorf("g%d: Add(%d,%d)=%d", k, a, b, got)
					return
				}
				if got := hybridge.LiveObjects(); got != hybridge.Invalid && got > 1<<30 {
					errCh <- fmt.Errorf("g%d: bogus stats", k)
					return
				}
			}
		}(k)
	}
	wg.Wait()
	select {
	case err := <-errCh:
		t.Fatal(err)
	default:
	}
}

// TestDeepRecursionPooledStack: 10k-deep Rust recursion (~0.9 MiB of frames)
// must survive on the pooled guarded stacks — and would die (or corrupt
// memory) if it ever ran on a goroutine stack.
func TestDeepRecursionPooledStack(t *testing.T) {
	if got := hybridge.DeepRec(10_000); got == hybridge.Invalid {
		t.Fatal("deep recursion returned INVALID")
	}
	// concurrent deep calls: 4 goroutines each 6k deep on DIFFERENT pooled stacks
	var wg sync.WaitGroup
	for k := 0; k < 4; k++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if got := hybridge.DeepRec(6000); got == hybridge.Invalid {
				t.Error("concurrent deep recursion returned INVALID")
			}
		}()
	}
	wg.Wait()
}

// TestRuntimeOffsetsCanary: the trampoline hardcodes go1.26.9 offsets
// (g.stackguard0=16); SP - stackguard0 must be a sane positive number on a
// normal goroutine stack. A Go version bump that moves runtime.g invalidates
// this and the extractor must be re-run.
func TestRuntimeOffsetsCanary(t *testing.T) {
	h := hybridge.SPHeadroomForTest()
	if h < 512 || h > 1<<30 {
		t.Fatalf("implausible stack headroom %d — runtime.g offsets stale?", h)
	}
}

// ---------------------------------------------------------------- T1 / P1 / P2

func TestGoTableBasic(t *testing.T) {
	const n = 100_000
	ids := make([]hybridge.Handle, n)
	vals := make([]*uint64, n)
	seen := make(map[hybridge.Handle]bool, n)

	for i := 0; i < n; i++ {
		v := new(uint64)
		*v = uint64(i)
		vals[i] = v
		ids[i] = hybridge.Acquire(v)
		if ids[i] == 0 {
			t.Fatalf("zero id at %d", i)
		}
		if seen[ids[i]] {
			t.Fatalf("duplicate live id %d", ids[i])
		}
		seen[ids[i]] = true
	}
	if got := hybridge.LiveHandles(); got != n {
		t.Fatalf("live = %d, want %d", got, n)
	}
	for i := 0; i < n; i++ {
		v, ok := hybridge.Get(ids[i])
		if !ok || v.(*uint64) != vals[i] || *v.(*uint64) != uint64(i) {
			t.Fatalf("Get(%d) mismatch at %d", ids[i], i)
		}
	}
	for i := 0; i < n; i++ {
		if !hybridge.Release(ids[i]) {
			t.Fatalf("Release(%d) failed", ids[i])
		}
		if _, ok := hybridge.Get(ids[i]); ok {
			t.Fatalf("Get after Release at %d still live", i)
		}
	}
	if got := hybridge.LiveHandles(); got != 0 {
		t.Fatalf("live after release-all = %d, want 0", got)
	}
	// double release must fail cleanly
	if hybridge.Release(ids[0]) {
		t.Fatalf("double Release succeeded")
	}
}

// ---------------------------------------------------------------- T2 / P3

func TestPinnedBorrowUnderGCHammer(t *testing.T) {
	const n = 50_000
	b := make([]uint64, 16)
	for i := range b {
		b[i] = uint64(i) + 1
	}
	want := uint64(16 * 17 / 2) // sum 1..16

	stop := make(chan struct{})
	var wg sync.WaitGroup
	wg.Add(1)
	go func() { // GC hammer on OTHER goroutines
		defer wg.Done()
		for {
			select {
			case <-stop:
				return
			default:
				runtime.GC()
			}
		}
	}()
	hammer2 := make(chan struct{})
	wg.Add(1)
	go func() { // allocation churn to force heap movement pressure
		defer wg.Done()
		junk := make([][]byte, 0, 4096)
		for i := 0; ; i++ {
			select {
			case <-hammer2:
				return
			default:
			}
			junk = append(junk, make([]byte, 64))
			if len(junk) > 4096 {
				junk = junk[:0]
			}
		}
	}()

	bad := 0
	for i := 0; i < n; i++ {
		if got := hybridge.SumPinned(b); got != want {
			bad++
		}
	}
	close(stop)
	close(hammer2)
	wg.Wait()
	if bad != 0 {
		t.Fatalf("%d/%d pinned reads corrupted under GC hammer", bad, n)
	}
}

// ---------------------------------------------------------------- T5a / P5

func TestDualReleaseExplicit(t *testing.T) {
	const n = 100_000
	objs := make([]*hybridge.RustObj, n)
	for i := range objs {
		objs[i] = hybridge.NewRustObj(uint64(i))
	}
	if got := hybridge.LiveObjects(); got != n {
		t.Fatalf("live after create = %d, want %d", got, n)
	}
	// Rust side holds an extra reference to every EVEN object.
	for i := 0; i < n; i += 2 {
		if rc := objs[i].Retain(); rc != 2 {
			t.Fatalf("retain rc = %d at %d", rc, i)
		}
	}
	// Go side releases everything: odd objects die, even ones survive (rc 2->1).
	for _, o := range objs {
		if !o.Release() {
			t.Fatal("explicit release failed")
		}
	}
	if got := hybridge.LiveObjects(); got != n/2 {
		t.Fatalf("live after Go release = %d, want %d", got, n/2)
	}
	// Rust side drops its references: everything dies.
	for i := 0; i < n; i += 2 {
		if rc := hybridge.ObjRelease(objs[i].ID()); rc != 0 {
			t.Fatalf("rust release rc = %d at %d", rc, i)
		}
	}
	if got := hybridge.LiveObjects(); got != 0 {
		t.Fatalf("live after both sides released = %d, want 0", got)
	}
	// double release (Go CAS) must be a clean no-op
	for _, o := range objs {
		if o.Release() {
			t.Fatal("double explicit release succeeded")
		}
	}
}

// ---------------------------------------------------------------- T5b (cleanup path)

func TestDualReleaseCleanup(t *testing.T) {
	const n = 50_000
	{
		objs := make([]*hybridge.RustObj, n)
		for i := range objs {
			objs[i] = hybridge.NewRustObj(uint64(i) + 1000)
		}
		if got := hybridge.LiveObjects(); got != n {
			t.Fatalf("live after create = %d, want %d", got, n)
		}
		objs = nil // drop all wrappers; cleanups must release the Rust refs
	}
	deadline := secondsFromNow(30)
	for hybridge.LiveObjects() > 0 {
		if deadline() {
			t.Fatalf("cleanups did not drain: live = %d", hybridge.LiveObjects())
		}
		runtime.GC()
		runtime.GC()
		timeSleep(50)
	}
}

// ---------------------------------------------------------------- T6 / P6

func TestUseAfterReleaseSentinel(t *testing.T) {
	o := hybridge.NewRustObj(0xABCD)
	if o.Get() != 0xABCD {
		t.Fatal("payload mismatch")
	}
	id := o.ID()
	o.Release()
	if got := hybridge.ObjGet(id); got != hybridge.Invalid {
		t.Fatalf("read after release = %#x, want INVALID", got)
	}
	// force slot REUSE, then the STALE id must still read INVALID (generation)
	for i := 0; i < 8; i++ {
		n := hybridge.NewRustObj(uint64(i))
		if n.ID() == id {
			// same slot reused under a new generation: expected eventually
			t.Logf("slot reused: old id %#x, new id %#x", id, n.ID())
		}
		if got := hybridge.ObjGet(id); got != hybridge.Invalid {
			t.Fatalf("STALE id read after slot reuse = %#x, want INVALID (gen tag failed)", got)
		}
		if n.Get() != uint64(i) {
			t.Fatal("new object corrupted by stale probes")
		}
		n.Release()
	}
	// stale RELEASE on a reused slot must also be INVALID, not corrupting
	fresh := hybridge.NewRustObj(777)
	if rc := hybridge.ObjRelease(id); rc != hybridge.Invalid {
		t.Fatalf("stale release returned %d, want INVALID", rc)
	}
	if fresh.Get() != 777 {
		t.Fatal("fresh object corrupted by stale release")
	}
	fresh.Release()
}

func TestScopedArena(t *testing.T) {
	outer := hybridge.ArenaScopeEnter()
	s1 := hybridge.ArenaSlot(outer, 11)
	s2 := hybridge.ArenaSlot(outer, 22)
	if hybridge.ArenaSlotRead(s1) != 11 || hybridge.ArenaSlotRead(s2) != 22 {
		t.Fatal("outer slots unreadable")
	}
	inner := hybridge.ArenaScopeEnter()
	i1 := hybridge.ArenaSlot(inner, 33)
	if hybridge.ArenaSlotRead(i1) != 33 {
		t.Fatal("inner slot unreadable")
	}
	if hybridge.ArenaScopeExit(inner) != 0 {
		t.Fatal("inner exit failed")
	}
	if got := hybridge.ArenaSlotRead(i1); got != hybridge.Invalid {
		t.Fatalf("inner slot after scope exit = %#x, want INVALID", got)
	}
	if hybridge.ArenaSlotRead(s1) != 11 {
		t.Fatal("outer slot corrupted by inner exit")
	}
	// LIFO violation: exiting outer while... inner already exited is fine;
	// exiting a bogus scope must fail
	if hybridge.ArenaScopeExit(999) != hybridge.Invalid {
		t.Fatal("bogus scope exit succeeded")
	}
	if hybridge.ArenaScopeExit(outer) != 0 {
		t.Fatal("outer exit failed")
	}
	if got := hybridge.ArenaSlotRead(s1); got != hybridge.Invalid {
		t.Fatalf("outer slot after scope exit = %#x, want INVALID", got)
	}
	if got := hybridge.LiveArenaSlots(); got != 0 {
		t.Fatalf("arena slots after exit = %d, want 0", got)
	}
	// reuse after full exit: same slot ids, values fresh
	o2 := hybridge.ArenaScopeEnter()
	r1 := hybridge.ArenaSlot(o2, 44)
	if hybridge.ArenaSlotRead(r1) != 44 {
		t.Fatal("arena reuse failed")
	}
	hybridge.ArenaScopeExit(o2)
}

// ---------------------------------------------------------------- T9 / P9

func TestConcurrentHandles(t *testing.T) {
	const g = 8
	const per = 10_000
	var wg sync.WaitGroup
	var totalLive int64
	var mu sync.Mutex

	for k := 0; k < g; k++ {
		wg.Add(1)
		go func(k int) {
			defer wg.Done()
			ids := make(map[hybridge.Handle]struct{}, 1024) // LIVE ids only
			liveMax := 0
			for i := 0; i < per; i++ {
				v := new(uint64)
				*v = uint64(k)*per + uint64(i)
				h := hybridge.Acquire(v)
				if _, dup := ids[h]; dup {
					// duplicate among SIMULTANEOUSLY-live ids = real table bug
					t.Errorf("g%d: duplicate LIVE id %d", k, h)
					return
				}
				ids[h] = struct{}{}
				if len(ids) > liveMax {
					liveMax = len(ids)
				}
				got, ok := hybridge.Get(h)
				if !ok || *(got.(*uint64)) != *v {
					t.Errorf("g%d: Get mismatch for %d", k, h)
					return
				}
				hybridge.Release(h)
				delete(ids, h) // released ids are recycled by design
			}
			mu.Lock()
			totalLive += int64(liveMax)
			mu.Unlock()
		}(k)
	}
	wg.Wait()

	// each goroutine's max-live must be at least 1 (and far below per);
	// total acquired ids across the storm are counted via liveMax sums.
	if totalLive < g || totalLive > g*per {
		t.Fatalf("implausible live-max totals: %d", totalLive)
	}
	if got := hybridge.LiveHandles(); got != 0 {
		t.Fatalf("live handles after storm = %d, want 0", got)
	}

	// concurrent Rust-object churn through the boundary, same goroutines
	var wg2 sync.WaitGroup
	var created int64
	for k := 0; k < g; k++ {
		wg2.Add(1)
		go func() {
			defer wg2.Done()
			for i := 0; i < 2000; i++ {
				o := hybridge.NewRustObj(uint64(i))
				if o.Get() != uint64(i) {
					t.Errorf("rust obj get mismatch")
					return
				}
				o.Release()
				atomic.AddInt64(&created, 1)
			}
		}()
	}
	wg2.Wait()
	if created != g*2000 {
		t.Fatalf("created = %d", created)
	}
	if got := hybridge.LiveObjects(); got != 0 {
		t.Fatalf("rust live after churn = %d, want 0", got)
	}
}

// ---------------------------------------------------------------- P7 (hazard)

var escapeSink any

func TestUnpinnedHeapHazard(t *testing.T) {
	if unsafeEnv() != "1" {
		t.Skip("gated: deliberate UB probe; run with SPIKE3_UNSAFE=1 (no -race)")
	}
	b := []uint64{0x1111222233334444, 0x5555666677778888}
	escapeSink = b // force the backing array onto the heap
	vid := hybridge.ViewHold(uintptr(unsafe.Pointer(&b[0])))
	before := hybridge.ViewRead(vid)
	if before != b[0] {
		t.Fatalf("setup wrong: before = %#x", before)
	}
	escapeSink = nil
	b = nil // Rust now holds the ONLY reference, as a raw pointer

	// churn same-size-class allocations so the freed span gets reused
	keep := make([][]uint64, 0, 4096)
	for i := 0; i < 4000; i++ {
		g := make([]uint64, 2)
		g[0] = 0xDEAD0000DEAD0000
		g[1] = uint64(i)
		keep = append(keep, g)
		if i%256 == 0 {
			runtime.GC()
		}
	}
	after := hybridge.ViewRead(vid)
	changed := after != before
	t.Logf("P7: before=%#x after=%#x changed=%v", before, after, changed)
	hybridge.ViewRelease(vid)
	_ = keep
	if !changed {
		t.Log("P7 OBSERVATION: value survived without pinning (non-moving GC or span not reused) — hazard latent, not absent")
	}
}

// ---------------------------------------------------------------- P8 (hazard)

//go:noinline
func captureStackView() (vid uint64, before uint64) {
	var buf [4]uint64
	buf[0] = 0x0BAD0BAD0BAD0BAD
	buf[1] = 0x600D600D600D600D
	buf[2] = 0xFEEDFEEDFEEDFEED
	buf[3] = 0xC0DEC0DEC0DEC0DE
	vid = hybridge.ViewHoldStack(uintptr(unsafe.Pointer(&buf[0])))
	return vid, buf[0]
}

//go:noinline
func stomp(i int) uint64 {
	var buf [4]uint64
	buf[0] = uint64(i) * 3
	buf[1] = uint64(i) + 1
	buf[2] = 0x1111111111111111
	buf[3] = 0x2222222222222222
	return buf[0] + buf[1] + buf[2] + buf[3]
}

func TestStackHazard(t *testing.T) {
	if unsafeEnv() != "1" {
		t.Skip("gated: deliberate UB probe; run with SPIKE3_UNSAFE=1 (no -race)")
	}
	vid, before := captureStackView() // buf's frame is gone now
	var acc uint64
	for i := 0; i < 500; i++ {
		acc += stomp(i)
	}
	after := hybridge.ViewRead(vid)
	changed := after != before
	t.Logf("P8: before=%#x after=%#x changed=%v (acc=%d)", before, after, changed, acc)
	hybridge.ViewRelease(vid)
	if !changed {
		t.Log("P8 OBSERVATION: stack slot not overwritten yet — try deeper churn; hazard latent")
	}
}

// ---------------------------------------------------------------- helpers

func unsafeEnv() string { return os.Getenv("SPIKE3_UNSAFE") }

func secondsFromNow(s int) func() bool {
	deadline := time.Now().Add(time.Duration(s) * time.Second)
	return func() bool { return time.Now().After(deadline) }
}

func timeSleep(ms int) { time.Sleep(time.Duration(ms) * time.Millisecond) }
