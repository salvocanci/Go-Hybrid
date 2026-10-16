// Package spike4: the Spike 4 load harness.
//
// A "cell" = one (mechanism, N, blocked-fraction, block-duration) load run:
// N goroutines start behind a barrier; fracPct% of them make the blocking
// foreign call through that mechanism, the rest burn ~50 us of compute; we
// measure wall time, per-task latency percentiles, a scheduler-health canary
// (time.Sleep(1ms) wake latency), peak OS threads and RSS from /proc.
//
// Each task runs under a 32 KiB stack pad (a real call chain's worth of
// frames) so the syscall-window mechanisms see realistic headroom — a fresh
// 2 KiB goroutine stack would bail to the pool path and mask M2 entirely.
// Pre-registered in RESULTS.md §Method.
package spike4

import (
	"encoding/json"
	"fmt"
	"os"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"spike4/hybridge4"
)

// Mechs is the mechanism set (M4 is not a cell mechanism — it is a demo).
var Mechs = []string{"M0", "M1", "M2a", "M2b", "M3"}

func blockWith(mech string, dms uint64) uint64 {
	switch mech {
	case "M0":
		return hybridge4.BlockViaGoSleep(dms)
	case "M1":
		return hybridge4.BlockMs(dms)
	case "M2a":
		return hybridge4.BlockViaSyswinCapped(dms, false)
	case "M2b":
		return hybridge4.BlockViaSyswinCapped(dms, true)
	case "M3":
		return hybridge4.BlockViaPool(dms)
	}
	panic("spike4: unknown mech " + mech)
}

// CellResult is one JSONL row of the matrix. P50us/P99us/PmaxMs describe
// the BLOCKED tasks (where the mechanism lives); CompP99us describes the
// compute tasks (scheduler-fairness probe under blocking load).
type CellResult struct {
	Mech        string  `json:"mech"`
	N           int     `json:"n"`
	FracPct     int     `json:"frac_pct"`
	Dms         int     `json:"d_ms"`
	WallS       float64 `json:"wall_s"`
	Done        int     `json:"done"`
	Capped      bool    `json:"capped"`
	CapS        float64 `json:"cap_s"`
	Tput        float64 `json:"tasks_per_s"`
	P50us       float64 `json:"p50_us"`
	P99us       float64 `json:"p99_us"`
	PmaxMs      float64 `json:"pmax_ms"`
	CompP99us   float64 `json:"comp_p99_us"`
	CanaryP99us float64 `json:"canary_p99_us"`
	CanaryMaxMs float64 `json:"canary_max_ms"`
	CanaryIters int     `json:"canary_iters"`
	PeakThreads int     `json:"peak_threads"`
	BaseThreads int     `json:"base_threads"`
	PeakRSSkb   int64   `json:"peak_rss_kb"`
	GOMAXPROCS  int     `json:"gomaxprocs"`
	Note        string  `json:"note,omitempty"`
}

// procSelf reads VmRSS (kB) and Threads from /proc/self/status in one pass.
func procSelf() (rssKb int64, threads int) {
	b, err := os.ReadFile("/proc/self/status")
	if err != nil {
		return 0, 0
	}
	for _, line := range strings.Split(string(b), "\n") {
		switch {
		case strings.HasPrefix(line, "VmRSS:"):
			f := strings.Fields(line[len("VmRSS:"):])
			if len(f) > 0 {
				rssKb, _ = strconv.ParseInt(f[0], 10, 64)
			}
		case strings.HasPrefix(line, "Threads:"):
			f := strings.Fields(line[len("Threads:"):])
			if len(f) > 0 {
				threads, _ = strconv.Atoi(f[0])
			}
		}
	}
	return rssKb, threads
}

// computeFiller burns ~50 us on-stack (uses the pad so the frame is real).
//
//go:noinline
func computeFiller(pad *[32768]byte) uint64 {
	s := uint64(0)
	for i := 0; i < len(pad); i += 64 {
		s += uint64(pad[i])
	}
	const iters = 1 << 17
	x := uint64(1)
	for i := 0; i < iters; i++ {
		x = x*1664525 + 1013904223
	}
	return s + x
}

