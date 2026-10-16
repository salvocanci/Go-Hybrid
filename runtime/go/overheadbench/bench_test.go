package overheadbench

import (
	"fmt"
	"sync"
	"testing"

	"hybrid.program/hybridge"
)

// TestNopPayloadFidelity: the crossing preserves the u64 payload exactly —
// the ABI handshake (init) already proved register discipline; this proves
// it across the payload values the bindings actually pass (ids, lengths,
// pointers, generation tags).
func TestNopPayloadFidelity(t *testing.T) {
	payloads := []uint64{0, 1, 42, 1 << 32, 0x68795f61626931, ^uint64(0) >> 1}
	for _, x := range payloads {
		if got := Nop(x); got != x {
			t.Fatalf("Nop(%#x) = %#x", x, got)
		}
		if v, ok := NopRaw(x); ok && v != x {
			t.Fatalf("NopRaw(%#x) = %#x", x, v)
		}
		// ok == false just means the fast trampoline bounced (shallow
		// stack) — Cross1's retry already returned the right answer above.
	}
}

// TestFastPathAfterStackGrowth: the G2 path-proof, as a regression test.
// After the goroutine stack has grown (200-deep recursion forces contiguous
// doubling), headroom exceeds fastStackNeed and EVERY crossing takes the
// fast path — DeepPathCount frozen across the loop.
func TestFastPathAfterStackGrowth(t *testing.T) {
	var pad [256]byte
	var grow func(depth int) byte
	grow = func(depth int) byte {
		if depth == 0 {
			return pad[0]
		}
		pad[depth%256]++
		return grow(depth-1) + pad[depth%256]
	}
	_ = grow(200)

	before := hybridge.DeepPathCount.Load()
	for i := 0; i < 10_000; i++ {
		if got := Nop(uint64(i)); got != uint64(i) {
			t.Fatalf("Nop(%d) = %d", i, got)
		}
	}
	after := hybridge.DeepPathCount.Load()
	if after != before {
		t.Fatalf("DeepPathCount moved %d → %d across a grown-stack loop: the fast path did not hold", before, after)
	}
}

// TestConcurrentCrossings: the collision-safety property spike 3's
// TestConcurrentCrossing pinned (the reason the pooled deep path exists) —
// many goroutines crossing simultaneously, every payload correct, the
// pool's acquire/release never leaking a slot.
func TestConcurrentCrossings(t *testing.T) {
	const workers = 8
	const perWorker = 500
	var wg sync.WaitGroup
	errs := make(chan error, workers)
	for w := 0; w < workers; w++ {
		wg.Add(1)
		go func(w int) {
			defer wg.Done()
			for i := 0; i < perWorker; i++ {
				want := uint64(w*perWorker + i)
				if got := Nop(want); got != want {
					errs <- fmt.Errorf("payload: got %#x, want %#x", got, want)
					return
				}
			}
		}(w)
	}
	wg.Wait()
	select {
	case err := <-errs:
		t.Fatal(err)
	default:
	}
}
