// ============================================================================
// 09-a3-map-slot-valid — Checker corpus #9 (pre-registered BEFORE any
// checker exists; human ruling 2026-10-12, QUESTIONS.md Q1).
//
// PURPOSE: the VALID A3 twin of 08 — identical program except the map
// INSERT comes AFTER the loan's last use. The non-lexical window
// (creation → last use) is the whole difference between REJECT and
// ACCEPT; the checker's window analysis must be line-exact. This is also
// a positive-control guard against over-strictness: a checker that
// rejects ANY slot-borrow near a map mutation (block-scoped windows
// instead of non-lexical ones) fails this program — that would be a bug
// in the checker, not the corpus.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `e` (env), `e.services` (map[string]service — the
//   arena), `svc` (the *service map-slot loan), `existing`/`fresh`
//   (strings), `n` (int).
// Layer 2 (Rust-side owned): none.
// Layer 3 (boundary handles): none.
//
// ---- Loans traced (non-lexical windows) ----
//   L1 = `svc := &e.services[existing]` — UNIQUE map-slot loan.
//   Window: creation → last use (`svc.tag = "scaled"`, TWO lines down).
//   NO map insert/delete occurs inside the window — the insert at the
//   `e.services[fresh] = ...` line comes AFTER L1 died. A3 satisfied
//   (this is spike-6 08's connect shape in a different domain: the
//   "creation → last use, no map ops inside" trace).
//   Map READS elsewhere (`len(e.services)`) are copies (A4) — not loans.
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   NONE — single-task program.
//
// ---- Expected verdict (PRE-REGISTERED 2026-10-12, before any checker) ----
// EXPECTED-VERDICT: ACCEPT
//   ACCEPT — A3 window respected (insert after last use). Guards the
//   non-lexical half of A3: the rule must kill 08 WITHOUT killing this.
//   Also exercises A4 in passing (map reads are copies).
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

fn scale_then_register(e *env, existing string, n int, fresh string) {
    svc := &e.services[existing]       // LOAN L1: map-slot borrow (creation)
    svc.replicas = n                   // (inside the window)
    svc.tag = "scaled"                 // L1 LAST USE — the window ends here
    e.services[fresh] = service{replicas: 1, tag: "new"}
                                       // INSERT after L1 died: LEGAL (A3)
}

fn main() {
    e := env{services: map[string]service{
        "frontend": {replicas: 2, tag: "prod"},
        "api":      {replicas: 3, tag: "prod"},
    }}
    scale_then_register(e, "frontend", 5, "cache")
    fmt.println("services: {len(e.services)}")
}
