package spike4

// The load matrices (SPEC §5 Spike 4): 1k + 10k in the sandbox leg, 100k in
// the worker leg (jobs/005 sets SPIKE4_WORKER=1). Caps are pre-registered in
// RESULTS.md — they bound resource waste, never hide data: capped cells
// report done-count and rate, which is the datum.

import (
	"os"
	"runtime"
	"runtime/debug"
	"strconv"
	"strings"
	"testing"
	"time"

	"spike4/hybridge4"
)

func TestMain(m *testing.M) {
	// Blocking pool sized for CONCURRENCY, not CPUs (measurement-driven
	// amendment, logged in RESULTS.md: a GOMAXPROCS-sized blocking pool
	// starved the overflow lane — Tokio's spawn_blocking default is 512 for
	// exactly this reason). Sandbox default 128; worker sets 256 via env.
	pool := 128
	if v := os.Getenv("SPIKE4_POOL_THREADS"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			pool = n
		}
	}
	hybridge4.PoolInit(uint64(pool))
	hybridge4.StartSyswinSampler() // publishes the thread-budget flag every 50 ms
	rc := m.Run()
	os.Exit(rc)
}

// matrixGC wraps a matrix test body: GC OFF during cells (a mark cycle
// started mid-cell on the worker and gcAssistAlloc WEDGED the spawn loop —
// every P was parked inside M1's nanosleeps so mark could not progress;
// goroutine dump evidence in jobs/005's first run; recorded in RESULTS.md
// as M1's third indictment), then an explicit GC between cells keeps the
// heap bounded. Percent restored on exit.
func matrixGC(t *testing.T, body func()) {
	old := debug.SetGCPercent(-1)
	defer debug.SetGCPercent(old)
	body()
	runtime.GC()
}

func outPath(defaultName string) string {
	if p := os.Getenv("SPIKE4_OUT"); p != "" {
		return p
	}
	return defaultName
}

// TestMatrixSandbox: 1k full sweep + 10k full sweep. No race detector (the
// race leg covers safety); timings are the data. SPIKE4_MATRIX_LEG selects
// "1k", "10k" or "all" (default) — the harness runs the legs as separate
// foreground invocations to stay under tool-call time limits; results append.
func TestMatrixSandbox(t *testing.T) {
	if testing.Short() {
		t.Skip("short mode")
	}
	matrixGC(t, func() { testMatrixSandboxBody(t) })
}

func testMatrixSandboxBody(t *testing.T) {
	leg := os.Getenv("SPIKE4_MATRIX_LEG")
	if leg == "" {
		leg = "all"
	}
	var rows []CellResult

	// 1k: mech x {1,10,50}% x {1,100}ms, cap 30s
	if leg == "all" || leg == "1k" {
		for _, mech := range Mechs {
			for _, f := range []int{1, 10, 50} {
				for _, d := range []int{1, 100} {
					r := runCell(mech, 1000, f, d, 30)
					rows = append(rows, r)
					t.Log(cellLine(r))
				}
			}
		}
	}

	// 10k: mech x {1,10,50}% x {1,10,100}ms, cap 60s
	// M2a/M2b route through BlockViaSyswinCapped (two-tier: syswin up to the
	// concurrency cap + thread budget, overflow to the pool) — the pure-M2b
	// crash at this cell is preserved in ../m2b-uncapped-crash.out
	if leg == "all" || leg == "10k" {
		for _, mech := range Mechs {
			for _, f := range []int{1, 10, 50} {
				for _, d := range []int{1, 10, 100} {
					r := runCell(mech, 10000, f, d, 60)
					rows = append(rows, r)
					t.Log(cellLine(r))
				}
			}
		}
	}

	if err := WriteJSONL(outPath("../matrix.sandbox.jsonl"), rows); err != nil {
		t.Fatal(err)
	}
}

// TestMatrixWorker: the 100k tier (jobs/005 sets SPIKE4_WORKER=1).
// SetMaxThreads(30000) + thread budget 2000 pre-registered (30 GB worker);
// M2 fan-in beyond the budget overflows to the pool (two-tier design);
// M1 cells cap at 120s; the M3 (50%,100ms) cell caps at 300s.
func TestMatrixWorker(t *testing.T) {
	if os.Getenv("SPIKE4_WORKER") != "1" {
		t.Skip("worker tier only (SPIKE4_WORKER=1)")
	}
	debug.SetMaxThreads(30000) // pre-registered (30 GB worker)
	// worker thread budget for the two-tier route (pre-registered): higher
	// than sandbox (600) but still bounded; M2 fan-in overflows to the pool
	os.Setenv("SPIKE4_THREAD_BUDGET", "2000")
	hybridge4.ReloadEnvTunables()
	matrixGC(t, func() { testMatrixWorkerBody(t) })
}

