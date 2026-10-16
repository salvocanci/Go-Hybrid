// ============================================================================
// 08-a3-map-slot-invalidated — Checker corpus #8 (pre-registered BEFORE any
// checker exists; human ruling 2026-10-12, QUESTIONS.md Q1).
//
// PURPOSE: exercise A3 on its REJECT side: a map-slot borrow (`&m[k]`)
// whose non-lexical live window contains a map INSERT — the rehash that
// may move the slot. Shape: a deploy tool that scales an existing service
// while registering a fresh one in the same function. Spike-6 08 traced
// the LEGAL twin (graph connect: "no map insert/delete occurs inside the
// window"); this is the invalidation the window check exists to catch.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `e` (env — GC), `e.services` (map[string]service —
//   the arena owning the services), `svc` (the *service map-slot loan),
//   `existing`/`fresh` (strings), `n` (int).
// Layer 2 (Rust-side owned): none.
// Layer 3 (boundary handles): none.
//
// ---- Loans traced (non-lexical windows) ----
//   L1 = `svc := &e.services[existing]` — UNIQUE map-slot loan.
//   Window: creation → last use (`svc.tag = "scaled"`).
//   The INSERT at the `e.services[fresh] = ...` line falls INSIDE the
//   window → A3 VIOLATION (any map insert/delete invalidates live slot
//   loans: a rehash may move the slot).
//   Codegen note (spike-6 A3): Go has no `&m[k]`; the compiler lowers
//   slot-borrows to read-modify-write — semantics identical, the check is
//   still required.
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   NONE — single-task program; the violation is loan invalidation.
//
// ---- Expected verdict (PRE-REGISTERED 2026-10-12, before any checker) ----
// EXPECTED-VERDICT: REJECT A3
//   REJECT — A3 (map-slot loan invalidated by an insert inside the live
//   window). Not contested: spike-6 pinned the semantics ("invalidated by
//   any map insert/delete in the live window"); this program is its
//   negative test. Fix: reorder — finish the slot mutation before ANY map
//   insert/delete (09 is the legal twin with ONE line moved), or
//   copy-out / modify / store-back (reads are copies, A4).
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

fn scale_and_register(e *env, existing string, n int, fresh string) {
    svc := &e.services[existing]       // LOAN L1: map-slot borrow (creation)
    e.services[fresh] = service{replicas: 1, tag: "new"}
                                       // VIOLATION (A3): map INSERT inside
                                       // L1's live window — rehash risk
    svc.replicas = n                   // L1 use — AFTER the insert
    svc.tag = "scaled"                 // L1 LAST USE: window ends here
}

fn main() {
    e := env{services: map[string]service{
        "frontend": {replicas: 2, tag: "prod"},
        "api":      {replicas: 3, tag: "prod"},
    }}
    scale_and_register(e, "frontend", 5, "cache")
    fmt.println("services: {len(e.services)}")
}
