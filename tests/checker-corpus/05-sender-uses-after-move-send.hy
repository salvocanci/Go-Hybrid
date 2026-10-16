// ============================================================================
// 05-sender-uses-after-move-send — Checker corpus #5 (pre-registered BEFORE
// any checker exists; human ruling 2026-10-12, QUESTIONS.md Q1).
//
// PURPOSE: the G0-named adversarial #2: "sender-keeps-using-after-send" —
// the freeze-after-send reading (A1b) made concrete. The send itself is
// LEGAL (an owned `move`, A1c route 2); the violation is what the sender
// does afterwards. This is the program that distinguishes reading (b) from
// reading (a): under (a) the sender may keep using the value; under (b)+(c)
// the move transferred ownership and every later use is use-after-move.
//
// The ported Go habit under test: "send the buffer, then patch/log the
// local copy" — harmless-looking daily Go, and exactly what (b) forbids
// once `move` has handed the value away.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `agg` (map[string]int — main-local until the MOVE),
//   `results`/`done` (channels), `w` (string), receiver-side `m` (map —
//   owned by the RECEIVER after the move lands).
// Layer 2 (Rust-side owned): none — this move is over an L1 GC value: a
//   DISCIPLINE transfer, not a memory-safety one (see verdict note).
// Layer 3 (boundary handles): none.
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   [S1] `task sink(results, done)` — channels: sendable (safe-by-type).
//   [S2] `results <- move agg` — OWNED MOVE: sendable (A1c route 2). The
//        A1b freeze starts HERE: `agg` — and every alias of it — must not
//        be used again by this task.
//   [S3] `done <- true` in sink — sendable.
//   Receiver side: `m := <-results` then reads — LEGAL: ownership arrived
//   with the move; the receiver is the new owner and may do anything.
//
// ---- Expected verdict (PRE-REGISTERED 2026-10-12, before any checker) ----
// EXPECTED-VERDICT: REJECT A1b
//   REJECT — A1b (freeze-after-send / use-after-move). Not contested: the
//   ruling adopted (c)+ (b) precisely so move semantics stay complete
//   ("(c) alone without freeze = move semantics incomplete", QUESTIONS.md).
//   REQUIRED MUTANT (the checker must ALSO reject): the alias form —
//   `m2 := agg` before the send, `m2["x"] = 1` after. A freeze that
//   ignores aliases is a no-op on GC values.
//   HONESTY NOTE: over a GC map the use-after-move cannot dangle — the
//   rejection is the discipline guarantee (single logical owner), not
//   memory safety. Clean twin: 16 (same send shape, discipline kept).
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

const corpus = "the quick brown fox jumps over the lazy dog the fox runs hybrid"

fn sink(results <-chan map[string]int, done chan<- bool) {
    m := <-results                    // ownership lands here (receiver-owned)
    fmt.println("words counted: {len(m)}")  // LEGAL: sink owns the map now
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

    results <- move agg               // send site [S2] — LEGAL owned move
                                      // (A1c route 2); the A1b freeze begins
                                      // here: agg + all aliases are done

    agg["total"] = len(agg)           // VIOLATION (A1b): use-after-move —
                                      // ownership left with the send; the
                                      // "patch the local copy" Go habit

    <-done
}
