// ============================================================================
// 03-pool-shared-struct-unguarded — Checker corpus #3 (pre-registered BEFORE
// any checker exists; human ruling 2026-10-12, QUESTIONS.md Q1).
//
// PURPOSE: tripwire case (ii), UNGUARDED shape: "a worker pool mutating a
// shared struct". Spawned workers mutate `stats.processed`/`stats.failures`
// through a shared pointer with no synchronization at all — the shape that
// "worked in testing". The checker must reject it at the spawn site, before
// any race detector gets a chance.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `stats` (pool_stats — MUTABLE struct, shared), the
//   `&stats` loan created at the spawn, `jobs`/`done` (channels), `url`
//   (string — immutable), `ok`/`i` (value copies).
// Layer 2 (Rust-side owned): none.
// Layer 3 (boundary handles): none.
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   [S1] n_workers x `task worker(i, jobs, &stats, done)`:
//        i (int copy), jobs/done (channels) — sendable.
//        &stats — a live BORROW of a MUTABLE GC struct, shared across
//        tasks: not safe-by-type, not an owned move, not `managed` → NOT
//        SENDABLE. VIOLATION (A1c). (Even reading (a)'s literal text —
//        "GC value with no live lexical borrow" — trips here: the sent
//        value IS a borrow; but (a)-as-Go-compatibility would wave it
//        through, because Go sends pointers to goroutines all day. The
//        (c)+(b) ruling does not.)
//   [S2] `jobs <- url` — string (immutable): sendable.
//   [S3] `done <- true` — sendable.
//   The `stats.processed++` lines are a REAL data race at runtime — the
//   verdict is decided at [S1], before it matters.
//
// ---- Expected verdict (PRE-REGISTERED 2026-10-12, before any checker) ----
// EXPECTED-VERDICT: REJECT A1c
//   REJECT — A1c (mutable GC value shared across tasks as a live borrow).
//   NOT contested: unsynchronized shared mutation; no reading of A1 that
//   preserves the ruling's race-prevention claim can accept this.
//   Reading-distinguishing power: distinguishes (c) from (a) and (b)-alone
//   (the sender — main — never mutates `stats` after spawn, so (b)-alone's
//   freeze would not fire; only (c) rejects the spawn). Legal routes:
//   `managed` (18 — the managed twin, lock included), channel merge of
//   per-worker stats (15), or `move` when the pool is done.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0 (it needs one, or a
//   redesign — that is the tripwire measurement, not a corpus defect).
// ============================================================================

const n_workers = 4

const seed_urls = [
    "https://example.com/a", "https://example.com/b", "https://example.com/c",
    "https://example.com/d", "https://example.com/e", "https://example.com/f",
]

struct pool_stats {
    processed int
    failures  int
}

fn fetch(url string) bool {           // stand-in for a real HTTP fetch
    return len(url) % 3 != 0          // deterministic pseudo-result
}

fn worker(id int, jobs <-chan string, stats *pool_stats, done chan<- bool) {
    for url in jobs {
        ok := fetch(url)
        stats.processed++             // UNGUARDED shared mutation — data race
        if !ok {
            stats.failures++          // (rejected at [S1] before it can fire)
        }
    }
    done <- true                      // send site [S3]
}

fn main() {
    jobs := make(chan string, len(seed_urls))
    stats := pool_stats{}             // zero-value init (no nil)
    done := make(chan bool, n_workers)

    for i in 0..n_workers {
        task worker(i, jobs, &stats, done)  // SPAWN SITE [S1] — VIOLATION
    }                                        // (A1c): `&stats` is a live borrow
                                             // of a mutable GC struct, shared
    for _, url in seed_urls {
        jobs <- url                   // send site [S2]: string — sendable
    }
    close(jobs)

    for _ in 0..n_workers { <-done }

    fmt.println("processed={stats.processed} failures={stats.failures}")
}
