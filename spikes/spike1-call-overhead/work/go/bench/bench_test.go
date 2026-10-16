package bench

// Benchmarks and safety probes. Mechanisms (see ../RESULTS.md):
//   M0 goonly  — Go->Go floor
//   M1 cgo_trivial — via the bench-cgo file (plain cgo noop)
//   M2 cgo_plain — cgo add
//   M3 asm_direct — trampoline, goroutine stack (lower bound)
//   M4 asm_stack — trampoline, mmap'd guarded Rust stack (safe design)

import (
        "runtime"
        "testing"

        "spike1/golink"
)

var sink uint64

func goAdd(a, b uint64) uint64 { return a + b }

func BenchmarkGoOnly(b *testing.B) {
        b.ReportAllocs()
        for i := 0; i < b.N; i++ {
                sink = goAdd(uint64(i), uint64(i))
        }
}

func BenchmarkAsmDirect(b *testing.B) {
        b.ReportAllocs()
        fn := golink.FnAdd
        for i := 0; i < b.N; i++ {
                sink = callRustDirect(fn, uint64(i), uint64(i))
        }
}

func BenchmarkAsmDirectNoop(b *testing.B) {
        b.ReportAllocs()
        fn := golink.FnNoop
        for i := 0; i < b.N; i++ {
                callRustDirectNoop(fn)
        }
}

func BenchmarkAsmStack(b *testing.B) {
        b.ReportAllocs()
        fn := golink.FnAdd
        for i := 0; i < b.N; i++ {
                sink = callRustStack(fn, uint64(i), uint64(i))
        }
}

func BenchmarkAsmStackNoop(b *testing.B) {
        b.ReportAllocs()
        fn := golink.FnNoop
        for i := 0; i < b.N; i++ {
                callRustStackNoop(fn)
        }
}

// ---- correctness & stability probes ----

func TestAsmCorrectness(t *testing.T) {
        if got := callRustStack(golink.FnAdd, 2, 3); got != 5 {
                t.Fatalf("callRustStack(2,3) = %d", got)
        }
        if got := callRustDirect(golink.FnAdd, 2, 3); got != 5 {
                t.Fatalf("callRustDirect(2,3) = %d", got)
        }
        // 20k-deep Rust recursion ≈ 640KB+ stack: proves the mmap'd stack is real
        // and deep frames never touch the Go stack (guard page protects).
        if got := callRustTreeStack(golink.FnTree, 20_000); got != 20000*20001/2 {
                t.Fatalf("tree(20000) = %d", got)
        }
}

func TestAsmStabilityUnderScheduler(t *testing.T) {
        // 8 parallel goroutines x 10k stack-switched calls under GOMAXPROCS=2:
        // goroutines may migrate between threads between calls; the trampoline
        // must stay correct (it holds no cross-call state).
        const workers = 8
        const calls = 10_000
        done := make(chan uint64, workers)
        for w := 0; w < workers; w++ {
                go func(seed uint64) {
                        local := uint64(0)
                        for i := 0; i < calls; i++ {
                                local ^= callRustStack(golink.FnAdd, seed, uint64(i))
                        }
                        done <- local
                }(uint64(w) + 1)
        }
        for w := 0; w < workers; w++ {
                <-done
        }
}

// TestAsmGCHammer runs GC while stack-switched calls happen, to shake out
// stack-scanning hazards (the known risk of running off the Go stack).
func TestAsmGCHammer(t *testing.T) {
        done := make(chan struct{})
        go func() {
                defer close(done)
                for i := 0; i < 500_000; i++ {
                        sink = callRustStack(golink.FnAdd, uint64(i), 1)
                }
        }()
        // force GC churn while the other goroutine crosses the boundary
        for i := 0; i < 20; i++ {
                _ = make([]byte, 1<<20)
                runtime.GC()
        }
        <-done
}
