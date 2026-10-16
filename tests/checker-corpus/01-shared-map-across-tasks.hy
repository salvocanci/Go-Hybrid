// ============================================================================
// 01-shared-map-across-tasks — Checker corpus #1 (pre-registered BEFORE any
// checker exists; human ruling 2026-10-12, QUESTIONS.md Q1 item 2: "write
// the adversarial programs before the checker lands, and treat them as the
// spec"). No compiler exists; this is an expected-verdict spec, not code.
//
// PURPOSE: tripwire case (i) exactly as the human named it: "a shared map
// across tasks (plain Go map read+written by spawned tasks)". Naive
// parallel word-count aggregation — the most common first-draft Go shape
// for "count things in parallel". Spike 6 called this the #1 corpus gap:
// its own ten programs "cannot distinguish the three readings of the
// sendability rule" because none of them shares a mutable map.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `counts` (map[string]int — MUTABLE, intended to be
//   shared across tasks), `words` (main-local, never crosses a spawn/send
//   site — chunks are fresh copies), `chunk` (fresh per-iteration slice,
//   move-sent), `done` (channel — concurrency-safe BY TYPE), `w` (string —
//   immutable).
// Layer 2 (Rust-side owned): none.
// Layer 3 (boundary handles): none.
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   [S1] n_shards x `task tally(move chunk, counts, done)`:
//        chunk — fresh local sent as an OWNED MOVE: sendable (A1c route 2).
//        done  — channel: sendable (A1c safe-by-type).
//        counts — MUTABLE GC map: not channel/atomic/immutable, not moved,
//        not `managed` → NOT SENDABLE. VIOLATION (A1c).
//   [S2] `done <- true` — bool literal: sendable (all readings).
//   Post-join `counts` reads in main: single-task, after the join — legal,
//   but unreachable: [S1] rejects the program first.
//
// ---- Expected verdict (PRE-REGISTERED 2026-10-12, before any checker) ----
// EXPECTED-VERDICT: REJECT A1c
//   REJECT — A1c (sendability, safe-by-type reading; QUESTIONS.md Q1 ruling
//   (c)+(b)). NOT contested: unsynchronized mutable shared state is the
//   shape reading (c) exists to reject — and note real Go PANICS on this
//   shape too (concurrent map writes are a runtime fatal): the strict
//   verdict agrees with the Go runtime, just earlier.
//   Reading-distinguishing power: distinguishes (c) from (a) AND from (b)
//   (see VERDICTS.md). Legal routes for the diagnostic: `managed` (02, the
//   managed twin), per-task + channel merge (15, zero managed), `move` when
//   the sender is done (05/16 show both edges of that route).
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0 — the point: as written it
//   NEEDS one (or a redesign). No expected runtime output is pinned: these
//   are checker-verdict tests, not execution tests.
// ============================================================================

const n_shards = 4

const corpus = "the quick brown fox jumps over the lazy dog " +
    "the dog barks and the fox runs hybrid quick hybrid"

fn chunk_of(words []string, i int, n int) []string {
    size := (len(words) + n - 1) / n
    a := i * size
    b := min(a + size, len(words))
    return append([]string{}, words[a:b]...) // FRESH copy: no view of main's
}                                            // `words` crosses the spawn

fn tally(shard []string, counts map[string]int, done chan<- bool) {
    for w in shard {
        counts[w]++                    // shared-map write (Go: runtime fatal;
    }                                  // Hybrid: rejected at spawn site [S1])
    done <- true                       // send site [S2]: token — sendable
}

fn main() {
    counts := map[string]int{}
    words := strings.split(corpus, " ")

    done := make(chan bool, n_shards)
    for i in 0..n_shards {
        chunk := chunk_of(words, i, n_shards) // fresh slice per iteration
        task tally(move chunk, counts, done)  // SPAWN SITE [S1] — VIOLATION
    }                                         // (A1c): `counts` is a mutable
                                              // GC map shared across tasks
    for _ in 0..n_shards { <-done }           // join by counting (no WaitGroup)

    fmt.println("unique words: {len(counts)}")
    n := counts["hybrid"]
    fmt.println("'hybrid' appears {n} times")
}
