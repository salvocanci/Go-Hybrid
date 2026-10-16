package hybridge

import "testing"

// TestSPHeadroomPositive: the probe must report positive headroom on the
// main test goroutine (the offsets canary — g.stackguard0's offset is
// verified against go1.26.9's DWARF by the spike-3 probe; this test pins
// the LIVE assumption the fast path's guard depends on).
func TestSPHeadroomPositive(t *testing.T) {
	if h := SPHeadroomForTest(); h == 0 {
		t.Fatal("SPHeadroomForTest() == 0 — the stackguard probe is broken")
	}
}

// TestNeedsDeepSentinelShape: the sentinel must never collide with a
// plausible small payload; pin its value (the retry logic in Cross1/2/3/4
// compares every fast-path result against it).
func TestNeedsDeepSentinelShape(t *testing.T) {
	if needsDeep != ^uint64(1) {
		t.Fatalf("needsDeep = %#x, want ^uint64(1)", needsDeep)
	}
	if fastStackNeed != 4096 {
		t.Fatalf("fastStackNeed = %d, want 4096 (the G2 bench's threshold)", fastStackNeed)
	}
}
