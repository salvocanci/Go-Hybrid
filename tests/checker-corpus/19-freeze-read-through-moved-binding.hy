// ============================================================================
// 19-freeze-read-through-moved-binding — Checker corpus #19 (pre-registered
// BEFORE any checker exists; added by the LEAD during integration, still
// pre-checker, 2026-10-12 — materializes the REQUIRED MUTANT that pins
// SPEC-LANGUAGE.md open decision D1 / corpus OQ3).
//
// PURPOSE: the pure-READ form of use-after-move. Program 05 pins the WRITE
// (`agg["total"] = len(agg)`); this program contains NO write through the
// moved binding — only a read — so it isolates exactly the question Q1's
// literal wording leaves open: the ruling says the sender's "subsequent
// mutations" are errors; SPEC-LANGUAGE.md O5.2 deliberately bans READS
// through frozen aliases too (the receiver may mutate concurrently; under
// Go's DRF-SC a concurrent unsynchronized read/write IS a race — a
// writes-only freeze would falsify the §9.2 claims paragraph). This
// program is that rule's pin. If it is ever relaxed to writes-only, this
// verdict flips via a logged amendment AND the claims paragraph must be
// re-scoped in the same edit.
//
// The ported Go habit under test: "send the aggregate, then log a stat
// about it" — `log.len(agg)` after handing `agg` away. Reads feel safe;
// over GC memory they cannot dangle. The race is with the RECEIVER's
// writes, not with freeing.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `agg` (map[string]int — main-local until the MOVE),
//   `results`/`done` (channels), receiver-side `m` (map — owned by the
//   RECEIVER after the move lands).
// Layer 2 (Rust-side owned): none (discipline transfer over an L1 value).
// Layer 3 (boundary handles): none.
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   [S1] `task sink(results, done)` — channels: sendable (safe-by-type).
//   [S2] `results <- move agg` — OWNED MOVE: sendable (A1c route 2). The
//        A1b freeze starts HERE (binding + every alias, reads AND writes).
//   [S3] `done <- true` in sink — sendable.
//   Receiver side: `m := <-results` then `m["fox"]++` then reads — LEGAL:
//   the receiver is the new owner and may mutate freely (it is the
//   receiver's MUTATION that makes the sender's later READ a race).
//
// ---- Expected verdict (PRE-REGISTERED 2026-10-12, before any checker) ----
// EXPECTED-VERDICT: REJECT A1b
//   REJECT — A1b read-form (freeze-after-send covers reads, SPEC O5.2,
//   diagnostic HYB-E3003). **CONTESTED (D1):** Q1's literal wording bans
//   "mutations" only; the stricter reads-too reading is adopted because a
//   writes-only freeze would falsify the honest-claims paragraph. Flagged
//   for human pre-review at G1 (SPEC §13.2 D1); relaxation requires a
//   logged amendment + claims re-scoping in one edit.
//   NOT the alias form — the alias mutant is 20 (uncontested).
//   Clean twin: 16 (same send shape, sender never touches it again).
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

const corpus = "the quick brown fox jumps over the lazy dog the fox runs hybrid"

fn sink(results <-chan map[string]int, done chan<- bool) {
    m := <-results                    // ownership lands here (receiver-owned)
    m["fox"]++                        // receiver MUTATES — this is what makes
                                      // the sender's later read a race
    fmt.println("fox count: {m["fox"]}")
    done <- true                      // send site [S3]
}

fn main() {
    agg := map[string]int{}
    for w in strings.split(corpus, " ") {
        agg[w]++
    }

    results := make(chan map[string]int, 1)
    done := make(chan bool, 1)
    task sink(results, done)          // spawn site [S1]

    results <- move agg               // send site [S2] — LEGAL owned move;
                                      // freeze begins (reads AND writes)

    n := len(agg)                     // VIOLATION (A1b, read-form): NO write
                                      // here — a pure read through a frozen
                                      // binding; races with sink's m["fox"]++

    fmt.println("sent {n} words")     // (using n is fine; the read above
                                      // is the violation site)
    <-done
}
