package hybridge

// In-package benchmark: the direct two-word (HyResult RAX:RDX) crossing cost
// without the hand-written Go wrapper layers — the compiler-emission
// projection for E1.

import (
	"testing"

	"spike5/golink"
)

// growStack ensures the bench goroutine's stack has headroom (fresh benches
// can start on small stacks, which the guard check correctly declines).
func growStack(n int) int {
	if n <= 0 {
		return 0
	}
	var pad [64]byte
	pad[0] = byte(n)
	return int(pad[0]) + growStack(n-1)
}

func BenchmarkWideDirect(b *testing.B) {
	growStack(96)
	fn := golink.FnOkAdd
	for i := 0; i < b.N; i++ {
		c1, c2 := callWide2(fn, uintptr(i), 1)
		if c1 == needsDeep {
			b.Fatal("unexpected deep fallback in bench")
		}
		_ = c2
	}
}