// runCell executes one matrix cell and returns its result.
func runCell(mech string, n, fracPct, dms int, capS float64) CellResult {
	hybridge4.ResetSyswinStats()
	res := CellResult{
		Mech: mech, N: n, FracPct: fracPct, Dms: dms,
		CapS: capS, GOMAXPROCS: runtime.GOMAXPROCS(0),
	}
	if _, t := procSelf(); t > 0 {
		res.BaseThreads = t
	}

	var (
		wg    sync.WaitGroup
		stop  int32
		done  int32
		lat   = make([]int64, n)
		t0    = time.Now().UnixNano()
		start = make(chan struct{})
	)
	close(start)

	// canary: scheduler-health probe
	canaryStop := make(chan struct{})
	var canaryMu sync.Mutex
	canaryWake := make([]int64, 0, 4096)
	go func() {
		for {
			select {
			case <-canaryStop:
				return
			default:
			}
			w := time.Now().UnixNano()
			time.Sleep(time.Millisecond)
			d := time.Now().UnixNano() - w
			canaryMu.Lock()
			canaryWake = append(canaryWake, d)
			canaryMu.Unlock()
		}
	}()

	// sampler: peak threads + RSS every 25 ms
	sampStop := make(chan struct{})
	var peakThreads, peakRSS int64
	go func() {
		t := time.NewTicker(25 * time.Millisecond)
		defer t.Stop()
		for {
			select {
			case <-sampStop:
				return
			case <-t.C:
				if _, v := procSelf(); int64(v) > atomic.LoadInt64(&peakThreads) {
					atomic.StoreInt64(&peakThreads, int64(v))
				}
				if r, _ := procSelf(); r > atomic.LoadInt64(&peakRSS) {
					atomic.StoreInt64(&peakRSS, r)
				}
			}
		}
	}()

	var watchdog *time.Timer
	if capS > 0 {
		watchdog = time.AfterFunc(time.Duration(capS*float64(time.Second)), func() {
			atomic.StoreInt32(&stop, 1)
		})
	}

	wg.Add(n)
	for i := 0; i < n; i++ {
		go func(i int) {
			defer wg.Done()
			var pad [32768]byte // allocated PRE-barrier: stack-growth cost stays out of latencies
			pad[0] = byte(i)    // touch it so the frame is real from the start
			<-start
			if atomic.LoadInt32(&stop) == 1 {
				return
			}
			if i%100 < fracPct {
				blockWith(mech, uint64(dms))
			} else {
				computeFiller(&pad)
			}
			lat[i] = time.Now().UnixNano() - t0
			atomic.AddInt32(&done, 1)
		}(i)
	}

	doneCh := make(chan struct{})
	go func() { wg.Wait(); close(doneCh) }()
	margin := time.Duration(dms)*time.Millisecond + 90*time.Second
	if capS > 0 {
		margin += time.Duration(capS * float64(time.Second))
	} else {
		margin = time.Duration(dms)*time.Millisecond + 10*time.Minute
	}
	select {
	case <-doneCh:
	case <-time.After(margin):
		atomic.StoreInt32(&stop, 1)
		select {
		case <-doneCh:
		case <-time.After(2 * time.Minute):
			res.Note = "HARD-DRAIN-TIMEOUT (goroutines stuck past stop+margin)"
		}
		res.Capped = true
	}
	if watchdog != nil {
		if !watchdog.Stop() {
			// the cap already fired
			res.Capped = true
		}
	}
	if atomic.LoadInt32(&stop) == 1 {
		res.Capped = true
	}

	wall := time.Now().UnixNano() - t0
	close(canaryStop)
	close(sampStop)

	res.WallS = float64(wall) / 1e9
	res.Done = int(atomic.LoadInt32(&done))
	res.Tput = float64(res.Done) / res.WallS
	res.PeakThreads = int(atomic.LoadInt64(&peakThreads))
	res.PeakRSSkb = atomic.LoadInt64(&peakRSS)

	// latency percentiles, SPLIT by task kind: blocked tasks carry the
	// mechanism; compute tasks probe scheduler fairness under blocking load
	lats := make([]int64, 0, res.Done)
	comps := make([]int64, 0, res.Done)
	for i := 0; i < n; i++ {
		if lat[i] > 0 {
			if i%100 < fracPct {
				lats = append(lats, lat[i])
			} else {
				comps = append(comps, lat[i])
			}
		}
	}
	if len(lats) > 0 {
		sort.Slice(lats, func(a, b int) bool { return lats[a] < lats[b] })
		pick := func(p float64) int64 { return lats[int(float64(len(lats)-1)*p)] }
		res.P50us = float64(pick(0.50)) / 1e3
		res.P99us = float64(pick(0.99)) / 1e3
		res.PmaxMs = float64(lats[len(lats)-1]) / 1e6
	}
	if len(comps) > 0 {
		sort.Slice(comps, func(a, b int) bool { return comps[a] < comps[b] })
		res.CompP99us = float64(comps[int(float64(len(comps)-1)*0.99)]) / 1e3
	}

	// canary percentiles
	canaryMu.Lock()
	cw := canaryWake
	canaryMu.Unlock()
	res.CanaryIters = len(cw)
	if len(cw) > 0 {
		sort.Slice(cw, func(a, b int) bool { return cw[a] < cw[b] })
		res.CanaryP99us = float64(cw[int(float64(len(cw)-1)*0.99)]) / 1e3
		res.CanaryMaxMs = float64(cw[len(cw)-1]) / 1e6
	}
	// two-tier routing split (M2a/M2b cells): syswin admits vs pool overflows
	if mech == "M2a" || mech == "M2b" {
		a, o := hybridge4.SyswinStats()
		res.Note = fmt.Sprintf("syswin=%d pool=%d", a, o)
	}
	return res
}

// WriteJSONL appends rows to a file (called by matrix tests).
func WriteJSONL(path string, rows []CellResult) error {
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	enc := json.NewEncoder(f)
	for i := range rows {
		if err := enc.Encode(rows[i]); err != nil {
			return err
		}
	}
	return nil
}

func cellLine(r CellResult) string {
	capped := ""
	if r.Capped {
		capped = " CAPPED"
	}
	return fmt.Sprintf("%-4s n=%-6d f=%-2d%% d=%-3dms wall=%8.2fs%s done=%-6d tput=%9.0f/s p99=%9.1fus canaryP99=%9.1fus thr=%-5d rss=%dMB",
		r.Mech, r.N, r.FracPct, r.Dms, r.WallS, capped, r.Done, r.Tput, r.P99us, r.CanaryP99us, r.PeakThreads, r.PeakRSSkb/1024)
}
