// ============================================================================
// 20-freeze-alias-write — Checker corpus #20 (pre-registered BEFORE any
// checker exists; added by the LEAD during integration, still pre-checker,
// 2026-10-12 — materializes the REQUIRED MUTANT recorded in 05's header and
// corpus OQ3: the ALIAS form of use-after-move).
//
// PURPOSE: a freeze that ignores aliases is a no-op on GC values — anyone
// could defeat it with `m2 := agg` before the send. This program does
// exactly that: creates an alias, move-sends the binding, then writes
// through the ALIAS. The send is legal (owned move, A1c route 2); the
// violation is the alias write. UNCONTESTED: alias coverage is entailed by
// any sound freeze-after-send rule (SPEC O5.2 "every live alias ... read or
// write"); no reading of Q1 — not even the literal "mutations"-only
// wording — permits this program, because this IS a mutation.
//
// The ported Go habit under test: re-binding the map to a second local
// "for the sender side" before handing the original away. Lexical aliases
// of GC values are invisible at runtime; only the checker's dataflow sees
// them — which is the entire point of Tier 0.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `agg` (map[string]int), `m2` (alias of `agg` —
//   same L1 value, second binding), `results`/`done` (channels),
//   receiver-side `m` (owned by the RECEIVER after the move lands).
// Layer 2 (Rust-side owned): none (discipline transfer over an L1 value).
// Layer 3 (boundary handles): none.
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   [S1] `task sink(results, done)` — channels: sendable (safe-by-type).
//   [S2] `results <- move agg` — OWNED MOVE: sendable (A1c route 2). The
//        A1b freeze starts HERE and covers the binding AND every live
//        alias — `m2` is frozen by the send even though `agg` was the name
//        that moved.
//   [S3] `done <- true` in sink — sendable.
//   Receiver side: reads only — LEGAL (receiver-owned).
//
// ---- Expected verdict (PRE-REGISTERED 2026-10-12, before any checker) ----
// EXPECTED-VERDICT: REJECT A1b
//   REJECT — A1b alias-form (freeze covers every live alias, SPEC O5.2;
//   diagnostic HYB-E3003, with the alias chain shown in the message so
//   the user sees WHERE the frozen access came from). NOT contested —
//   this is a write through an alias; even Q1's literal mutations-only
//   wording rejects it. Read-form contested twin: 19 (D1). Clean twin: 16.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

const corpus = "the quick brown fox jumps over the lazy dog the fox runs hybrid"

fn sink(results <-chan map[string]int, done chan<- bool) {
    m := <-results                    // ownership lands here (receiver-owned)
    fmt.println("words counted: {len(m)}")
    done <- true                      // send site [S3]
}

fn main() {
    agg := map[string]int{}
    for w in strings.split(corpus, " ") {
        agg[w]++
    }

    m2 := agg                         // ALIAS of the same L1 map value —
                                      // the freeze-defeat shape under test

    results := make(chan map[string]int, 1)
    done := make(chan bool, 1)
    task sink(results, done)          // spawn site [S1]

    results <- move agg               // send site [S2] — LEGAL owned move;
                                      // freeze begins: agg AND m2 frozen

    m2["total"] = len(m2)             // VIOLATION (A1b, alias-form): write
                                      // through a live alias of the moved
                                      // value — the checker's alias dataflow
                                      // is the only thing that sees this

    <-done
}
