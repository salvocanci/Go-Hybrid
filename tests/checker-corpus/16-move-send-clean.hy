// ============================================================================
// 16-move-send-clean — Checker corpus #16 (pre-registered BEFORE any
// checker exists; human ruling 2026-10-12, QUESTIONS.md Q1).
//
// PURPOSE: positive control (iii): the owned-`move` send route kept clean —
// the positive twin of 05. A producer loop move-sends freshly-built
// batches; the sender never touches a moved value again. Every send is
// legal under A1c route 2 with A1b satisfied. Must ACCEPT with zero
// `managed`: this is the third legal route from the Q1 ruling's diagnostic
// ("send ownership with `move`") in its disciplined form.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `b` (fresh batch struct per iteration — owns its
//   `rows` slice; move-sent), `batches`/`acks` (channels), `rows` (local),
//   `seq` (int), receiver-side `b` (owned by the consumer after the move).
// Layer 2 (Rust-side owned): none.
// Layer 3 (boundary handles): none.
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   [S1] `task consumer(batches, acks)` — channels: sendable (safe-by-type).
//   [S2] n_batches x `batches <- move b` — OWNED MOVE of a fresh local;
//        the sender never touches `b` again: A1b satisfied. Sendable.
//   [S3] `acks <- b.seq` in consumer — int: sendable.
//   Receiver side: `for b in batches` — the consumer owns each moved batch;
//        reads and helper calls on it are uses of the new owner.
//
// ---- Expected verdict (PRE-REGISTERED 2026-10-12, before any checker) ----
// EXPECTED-VERDICT: ACCEPT
//   ACCEPT — 0 annotations, 0 managed. Guards the `move` route: the checker
//   must accept move-sends (05 rejects only the USE-AFTER-MOVE, not the
//   move itself — a checker that rejects [S2] is over-strict: bug in the
//   checker, not the corpus).
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

struct row {
    key string
    val int
}

struct batch {
    seq  int
    rows []row
}

const n_batches = 8

fn build_batch(seq int) batch {       // FRESH struct each call (owns its rows)
    var rows []row
    for i in 0..4 {
        rows = append(rows, row{key: "k{seq}-{i}", val: seq * 10 + i})
    }
    return batch{seq: seq, rows: rows}
}

fn persist(rows []row) int {          // single-task helper: rows kept
    return len(rows)
}

fn consumer(batches <-chan batch, acks chan<- int) {
    for b in batches {
        persist(b.rows)               // the consumer owns each moved batch
        acks <- b.seq                 // send site [S3]: int — sendable
    }
}

fn main() {
    batches := make(chan batch, 8)
    acks := make(chan int, 8)

    task consumer(batches, acks)      // spawn site [S1]: channels — sendable

    for seq in 0..n_batches {
        b := build_batch(seq)         // fresh local, owned by this iteration
        batches <- move b             // send site [S2]: OWNED MOVE (A1c
    }                                 // route 2); sender never touches `b`
                                      // again — A1b satisfied
    close(batches)
    for _ in 0..n_batches { <-acks }

    fmt.println("ingested {n_batches} batches")
}
