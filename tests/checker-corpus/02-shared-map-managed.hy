// ============================================================================
// 02-shared-map-managed — Checker corpus #2 (pre-registered BEFORE any
// checker exists; human ruling 2026-10-12, QUESTIONS.md Q1).
//
// PURPOSE: the `managed` rewrite of 01 — the first fix-it route from the Q1
// ruling's diagnostic shape ("this map is shared across tasks; wrap it in
// `managed`, or send ownership with `move`"). The program is IDENTICAL to
// 01 except: the shared region is wrapped in a `managed` block (plus this
// AMENDMENT 2026-10-14 (row 14, discussion #4): the payload form is now
// REQUIRED (fail-closed) — this program gained reason+category+ticket;
// the bare form now rejects with HYB-E0003. Verdict unchanged.
// comment). This pins the MINIMAL semantic diff of the escape hatch — one
// wrapper flips the verdict and nothing else changes.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `counts` (map[string]int — MUTABLE, shared, now a
//   MANAGED value: the hatch is a compile-time permit + lint, not a
//   synchronization mechanism), `words` (main-local; chunks are fresh
//   copies), `chunk` (fresh, move-sent), `done` (channel).
// Layer 2 (Rust-side owned): none.
// Layer 3 (boundary handles): none.
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   [S1] n_shards x `task tally(move chunk, counts, done)` INSIDE `managed`:
//        counts is a MANAGED value → sendable (A1c escape route 3). The
//        site is PERMITTED and LINTED (the lint output is part of the
//        expected verdict — Q1 item 4: the hatch must be greppable,
//        auditable, countable per project via --report-managed).
//   [S2] `done <- true` — sendable (all readings).
//
// ---- Expected verdict (PRE-REGISTERED 2026-10-12, before any checker) ----
// EXPECTED-VERDICT: ACCEPT-MANAGED
//   ACCEPT-MANAGED — A1c escape route 3, with the managed LINT expected:
//     lint[managed]: 1 region, 4 permitted spawn sites
//       (map[string]int shared across tasks) — counted by --report-managed
//   HONESTY NOTE (pre-registered): ACCEPT-MANAGED is the CHECKER verdict
//   only. `managed` suppresses the sendability rejection; it does NOT
//   remove Go's own concurrent-map-write fatal — this exact program can
//   still panic at runtime. The runtime-honest managed shape adds a lock
//   (see 18); the Tier-0-native shape needs no hatch at all (see 15).
// RUNTIME-HAZARD: concurrent map writes (Go fatal, pre-registered above) —
//   the differential accept-side accepts exit 0 OR this documented fatal.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 1 (the point).
// ============================================================================

const n_shards = 4

const corpus = "the quick brown fox jumps over the lazy dog " +
    "the dog barks and the fox runs hybrid quick hybrid"

fn chunk_of(words []string, i int, n int) []string {
    size := (len(words) + n - 1) / n
    a := i * size
    b := min(a + size, len(words))
    return append([]string{}, words[a:b]...) // fresh copy per task
}

fn tally(shard []string, counts map[string]int, done chan<- bool) {
    for w in shard {
        counts[w]++
    }
    done <- true                       // send site [S2]
}

fn main() {
    words := strings.split(corpus, " ")

    managed("shards tallied under the runner mutex", "mutex", "CORPUS-02") { // hatch:
        counts := map[string]int{}     // counted per project (--report-managed)

        done := make(chan bool, n_shards)
        for i in 0..n_shards {
            chunk := chunk_of(words, i, n_shards)
            task tally(move chunk, counts, done) // spawn site [S1]:
        }                                         // PERMITTED (managed)
        for _ in 0..n_shards { <-done }

        fmt.println("unique words: {len(counts)}")
        n := counts["hybrid"]
        fmt.println("'hybrid' appears {n} times")
    }
    // `managed` is a compile-time marker over a lexical region: every
    // spawn/send site inside is permitted + linted. Spawned tasks may
    // outlive the block — the permit is static, not a runtime scope.
}
