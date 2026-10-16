// ============================================================================
// 22-a1c-mapslot-loan-at-spawn — Checker corpus #22 (bounty track, issue #6:
// "grow the adversarial corpus"). Verdict derived BY HAND from VERDICTS.md's
// rule key + SPEC-LANGUAGE.md O3/O4 BEFORE this file was run through the
// checker; the checker run below only confirms agreement (per BOUNTY.md:
// "pay only after reproduction").
//
// PURPOSE: a genuinely untested intersection. 08/09 exercise map-slot
// borrows (O3 loan form 3) against A3 (insert/delete invalidation) — but
// always single-task. 01/03/04 exercise A1c sendability — but always on a
// plain pointer or map, never on a map-slot LOAN. Nothing in the corpus
// sends a live map-slot borrow itself into a `task` spawn argument list.
// Does the map-slot loan's special status (O3 form 3, O8) exempt it from
// ordinary A1c sendability, or does the checker treat it like any other
// mutable GC pointer at a check-site? This program pins the answer: NO
// special case — a map-slot loan is still a `*service` pointing at shared
// mutable GC state, and A1c's safe-by-type test runs on its TYPE exactly
// as it would for `&stats` in 03, regardless of how the pointer came to
// exist. The loan-liveness machinery (O2 "loans are function-local") never
// even gets a chance to fire a second diagnostic — the simpler sendability
// check rejects first, at the spawn site itself.
//
// RULE CITATION: A1c, "sendability, safe-by-type" (VERDICTS.md rule key;
// SPEC-LANGUAGE.md O4, §9.3) — reading (c)+(b), QUESTIONS.md Q1. The value
// at the check-site is `svc`, a map-slot borrow (O3 loan form 3, O8): it is
// not a channel/atomic/immutable value, not `move`d, not inside `managed`
// -> not sendable.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `e` (env — GC), `e.services` (map[string]service —
//   the arena), `svc` (the *service map-slot loan — LIVE at the spawn
//   site), `n` (int), `done` (channel).
// Layer 2 (Rust-side owned): none.
// Layer 3 (boundary handles): none.
//
// ---- Loans traced (non-lexical windows) ----
//   L1 = `svc := &e.services["frontend"]` — unique map-slot loan (O8).
//   L1 is still LIVE at the spawn site below (no read of `svc` happens
//   first) — the loan crosses into the task's argument list as-is.
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   [S1] `task bump(svc, n, done)`:
//        svc — LIVE map-slot loan, type `*service`: mutable GC pointer, not
//        channel/atomic/immutable, not `move`d, not `managed` -> NOT
//        SENDABLE. VIOLATION (A1c). (It is irrelevant here whether the
//        loan would also outlive its window across the concurrent task —
//        A1c rejects before loan-liveness analysis is reached.)
//        n — int copy: sendable. done — channel: sendable (safe-by-type).
//
// ---- Expected verdict (derived from VERDICTS.md rule key + SPEC O3/O4
// BEFORE running the checker) ----
// EXPECTED-VERDICT: REJECT A1c
//   REJECT — A1c (sendability, safe-by-type; see 03's identical pointer
//   shape). The map-slot provenance of `svc` (O3 form 3 / O8) does not
//   change its type (`*service`) and does not open an exemption: a loan is
//   still a pointer at a check-site. Not contested — same safe-by-type
//   test as 01/03/04, applied to a value class (map-slot loans) the
//   corpus had not yet sent across a spawn. Fix-it routes, in the rule's
//   own order: read the field BEFORE the spawn (a copy, A4 — see the legal
//   twin, 22), `move` the owning struct into the task, or `managed`.
//
// ---- Checker reproduction (per BOUNTY.md: pay only after reproduction) ----
//   `hyb check 22-a1c-mapslot-loan-at-spawn.hy --json` on the pinned
//   toolchain: verdict=reject, 1 error, tier0_rule=A1c, code=HYB-E3001 —
//   agrees with the hand-derived verdict above.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

struct service {
    replicas int
    tag      string
}

struct env {
    services map[string]service
}

fn bump(svc *service, n int, done chan<- bool) {
    svc.replicas += n
    done <- true
}

fn main() {
    e := env{services: map[string]service{
        "frontend": {replicas: 2, tag: "prod"},
    }}

    done := make(chan bool, 1)
    svc := &e.services["frontend"]   // LOAN L1: map-slot borrow (creation)
    task bump(svc, 3, done)          // VIOLATION (A1c): the LIVE loan `svc`
                                     // crosses spawn site [S1] as a plain
                                     // mutable GC pointer
    <-done
    updated := e.services["frontend"]
    fmt.println("replicas: {updated.replicas}")
}
