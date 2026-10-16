// ============================================================================
// 17-atomic-channel-immutable — Checker corpus #17 (pre-registered BEFORE
// any checker exists; human ruling 2026-10-12, QUESTIONS.md Q1).
//
// PURPOSE: positive control (iv): sharing across tasks through the three
// safe-by-type mediators — ATOMIC (a shared counter), CHANNEL (results
// fan-in), and IMMUTABLE (a const table read by every task). Zero
// `managed`. This pins reading (c)'s LEGAL side: strictness rejects
// 01/03/04 only because a mediator exists for every legitimate sharing
// need — a checker that also rejects this has no legal sharing story left.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `thresholds` (CONST composite — immutable by
//   construction; see OQ5), `hits` (atomic.int64 — the shared MUTABLE
//   state, atomic-mediated), `samples` (channel), `s`/`total`/`ms`/
//   `above` (locals).
// Layer 2 (Rust-side owned): none.
// Layer 3 (boundary handles): none (sync/atomic is a GO package; call-level
//   interop after Go-source emission, Spike 2 — not the checked Rust
//   boundary).
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   [S1] n_probes x `task probe(i, calls, &hits, samples)`:
//        i (int copy), `samples` (channel): sendable.
//        `&hits` — pointer to an ATOMIC-typed value: the checked property
//        is the pointee's TYPE (atomic = safe-by-type): sendable (OQ6 —
//        SPEC-LANGUAGE must pin pointer-to-atomic sendability explicitly).
//        `thresholds` — const composite captured read-only: immutable
//        (OQ5 — const-composite immutability must be pinned).
//   [S2] `samples <- sample{...}` — fresh struct literal, no aliases:
//        sendable (all readings).
//   [S3] `hits.add(1)` — atomic op: the mediated mutation route itself.
//
// ---- Expected verdict (PRE-REGISTERED 2026-10-12, before any checker) ----
// EXPECTED-VERDICT: ACCEPT
//   ACCEPT — 0 annotations, 0 managed. CONTINGENT on two flagged decisions
//   (not silently decided): OQ5 const composites count as immutable for
//   A1c, and OQ6 borrows of atomic-typed values are sendable. If either
//   resolves the other way, this program is amended by logged entry, not
//   silently re-verdicted.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

import "sync/atomic"

const n_probes = 4
const calls = 1000

const thresholds = [10, 50, 250, 1000]  // const composite: immutable by
                                        // construction (OQ5)

struct sample {
    probe int
    above int
}

fn measure(i int, c int) int {          // stand-in for a latency sample
    return (i * 137 + c * 31) % 1200    // deterministic pseudo-metrics
}

fn probe(id int, n int, hits *atomic.int64, samples chan<- sample) {
    var above int
    for c in 0..n {
        ms := measure(id, c)
        if ms > thresholds[3] {         // immutable read: safe (OQ5)
            hits.add(1)                 // [S3] ATOMIC-mediated share:
            above++                     // safe-by-type
        }
    }
    samples <- sample{probe: id, above: above}  // send site [S2]: fresh
}

fn main() {
    var hits atomic.int64               // shared mutable state — via ATOMIC
    samples := make(chan sample, n_probes)

    for i in 0..n_probes {
        task probe(i, calls, &hits, samples)  // spawn site [S1]
    }

    var total int                       // fan-in: single-task merge
    for _ in 0..n_probes {
        s := <-samples
        total += s.above
    }

    slow := thresholds[3]
    fmt.println("calls over {slow}ms: atomic={hits.load()} reported={total}")
}
