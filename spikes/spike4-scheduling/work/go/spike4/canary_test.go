package spike4

// Canary + safety tests for the Spike 4 mechanisms. These are the tests the
// race leg runs; the matrix tests (matrix_test.go) are the load data.

import (
	"os"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"spike4/hybridge4"
)

// TestOffsetsCanary pins the go1.26.9 runtime.g.stackguard0 offset the
// trampolines read: headroom must be plausible, must grow when the stack
// grows (the guard tracks the LIVE stack), and must decrease with depth
// within one grown stack (SP really moves down toward the guard).
func TestOffsetsCanary(t *testing.T) {
	h0 := hybridge4.SPHeadroomForTest()
	if h0 < 512 || h0 > 1<<30 {
		t.Fatalf("implausible headroom: %d", h0)
	}
	var hShallow, hDeep uintptr
	var rec func(depth int) uintptr
	rec = func(depth int) uintptr {
		var pad [256]byte
		pad[0] = byte(depth)
		if depth == 4 {
			hShallow = hybridge4.SPHeadroomForTest() // nearer the stack top
		}
		if depth == 2 {
			hDeep = hybridge4.SPHeadroomForTest() // two frames deeper
		}
		if depth <= 0 {
			return 0
		}
		return rec(depth-1) + uintptr(pad[0]) - uintptr(pad[0])
	}
	rec(300) // forces stack growth first (the guard must track the LIVE stack)
	if hShallow == 0 || hDeep == 0 {
		t.Fatal("canary probes never ran")
	}
	if hDeep > hShallow {
		t.Fatalf("headroom must not increase with call depth: depth2=%d depth4=%d", hDeep, hShallow)
	}
}

// TestM2CanaryPReleased proves the linkname'd handoff actually releases the
// P while Rust blocks (S2's core safety claim). Self-calibrating: two spinner
// goroutines under GOMAXPROCS(2); while the third goroutine blocks via M1
// (naive) it holds a P and the spinners share one; via M2b the P is released
// and both spinners run full-speed. M2b's total spin must be much higher.
//
// Steady-state design (the first version was flaky: spinners could start
// before the blocker entered Rust): the blocker runs 3x100 ms blocks; the
// spinners start 20 ms in (mid-block) and spin 300 ms — fully inside the
// blocked window. 3 alternating rounds, verdict on the MEDIAN ratio.
func TestM2CanaryPReleased(t *testing.T) {
	old := runtime.GOMAXPROCS(0)
	defer runtime.GOMAXPROCS(old)
	if old > 2 {
		runtime.GOMAXPROCS(2) // deterministic on the 4-core worker too
	}

	spin := func(ms int) uint64 {
		var total uint64
		var wg sync.WaitGroup
		for i := 0; i < 2; i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				deadline := time.Now().Add(time.Duration(ms) * time.Millisecond)
				var c uint64
				x := uint64(1)
				for time.Now().Before(deadline) {
					for j := 0; j < 10000; j++ {
						x = x*1664525 + 1013904223
					}
					c++
				}
				atomic.AddUint64(&total, c*10000+x*0)
			}()
		}
		wg.Wait()
		return atomic.LoadUint64(&total)
	}

	// run spins for 300 ms while (optionally) a third goroutine blocks in
	// Rust via `block` (3 x 100 ms, started 20 ms before the spin window).
	// block == nil measures the ENVIRONMENTAL CEILING: two spinners, no
	// blocker — whatever the box/cgroup actually delivers for 2 busy
	// threads. Every assertion below is relative to that floor, so the
	// test self-calibrates against cgroup quotas, steal, and frequency
	// caps (measured ceiling on this sandbox: ~1.5x, NOT 2.0x).
	run := func(block func()) (iters uint64, cpuDelta int64) {
		var wg sync.WaitGroup
		if block != nil {
			wg.Add(1)
			go func() {
				defer wg.Done()
				var pad [32768]byte // real call depth: syswin headroom (see cell.go)
				pad[0] = 1
				for i := 0; i < 3; i++ {
					block() // 3 x 100 ms inside Rust
				}
				_ = pad[0]
			}()
		}
		time.Sleep(20 * time.Millisecond) // blocker (if any) is mid-block now
		u0, s0 := cpuTicks()
		s := spin(300)
		u1, s1 := cpuTicks()
		wg.Wait()
		return s, (u1 - u0) + (s1 - s0)
	}

	// Pre-registered on the self-calibrating form (Decision Log 2026-10-12):
	//   floor  = 2 spinners, no blocker   (the achievable ceiling C)
	//   naive  = M1 blocker holds a P     -> must sit at <= 0.75 x C
	//   syswin = M2b blocker releases it  -> must recover >= 0.80 x C
	//   and    syswin >= 1.25 x naive
	var floorCPU, naiveCPU, syswinCPU int64
	var floorIter, naiveIter, syswinIter uint64
	for r := 0; r < 3; r++ {
		fi, fc := run(nil)
		ni, nc := run(func() { hybridge4.BlockMs(100) })
		si, sc := run(func() { hybridge4.BlockViaSyswin(100, true) })
		t.Logf("round %d: floor=%dt naive=%dt(%.2fxC) syswin=%dt(%.2fxC) | iters %d/%d/%d",
			r+1, fc, nc, float64(nc)/float64(fc), sc, float64(sc)/float64(fc), fi, ni, si)
		floorCPU += fc
		naiveCPU += nc
		syswinCPU += sc
		floorIter += fi
		naiveIter += ni
		syswinIter += si
	}
	fF, fN, fS := float64(floorCPU), float64(naiveCPU), float64(syswinCPU)
	t.Logf("totals: floor=%dt naive=%dt syswin=%dt | naive/floor=%.2f syswin/floor=%.2f syswin/naive=%.2f | iters syswin/naive=%.2f",
		floorCPU, naiveCPU, syswinCPU, fN/fF, fS/fF, fS/fN, float64(syswinIter)/float64(naiveIter))
	if fS < 0.80*fF {
		t.Fatalf("M2b did not recover the ceiling: syswin/floor %.2f < 0.80", fS/fF)
	}
	if fN > 0.75*fF {
		t.Fatalf("M1 naive unexpectedly high (no starvation visible?): naive/floor %.2f > 0.75", fN/fF)
	}
	if fS < 1.25*fN {
		t.Fatalf("M2b not clearly above naive: syswin/naive %.2f < 1.25", fS/fN)
	}
}

