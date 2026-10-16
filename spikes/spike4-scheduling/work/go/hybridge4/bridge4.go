// Package hybridge4: the Spike 4 Go side of the boundary — the crossing
// subset needed for scheduling experiments plus the five mechanisms:
//
//	M0  BlockViaGoSleep   (pure-Go baseline; goroutine parks, P is free)
//	M1  BlockMs           (naive: block in Rust on the caller's stack — the R4 hazard)
//	M2a BlockViaSyswin(false)  (entersyscall window: lazy P handoff, sysmon ~20ms)
//	M2b BlockViaSyswin(true)   (entersyscallblock: immediate P handoff)
//	M3  BlockViaPool      (bounded Rust thread pool + ticket poll with park backoff)
//	M4  SpawnDetached     (unbounded thread-per-call; the negative control)
package hybridge4

import (
	"os"
	"strconv"
	"sync/atomic"
	"time"
	"unsafe"

	"spike4/golink4"
	"spike4/rt5"
)

// ------------------------------------------------------------ asm trampolines

//go:noescape
func spHeadroom() uintptr

//go:noescape
func callFast1(fn unsafe.Pointer, a1 uintptr) uint64

//go:noescape
func callFast2(fn unsafe.Pointer, a1, a2 uintptr) uint64

//go:noescape
func callDeep1(fn unsafe.Pointer, a1 uintptr, stack uintptr) uint64

//go:noescape
func callDeep2(fn unsafe.Pointer, a1, a2 uintptr, stack uintptr) uint64

//go:noescape
func callSyswin1(fn unsafe.Pointer, a1 uintptr) uint64

// SPHeadroomForTest exposes the stackguard headroom for the offsets canary.
func SPHeadroomForTest() uintptr { return spHeadroom() }

const (
	fastStackNeed   = 4096 // headroom for the guard-checked fast path
	syswinStackNeed = 8192 // headroom required BEFORE entering the syscall window
	needsDeep       = ^uint64(1)
)

// cross1: guard-checked fast path with pooled-deep bail-out (Spike 3 shape).
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

// ------------------------------------------------------------ mechanisms

// BlockViaGoSleep is M0: park the goroutine the way Go itself would.
func BlockViaGoSleep(ms uint64) uint64 {
	time.Sleep(time.Duration(ms) * time.Millisecond)
	return ms
}

// BlockMs is M1: the naive Spike 3 crossing — Rust blocks on the caller's
// own goroutine stack, holding the P for the whole call (the R4 hazard).
func BlockMs(ms uint64) uint64 {
	return cross1(golink4.FnBlockMs, uintptr(ms))
}

// BlockViaSyswin is M2a/M2b: wrap the blocking crossing in a syscall
// handoff so the P is released while the M sleeps inside Rust.
//
// Sequence (what the generator would emit for descriptor-flagged blocking
// callees):
//  1. pre-check headroom (>= syswinStackNeed): if short, fall back to the
//     pool — NO Go code may run inside the window (stackguard0 is
//     stackPreempt there);
//  2. entersyscall / entersyscallblock;
//  3. callSyswin1: raw aligned NOSPLIT call, no guard read;
//  4. exitsyscall (reacquires a P, possibly a different one).
func BlockViaSyswin(ms uint64, immediate bool) uint64 {
	if spHeadroom() < syswinStackNeed {
		return BlockViaPool(ms) // low-headroom caller: take the pool path
	}
	if immediate {
		rt5.Entersyscallblock()
	} else {
		rt5.Entersyscall()
	}
	v := callSyswin1(golink4.FnBlockMs, uintptr(ms))
	rt5.Exitsyscall()
	return v
}

// pool poll backoff: start 25 us, double, cap 2 ms.
const (
	pollStart = 25 * time.Microsecond
	pollCap   = 2 * time.Millisecond
)

// PoolInit starts the Rust-side bounded pool (idempotent).
func PoolInit(threads uint64) uint64 {
	return cross1(golink4.FnPoolInit, uintptr(threads))
}

// BlockViaPool is M3: submit a blocking job (fn_id=0), park via time.Sleep
// backoff, poll the ticket until done. No Go runtime internals anywhere.
func BlockViaPool(ms uint64) uint64 {
	ticket := cross2(golink4.FnPoolSubmit, 0, uintptr(ms)) // (fn_id=0 blocking, arg=ms)
	if ticket == ^uint64(0) {
		panic("spike4: pool full (262144 outstanding) — pre-registered drop check")
	}
	backoff := pollStart
	for {
		st := cross1(golink4.FnPoolPoll, uintptr(ticket))
		if st == 1 {
			return ms
		}
		if st == ^uint64(0) {
			panic("spike4: INVALID ticket — generation mismatch (bug)")
		}
		time.Sleep(backoff)
		if backoff < pollCap {
			backoff *= 2
			if backoff > pollCap {
				backoff = pollCap
			}
		}
	}
}

// SpawnDetached is M4: one unbounded detached Rust thread per call.
// Returns u64::MAX when the OS refuses the spawn (resource exhaustion —
// the datum this negative control exists to produce).
func SpawnDetached(ms uint64) uint64 {
	return cross1(golink4.FnSpawnDetached, uintptr(ms))
}

// ------------------------------------------------------------ stats + raw

func Add(a, b uint64) uint64 { return cross2(golink4.FnAdd, uintptr(a), uintptr(b)) }

func PoolThreads() uint64 { return cross1(golink4.FnPoolThreads, 0) }
func PoolIdle() uint64    { return cross1(golink4.FnPoolIdle, 0) }
func PoolQdepth() uint64  { return cross1(golink4.FnPoolQdepth, 0) }
func PoolDone() uint64    { return cross1(golink4.FnPoolDone, 0) }
func PoolSpawned() uint64 { return cross1(golink4.FnPoolSpawned, 0) }

