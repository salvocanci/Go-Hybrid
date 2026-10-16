package hybridge

// In-package benchmarks: the cost of the crossing PRIMITIVE itself, without
// the hand-written Go wrapper layers (Add -> cross2 -> callFast2) that the
// Spike 3 test API goes through. The Hybrid compiler emits the trampoline
// call INLINE at each crossing site, so THESE numbers (not the wrapped ones)
// are the projection for the generated code.

import (
	"testing"

	"spike3/golink"
)

// The raw fast-path crossing as the compiler would emit it (check + call).
// NOTE: fresh benchmark goroutines can start with small (2 KiB-class)
// stacks, which the guard check CORRECTLY declines to the deep path. To
// measure the fast path itself, grow the goroutine stack first.
func growStack(n int) int {
	if n <= 0 {
		return 0
	}
	var pad [64]byte
	pad[0] = byte(n)
	return int(pad[0]) + growStack(n-1)
}

func BenchmarkCrossFastDirect(b *testing.B) {
	growStack(96) // ensure the bench goroutine's stack has headroom
	fn := golink.FnAdd
	for i := 0; i < b.N; i++ {
		v := callFast2(fn, uintptr(i), 1)
		if v == needsDeep {
			b.Fatal("unexpected deep fallback in bench")
		}
	}
}

// The deep-path crossing (pool acquire + switch + release) per op.
func BenchmarkCrossDeepDirect(b *testing.B) {
	fn := golink.FnAdd
	for i := 0; i < b.N; i++ {
		j := acquireDeep()
		callDeep2(fn, uintptr(i), 1, deepTops[j])
		releaseDeep(j)
	}
}

// The deep-path crossing WITHOUT pool overhead (stack pre-acquired):
// isolates the switch + call itself.
func BenchmarkCrossDeepSwitchOnly(b *testing.B) {
	fn := golink.FnAdd
	j := acquireDeep()
	st := deepTops[j]
	defer releaseDeep(j)
	for i := 0; i < b.N; i++ {
		callDeep2(fn, uintptr(i), 1, st)
	}
}