func testMatrixWorkerBody(t *testing.T) {
	var rows []CellResult

	// cross-tier anchor: same 3 cells as the sandbox 10k leg
	for _, mech := range []string{"M0", "M2b", "M3"} {
		r := runCell(mech, 10000, 10, 10, 60)
		rows = append(rows, r)
		t.Log(cellLine(r))
	}

	// 100k sweep: {1,10,50}% x {1,10}ms + M3-only (50%,100ms)
	for _, mech := range Mechs {
		for _, f := range []int{1, 10, 50} {
			for _, d := range []int{1, 10} {
				capS := 120.0
				if mech == "M3" || mech == "M0" {
					capS = 300
				}
				r := runCell(mech, 100000, f, d, capS)
				rows = append(rows, r)
				t.Log(cellLine(r))
			}
		}
	}
	// the long M3 cell: (100k, 50%, 100ms) — throughput-bound, cap 300s
	r := runCell("M3", 100000, 50, 100, 300)
	rows = append(rows, r)
	t.Log(cellLine(r))

	if err := WriteJSONL(outPath("../matrix.worker.jsonl"), rows); err != nil {
		t.Fatal(err)
	}
}

// TestRaceLeg: 1k scale, the two safety cells per mechanism — run under
// -race by run.sh. Deadlock/panic is the failure mode, not numbers.
func TestRaceLeg(t *testing.T) {
	var rows []CellResult
	for _, mech := range Mechs {
		for _, c := range [][2]int{{1, 1}, {50, 100}} {
			r := runCell(mech, 1000, c[0], c[1], 30)
			rows = append(rows, r)
			t.Log(cellLine(r))
		}
	}
	if err := WriteJSONL(outPath("../matrix.race.jsonl"), rows); err != nil {
		t.Fatal(err)
	}
}

// TestM4ExhaustionDemo: unbounded detached threads (the negative control).
// Sandbox default 2000; worker sets SPIKE4_M4N=5000. Sleepers live 250 ms.
// Exhaustion is evidenced by EITHER spawn failures (the OS/cgroup refusing
// threads — the strongest form) OR peak concurrency >= n/2.
func TestM4ExhaustionDemo(t *testing.T) {
	n := 2000
	if v := os.Getenv("SPIKE4_M4N"); v != "" {
		n, _ = strconv.Atoi(v)
	}
	if b, err := os.ReadFile("/sys/fs/cgroup/pids.max"); err == nil {
		t.Logf("cgroup pids.max = %s", strings.TrimSpace(string(b)))
	}
	t.Logf("spawning up to %d detached Rust threads (250 ms each)", n)
	_, baseThreads := procSelf()
	baseRSS, _ := procSelf()

	t0 := time.Now()
	spawned := 0
	firstFailure := 0
	for i := 0; i < n; i++ {
		if r := hybridge4.SpawnDetached(250); r == ^uint64(0) {
			if firstFailure == 0 {
				firstFailure = i + 1
			}
			// keep trying a few more to confirm it is a hard wall, not a blip
			if i > firstFailure+20 {
				break
			}
			continue
		}
		spawned++
		if spawned%500 == 0 {
			rss, thr := procSelf()
			t.Logf("  spawned %5d: threads=%d rss=%d kB (%.1f kB/thread over base)",
				spawned, thr, rss, float64(rss-baseRSS)/float64(thr-baseThreads+1))
		}
	}
	spawnWall := time.Since(t0)
	peakThr := 0
	peakRSS := int64(0)
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		rss, thr := procSelf()
		if thr > peakThr {
			peakThr = thr
		}
		if rss > peakRSS {
			peakRSS = rss
		}
		time.Sleep(25 * time.Millisecond)
	}
	if got := hybridge4.StatsDetached(); got != uint64(spawned) {
		t.Fatalf("detached success count: got %d want %d", got, spawned)
	}
	extra := peakThr - baseThreads
	t.Logf("spawn wall: %v (%.1f us/thread for %d spawns); first spawn FAILURE at attempt %d (failures: %d); peak threads=%d (+%d over base %d); peak rss=%d kB (+%d; %.1f kB/thread)",
		spawnWall, float64(spawnWall.Microseconds())/float64(spawned), spawned,
		firstFailure, hybridge4.StatsDetachedFails(),
		peakThr, extra, baseThreads,
		peakRSS, peakRSS-baseRSS, float64(peakRSS-baseRSS)/float64(extra+1))
	if firstFailure == 0 && extra < n/2 {
		t.Fatalf("neither exhaustion mode observed: no spawn failures and peak threads %d < %d", extra, n/2)
	}
}
