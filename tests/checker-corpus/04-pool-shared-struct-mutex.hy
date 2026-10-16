// ============================================================================
// 04-pool-shared-struct-mutex — Checker corpus #4 (pre-registered BEFORE any
// checker exists; human ruling 2026-10-12, QUESTIONS.md Q1).
//
// PURPOSE: tripwire case (ii), MUTEX-GUARDED shape — THE load-bearing
// contested program of this corpus. Exactly the code a Go programmer
// writes daily for "workers update shared stats": a struct guarded by
// sync.Mutex, spawned workers take &stats and lock around every access.
// The program is RACE-FREE, idiomatic, correct Go. Under the ruled reading
// (c) a mutex is not a channel/atomic/immutable, not an owned move, not
// `managed` — so the spawn site REJECTS it anyway.
//
// This is precisely what the human armed the tripwire for: "if a strict
// rule rejects code real Go programmers write daily ... we must know
// before we ship."
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `stats` (pool_stats incl. `mu sync.mutex` — MUTABLE
//   GC struct, mutex-guarded), the `&stats` loan at the spawn, `jobs`/
//   `done` (channels), `url` (string), `p`/`f` (value copies).
// Layer 2 (Rust-side owned): none.
// Layer 3 (boundary handles): none (sync is a GO package; call-level interop
//   after Go-source emission, Spike 2 — not the checked Rust boundary).
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   [S1] n_workers x `task worker(i, jobs, &stats, done)`:
//        &stats — live borrow of a MUTABLE GC struct: not safe-by-type, not
//        a move, not managed → NOT SENDABLE. VIOLATION (A1c) — CONTESTED
//        (see verdict). i/jobs/done: sendable.
//   [S2] `jobs <- url` — string: sendable.
//   [S3] `done <- true` — sendable.
//   Every field access is lock-guarded: race-free under Go's DRF-SC story.
//   Tier 0 does not credit locks (as ruled) — that is the whole question.
//
// ---- Expected verdict (PRE-REGISTERED 2026-10-12, before any checker) ----
// EXPECTED-VERDICT: REJECT A1c (CONTESTED)
//   REJECT — A1c, CONTESTED, strict verdict per corpus discipline (when two
//   readings genuinely disagree, the strict one wins and the disagreement
//   is recorded). The disagreement: an "externally synchronized" clause —
//   checker-verified exclusive access behind sync.mutex — is the strongest
//   candidate for a Tier-1 amendment; it is NOT Tier 0 as ruled (QUESTIONS.
//   md Q1: (c)+(b), no weakening). If that amendment ever lands, this
//   program's verdict flips to ACCEPT by logged amendment, and the
//   tripwire's as-written-managed number drops with it.
//   Reading-distinguishing power: accepts under (a) and under (b)-alone
//   (main never mutates after spawn — reads at the end only); ONLY (c)
//   rejects. This is the program that pins (c).
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

import "sync"

const n_workers = 4

const seed_urls = [
    "https://example.com/a", "https://example.com/b", "https://example.com/c",
    "https://example.com/d", "https://example.com/e", "https://example.com/f",
]

struct pool_stats {
    mu        sync.mutex       // guards processed / failures — idiomatic Go
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
        stats.processed++             // race-free: guarded (Go's DRF-SC story)
        if !ok {
            stats.failures++
        }
        stats.mu.unlock()
    }
    done <- true                      // send site [S3]
}

fn main() {
    jobs := make(chan string, len(seed_urls))
    stats := pool_stats{}             // zero mutex = ready (Go zero value)
    done := make(chan bool, n_workers)

    for i in 0..n_workers {
        task worker(i, jobs, &stats, done)  // SPAWN SITE [S1] — VIOLATION
    }                                        // (A1c), CONTESTED — see header

    for _, url in seed_urls {
        jobs <- url                   // send site [S2]: string — sendable
    }
    close(jobs)

    for _ in 0..n_workers { <-done }

    // read under the lock, as a Go programmer would:
    stats.mu.lock()
    p, f := stats.processed, stats.failures
    stats.mu.unlock()
    fmt.println("processed={p} failures={f}")
}
