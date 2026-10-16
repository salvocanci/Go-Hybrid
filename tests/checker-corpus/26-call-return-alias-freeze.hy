// ============================================================================
// 26-call-return-alias-freeze — Checker corpus #26 (added 2026-10-14 to pin
// issue #38: an alias that comes back through a function CALL is not frozen
// by a later `move`, so the sender can still write through it).
//
// PURPOSE: corpus 20 covers the lexical alias (`m2 := agg`). This program
// covers the CALL form: `alias := same(agg)` where `same` returns its map
// argument. In Go a map is a reference value, so `same` hands back the SAME
// backing store as `agg`; the checker has no interprocedural summary that
// could prove the return is fresh, so `alias` must be treated as a live
// alias of `agg`. After `results <- move agg` the write through `alias` is
// use-after-move (A1b) — the emitted Go races (`go run -race`: WARNING: DATA
// RACE) and the checker accepted it with 0 diagnostics before the fix.
//
// UNCONTESTED: alias coverage is entailed by any sound freeze rule (SPEC
// O5.2 "every live alias ... read or write"); a call is just another way to
// spell the alias. Clean twin of 20 (lexical alias); read-form twin: 19.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `agg` and `alias` (same map value, two bindings),
//   `results`/`done` (channels), receiver-side `m` (owned after the move).
// Layer 2 (Rust-side owned): none.
// Layer 3 (boundary handles): none.
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   [S1] `task sink(results, done)` — channels: sendable (safe-by-type).
//   [S2] `results <- move agg` — OWNED MOVE: sendable (A1c route 2). The
//        A1b freeze starts HERE and covers the binding AND every live alias
//        — `alias` (aliased via the call return) is frozen too.
//   [S3] `done <- true` in sink — sendable.
//
// ---- Expected verdict (registered 2026-10-14) ----
// EXPECTED-VERDICT: REJECT A1b
//   REJECT — A1b alias-form (freeze covers every live alias, SPEC O5.2;
//   diagnostic HYB-E3003, with the alias chain shown). Not contested: this
//   is a write through an alias of the moved value.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

fn same(m map[string]int) map[string]int {
    return m
}

fn sink(results <-chan map[string]int, done chan<- bool) {
    m := <-results
    fmt.println("count: {len(m)}")
    done <- true
}

fn main() {
    agg := map[string]int{}
    agg["a"] = 1

    results := make(chan map[string]int, 1)
    done := make(chan bool, 1)
    task sink(results, done)          // spawn site [S1]

    alias := same(agg)                // ALIAS via call return — same map value

    results <- move agg               // send site [S2] — LEGAL owned move;
                                      // freeze begins: agg AND alias frozen

    alias["total"] = len(alias)       // VIOLATION (A1b, alias-form): write
                                      // through a live alias of the moved value

    <-done
}