func StatsBlockCalls() uint64    { return cross1(golink4.FnStatsBlkCalls, 0) }
func StatsBlockedNs() uint64     { return cross1(golink4.FnStatsBlkNs, 0) }
func StatsDetached() uint64      { return cross1(golink4.FnStatsDetached, 0) }
func StatsDetachedFails() uint64 { return cross1(golink4.FnStatsDetFails, 0) }

// SubmitNoopJob submits fn_id=1 (no-op) and returns the ticket — used by the
// dispatch-floor benchmark to avoid conflating poll backoff with submit cost.
func SubmitNoopJob() uint64 {
	return cross2(golink4.FnPoolSubmit, 1, 0)
}

// PollTicket polls an explicit ticket (benchmark helper).
func PollTicket(ticket uint64) uint64 {
	return cross1(golink4.FnPoolPoll, uintptr(ticket))
}

// ------------------------------------------------------------ two-tier route

// The CRASH FINDING (m2b-uncapped-crash.out): pure M2b at (10k, 50%, 100 ms)
// died with "runtime/cgo: pthread_create failed" — Go Ms NEVER shrink, so
// lingering Ms (~506 after the 1k leg) + ~500 new blocked Ms exceeded the
// environment's ~718-thread pid budget. The bridge must own a hard thread
// budget (research/runtime-hazards.md item 4, now measured).
//
// BlockViaSyswinCapped is the production-shaped two-tier route (S6's design):
// the syscall-window path while (a) concurrent syswin calls are under the
// soft cap and (b) the sampler-published thread budget has room; otherwise
// overflow to the bounded pool. Admission counters are exported for cell
// annotations.
var (
	syswinBusy      int64
	syswinConcCap   = envInt64("SPIKE4_SYSWIN_CAP", 384)
	threadBudget    = envInt64("SPIKE4_THREAD_BUDGET", 600)
	syswinAdmits    int64
	syswinOverflows int64
	syswinOpen      int32 = 1 // published by the sampler goroutine
)

func envInt64(name string, def int64) int64 {
	if v := os.Getenv(name); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			return n
		}
	}
	return def
}

// ReloadEnvTunables re-reads SPIKE4_SYSWIN_CAP / SPIKE4_THREAD_BUDGET (the
// worker tier sets a higher budget before its matrix runs).
func ReloadEnvTunables() {
	syswinConcCap = envInt64("SPIKE4_SYSWIN_CAP", 384)
	threadBudget = envInt64("SPIKE4_THREAD_BUDGET", 600)
}

// BlockViaSyswinCapped routes a blocking call: syswin (few/long tier) while
// budgets allow, else the bounded pool (many tier). This is S6's design.
// Hot path = two atomic reads (counter + sampler flag) — the /proc thread
// count is read by a 50 ms background sampler, NEVER per call (the first
// router version read /proc per call and the reads cost ~1-2 ms each under
// this sandbox's intercepted syscalls, poisoning every high-fan-in cell;
// measurement-infrastructure fix, logged in RESULTS.md).
func BlockViaSyswinCapped(ms uint64, immediate bool) uint64 {
	if atomic.AddInt64(&syswinBusy, 1) <= syswinConcCap && atomic.LoadInt32(&syswinOpen) == 1 {
		atomic.AddInt64(&syswinAdmits, 1)
		v := BlockViaSyswin(ms, immediate)
		atomic.AddInt64(&syswinBusy, -1)
		return v
	}
	atomic.AddInt64(&syswinBusy, -1)
	atomic.AddInt64(&syswinOverflows, 1)
	return BlockViaPool(ms)
}

// StartSyswinSampler launches the thread-budget monitor (idempotent).
// A blocking pool sized for CONCURRENCY (not CPUs — see RESULTS.md) plus a
// syswin lane bounded by the counter need a cheap global guard against the
// hard environment thread budget; a 50 ms /proc sample is 20 reads/second
// total instead of one per call.
func StartSyswinSampler() {
	if atomic.SwapInt32(&samplerStarted, 1) == 1 {
		return
	}
	go func() {
		for {
			t := readProcThreads()
			if t >= threadBudget-64 {
				atomic.StoreInt32(&syswinOpen, 0)
			} else {
				atomic.StoreInt32(&syswinOpen, 1)
			}
			time.Sleep(50 * time.Millisecond)
		}
	}()
}

var samplerStarted int32

// SyswinStats reports (admits, overflows) for cell annotations.
func SyswinStats() (int64, int64) {
	return atomic.LoadInt64(&syswinAdmits), atomic.LoadInt64(&syswinOverflows)
}

// ResetSyswinStats zeroes the admission counters between cells.
func ResetSyswinStats() {
	atomic.StoreInt64(&syswinAdmits, 0)
	atomic.StoreInt64(&syswinOverflows, 0)
}

func readProcThreads() int64 {
	b, err := os.ReadFile("/proc/self/status")
	if err != nil {
		return 1 << 30 // fail-safe: route to the pool
	}
	s := string(b)
	for i := 0; i+8 <= len(s); i++ {
		if s[i] == 'T' && s[i:i+8] == "Threads:" {
			j := i + 8
			for j < len(s) && (s[j] == ' ' || s[j] == '\t') {
				j++
			}
			k := j
			for k < len(s) && s[k] >= '0' && s[k] <= '9' {
				k++
			}
			if k > j {
				n, _ := strconv.ParseInt(s[j:k], 10, 64)
				return n
			}
		}
	}
	return 1 << 30
}
