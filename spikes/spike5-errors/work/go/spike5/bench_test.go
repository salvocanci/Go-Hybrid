// Spike 5 benchmarks (thresholds E1-E3, E6 in ../RESULTS.md).
package spike5

import (
	"errors"
	"testing"

	"spike5/hybridge"
)

var errSentinel = errors.New("native sentinel")

//go:noinline
func goNativeOk(a, b uint64) (uint64, error) { return a + b, nil }

//go:noinline
func goNativeErr(a uint64) (uint64, error) { return 0, errSentinel }

// The Go-native floor: (T, error) return without any crossing.
func BenchmarkGoNativeOk(b *testing.B) {
	for i := 0; i < b.N; i++ {
		if _, err := goNativeOk(uint64(i), 1); err != nil {
			b.Fatal(err)
		}
	}
}

// The Go-native error floor: returning a pre-allocated sentinel.
func BenchmarkGoNativeErr(b *testing.B) {
	for i := 0; i < b.N; i++ {
		if _, err := goNativeErr(uint64(i)); err == nil {
			b.Fatal("expected error")
		}
	}
}

// E1: ok path through the boundary ((T, nil), zero allocs expected).
func BenchmarkOkPath(b *testing.B) {
	for i := 0; i < b.N; i++ {
		if _, err := hybridge.OkAdd(uint64(i), 1); err != nil {
			b.Fatal(err)
		}
	}
}

// E2: sentinel error path (zero allocs expected).
func BenchmarkErrSentinel(b *testing.B) {
	for i := 0; i < b.N; i++ {
		if _, err := hybridge.MayFail(0, 1, false); err == nil {
			b.Fatal("expected error")
		}
	}
}

// E3: dynamic (wrapped) error path (at most 1 alloc expected).
func BenchmarkErrDynamic(b *testing.B) {
	for i := 0; i < b.N; i++ {
		if _, err := hybridge.MayFail(3, 1, true); err == nil {
			b.Fatal("expected error")
		}
	}
}

// E6: Rust-side Result loop reference (inner 2^20 iterations per op; divide
// ns/op by 1048576 in analysis).
const rustInner = 1 << 20

func BenchmarkRustResultLoop(b *testing.B) {
	for i := 0; i < b.N; i++ {
		hybridge.BenchResult(rustInner, 0)
	}
}

// E6 error-arm reference: the Rust loop with 1-in-4 Err frequency.
func BenchmarkRustResultLoopErr(b *testing.B) {
	for i := 0; i < b.N; i++ {
		hybridge.BenchResult(rustInner, 4)
	}
}
