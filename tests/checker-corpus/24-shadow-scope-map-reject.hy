// ============================================================================
// 24-shadow-scope-map-reject — Checker corpus #24 (bounty track, issue #14,
// reported by LubuSeb on 2026-10-14 and reproduced on main before the fix).
//
// PURPOSE: pin that an inner-block define SHADOWS an outer binding instead
// of overwriting it. The checker's binding env was FLAT over the function:
// `m := 1` inside an `if` rewrote the outer `m := map[string]int{...}`
// entry, so the later `task worker(m, done)` classified against the INNER
// int (class 1, sendable-by-type) and passed with ZERO diagnostics — while
// the emitted Go passed the real map to the goroutine and
// `go run -race` reported two write/write DATA RACEs (main.worker vs
// main.main) plus a concurrent-map-writes fatal.
//
// ---- Tier-0 rule set applied ----
// The outer `m` is a map[string]int: a named mutable GC value (§9.4,
// "not sendable"). The inner `m := 1` is lexically scoped to the if block
// (T22's binding-level rules do not change block scoping); after the block
// the ONLY visible `m` is the map. A1c's safe-by-type test on the spawn
// therefore runs against the map: REJECT.
//
// Negative control (reporter-supplied): rename the inner binding to `n`
// and the same checker rejects the spawn — proving the shadowing was the
// exact laundering path.
//
// FIX SHAPE: the checker's env is now scope-aware (Push/Pop scope events in
// walk.rs's flat list; defines land in the innermost layer and die at block
// exit; closures.rs mirrors the discipline). The if-init define shares the
// if's implicit scope (Go rule: init vars are visible through the whole
// if, including the else branch); then/else bodies, loop bodies, managed
// bodies, and match/select arm bodies each get their own scope.
//
// ---- Expected verdict (derived from the rule key BEFORE the fix ran) ----
// EXPECTED-VERDICT: REJECT A1c
// ============================================================================

fn worker(m map[string]int, done chan<- bool) {
    for i in 0..10000 { m["k"] = i }
    done <- true
}

fn main() {
    m := map[string]int{"k": 0}
    if true {
        m := 1
        fmt.println(m)
    }
    done := make(chan bool, 1)
    task worker(m, done)
    for i in 0..10000 { m["k"] = i }
    <-done
}
