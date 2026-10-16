// ============================================================================
// 15-fanin-per-task-state — Checker corpus #15 (pre-registered BEFORE any
// checker exists; human ruling 2026-10-12, QUESTIONS.md Q1).
//
// PURPOSE: positive control (i) — and the OTHER side of the tripwire: the
// SAME problem as 01 (parallel word count) solved the Tier-0-native way —
// per-task state, owned-move sends, single-task merge. ZERO `managed`,
// ZERO annotations. Strict rules must NOT reject this: it is the
// idiomatic-safe fan-in/worker pattern, and rejecting it would mean the
// strictness left no legal fast path (the Borgo ceiling by another route
// — spike-6 risk #3). This is the program the tripwire protects.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `words` (main-local; NEVER crosses a spawn/send
//   site — chunks are fresh copies), `chunk` (fresh per-iteration slice,
//   move-sent), `local` (per-task map — NO alias exists outside its task,
//   ever), `results` (channel), `merged` (main-local map),
//   `shard_counts`/`w`/`n` (received/loop locals).
// Layer 2 (Rust-side owned): none.
// Layer 3 (boundary handles): none.
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   [S1] n_shards x `task tally(move chunk, results)`:
//        chunk — fresh local, OWNED MOVE: sendable (A1c route 2).
//        results — channel: sendable (safe-by-type).
//   [S2] `results <- move local` — OWNED MOVE of per-task state; the
//        sender (the worker) never touches `local` again: A1b satisfied.
//        Sendable.
//   [S3] merge loop — single-task; map reads are COPIES (A4), not loans.
//
// ---- Expected verdict (PRE-REGISTERED 2026-10-12, before any checker) ----
// EXPECTED-VERDICT: ACCEPT
//   ACCEPT — 0 annotations, 0 managed. REQUIRED for the tripwire's healthy
//   side: any checker that rejects this is over-strict — a bug in the
//   checker per the corpus contract, not a reason to amend this verdict.
//   (Also the clean twin of 05's move discipline: same send shape, the
//   sender simply stops after the send.)
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
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

fn tally(shard []string, results chan<- map[string]int) {
    local := map[string]int{}         // PER-TASK state: no alias outside
    for w in shard {                  // this task, ever
        local[w]++
    }
    results <- move local             // send site [S2]: owned move; the
}                                      // sender never touches it again (A1b)

fn main() {
    words := strings.split(corpus, " ")
    results := make(chan map[string]int, n_shards)

    for i in 0..n_shards {
        chunk := chunk_of(words, i, n_shards) // fresh copy — no view of
        task tally(move chunk, results)       // main's `words` crosses
    }                                          // spawn site [S1]

    merged := map[string]int{}        // main-local: the merge is single-task
    for _ in 0..n_shards {
        shard_counts := <-results     // ownership of each moved map lands
        for w, n in shard_counts {    // reads are copies (A4)
            merged[w] += n
        }
    }

    fmt.println("unique words: {len(merged)}")
    n := merged["hybrid"]
    fmt.println("'hybrid' appears {n} times")
}
