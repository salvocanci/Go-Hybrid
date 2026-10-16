// ============================================================================
// 18-pool-shared-struct-managed — Checker corpus #18 (pre-registered BEFORE
// any checker exists; human ruling 2026-10-12, QUESTIONS.md Q1).
//
// PURPOSE: the `managed` rewrite of 04 — the ruling's named escape for the
// worker-pool tripwire shape ("wrap it in `managed`"). Identical to 04
// except: the shared region is wrapped in a `managed` block (plus this
// AMENDMENT 2026-10-14 (row 14, discussion #4): the payload form is now
// REQUIRED (fail-closed) — this program gained reason+category+ticket;
// the bare form now rejects with HYB-E0003. Verdict unchanged.
// comment). The mutex STAYS, deliberately: `managed` suppresses the A1c
// spawn-site rejection; it does not check anything in its place — inside
// the hatch the race story is Go's (DRF-SC), and this program is DRF
// because of the lock. managed + lock = the runtime-honest escape shape
// (contrast 02's honesty note: managed WITHOUT a lock on a shared map is
// still a Go runtime fatal).
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `stats` (pool_stats + sync.mutex — MUTABLE, shared,
//   now a MANAGED value), the `&stats` loans at the spawns, `jobs`/`done`
//   (channels), `url` (string), `p`/`f` (copies).
// Layer 2 (Rust-side owned): none.
// Layer 3 (boundary handles): none.
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   [S1] n_workers x `task worker(i, jobs, &stats, done)` INSIDE `managed`:
//        `&stats` — live borrow of a mutable GC struct → would be A1c, but
//        the site is inside the hatch: PERMITTED and LINTED.
//   [S2] `jobs <- url` — string: sendable.
//   [S3] `done <- true` — sendable.
//
// ---- Expected verdict (PRE-REGISTERED 2026-10-12, before any checker) ----
// EXPECTED-VERDICT: ACCEPT-MANAGED
//   ACCEPT-MANAGED — A1c escape route 3, with the managed LINT expected:
//     lint[managed]: 1 region, 4 permitted spawn sites
//       (*pool_stats shared across tasks; guarded by sync.mutex — Go's
//        DRF-SC story applies inside the hatch) — counted by
//        --report-managed
//   The lint text carries the guard note on purpose (Q1 item 4: the hatch
//   is a visible trust metric — an auditor reading --report-managed output
//   should see WHAT is shared and WHY it is believed safe).
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 1 (the point).
// ============================================================================

import "sync"

const n_workers = 4

const seed_urls = [
    "https://example.com/a", "https://example.com/b", "https://example.com/c",
    "https://example.com/d", "https://example.com/e", "https://example.com/f",
]

struct pool_stats {
    mu        sync.mutex       // guards processed / failures
    processed int
    failures  int
}

fn fetch(url string) bool {           // stand-in for a real HTTP fetch
    return len(url) % 3 != 0
}

fn worker(id int, jobs <-chan string, stats *pool_stats, done chan<- bool) {
    for url in jobs {
        ok := fetch(url)
        stats.mu.lock()
        stats.processed++
        if !ok {
            stats.failures++
        }
        stats.mu.unlock()
    }
    done <- true                      // send site [S3]
}

fn main() {
    managed("pool stats under the pool mutex (lock stays)", "mutex", "CORPUS-18") {
        jobs := make(chan string, len(seed_urls))
        stats := pool_stats{}         // counted by --report-managed
        done := make(chan bool, n_workers)

        for i in 0..n_workers {
            task worker(i, jobs, &stats, done)  // spawn site [S1]:
        }                                         // PERMITTED (managed)
        for _, url in seed_urls {
            jobs <- url                // send site [S2]: string — sendable
        }
        close(jobs)
        for _ in 0..n_workers { <-done }

        stats.mu.lock()
        p, f := stats.processed, stats.failures
        stats.mu.unlock()
        fmt.println("processed={p} failures={f}")
    }
}