// cpuTicks reads utime+stime (clock ticks) from /proc/self/stat.
func cpuTicks() (utime, stime int64) {
	b, err := os.ReadFile("/proc/self/stat")
	if err != nil {
		return 0, 0
	}
	s := string(b)
	if i := strings.LastIndex(s, ")"); i >= 0 {
		s = s[i+2:]
	} else {
		return 0, 0
	}
	f := strings.Fields(s)
	if len(f) < 13 {
		return 0, 0
	}
	utime, _ = strconv.ParseInt(f[11], 10, 64) // field 14 overall
	stime, _ = strconv.ParseInt(f[12], 10, 64) // field 15 overall
	return utime, stime
}

// TestM2NoDeadlock interleaves both syswin variants with GC pressure and
// GOMAXPROCS churn — the enter/exit window must never wedge or crash.
func TestM2NoDeadlock(t *testing.T) {
	var wg sync.WaitGroup
	stop := make(chan struct{})

	wg.Add(1)
	go func() { // GC hammer during the whole test
		defer wg.Done()
		for i := 0; i < 40; i++ {
			runtime.GC()
			select {
			case <-stop:
				return
			case <-time.After(5 * time.Millisecond):
			}
		}
	}()

	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			var pad [32768]byte // syswin headroom (see cell.go)
			pad[0] = byte(i)
			for j := 0; j < 100; j++ {
				d := uint64(j % 2) // 0 or 1 ms
				if j%2 == 0 {
					hybridge4.BlockViaSyswin(d, true)
				} else {
					hybridge4.BlockViaSyswin(d, false)
				}
			}
			_ = pad[0]
		}(i)
	}
	// GOMAXPROCS churn (Ms and Ps come and go around the window)
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := 0; i < 20; i++ {
			select {
			case <-stop:
				return
			default:
			}
			runtime.GOMAXPROCS(1 + i%2)
			time.Sleep(2 * time.Millisecond)
		}
		runtime.GOMAXPROCS(2)
	}()
	// let the churner finish, then signal GC hammer
	time.Sleep(60 * time.Millisecond)
	// wait for the 8 workers (churner included above)
	wgDone := make(chan struct{})
	go func() { wg.Wait(); close(wgDone) }()
	select {
	case <-wgDone:
	case <-time.After(30 * time.Second):
		t.Fatal("M2 deadlock detected (workers did not finish in 30s)")
	}
}

// TestPoolRoundTrip: sequential pool calls complete with correct values.
func TestPoolRoundTrip(t *testing.T) {
	for i := 0; i < 100; i++ {
		v := hybridge4.BlockViaPool(1)
		if v != 1 {
			t.Fatalf("pool round trip %d: got %d want 1", i, v)
		}
	}
	if n := hybridge4.PoolThreads(); n == 0 {
		t.Fatal("pool has zero threads")
	}
}

// TestPoolNoTicketLoss: 1000 concurrent pool calls, all must return
// (the S4 "zero lost tickets" precondition at small scale).
func TestPoolNoTicketLoss(t *testing.T) {
	const n = 1000
	var wg sync.WaitGroup
	var ret int32
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			hybridge4.BlockViaPool(1)
			atomic.AddInt32(&ret, 1)
		}()
	}
	done := make(chan struct{})
	go func() { wg.Wait(); close(done) }()
	select {
	case <-done:
	case <-time.After(30 * time.Second):
		t.Fatal("pool lost tickets: not all 1000 returned in 30s")
	}
	if int(ret) != n {
		t.Fatalf("returned %d of %d", ret, n)
	}
}
