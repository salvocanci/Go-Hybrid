package spike4

// Dispatch-cost micro-benches (count=10 in run.sh): the per-call price of
// each mechanism with an instant-return callee — the number the compiler's
// descriptor flag decides between.

import (
	"testing"
	"time"

	"spike4/hybridge4"
)

// BenchmarkCrossAdd: the plain fast crossing (Spike 1/3 reference, ~2.4 ns).
func BenchmarkCrossAdd(b *testing.B) {
	for i := 0; i < b.N; i++ {
		hybridge4.Add(1, 2)
	}
}

// BenchmarkM1Zero: naive crossing, instant callee.
func BenchmarkM1Zero(b *testing.B) {
	for i := 0; i < b.N; i++ {
		hybridge4.BlockMs(0)
	}
}

// BenchmarkM2aZero: lazy enter/exit pair + instant callee.
func BenchmarkM2aZero(b *testing.B) {
	for i := 0; i < b.N; i++ {
		hybridge4.BlockViaSyswin(0, false)
	}
}

// BenchmarkM2bZero: immediate enter/exit pair + instant callee.
func BenchmarkM2bZero(b *testing.B) {
	for i := 0; i < b.N; i++ {
		hybridge4.BlockViaSyswin(0, true)
	}
}

// BenchmarkGoSleepZero: the pure-Go park floor.
func BenchmarkGoSleepZero(b *testing.B) {
	for i := 0; i < b.N; i++ {
		time.Sleep(0)
	}
}

// BenchmarkPoolNoopRT: M3 dispatch floor — no-op job submit + poll-to-done.
// Includes the 25 us minimum park backoff (the honest floor of the design).
func BenchmarkPoolNoopRT(b *testing.B) {
	for i := 0; i < b.N; i++ {
		ticket := hybridge4.SubmitNoopJob()
		for {
			if hybridge4.PollTicket(ticket) == 1 {
				break
			}
			time.Sleep(25 * time.Microsecond)
		}
	}
}
