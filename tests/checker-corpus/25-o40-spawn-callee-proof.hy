// ============================================================================
// 25-o40-spawn-callee-proof — Checker corpus #25 (adoption-audit finding F1,
// reproduced on main 2026-10-14; the audit ran on a pre-shadowing-fix
// checkout, the undeclared-callee half still reproduces at HEAD).
//
// PURPOSE: pin the O4.0 spawn-callee PROOF — the checker must classify WHAT
// would run in the new task, not only the arguments. Before this corpus
// landed, `lib.rs`'s O4.0 site checked only `args`: a closure callee
// (`task gap()`) crossed with its captured environment and zero diagnostics
// fired, and an undeclared callee (`task mystery(1)`) passed silently —
// both fail-open shapes under the FC rule.
//
// ---- Tier-0 rule set applied ----
// O4.0 (spawn-callee proof): a spawn is proven only when the callee
// resolves to a declared top-level `fn` — a static call where nothing but
// the arguments crosses.
//   [S1] `task gap()` — `gap` is a closure binding capturing the live map
//        `shared`. Spawning it shares every capture with the new task
//        (A5 perimeter): REJECT under A1c (E3001, value class "closure").
//   [S2] `task mystery(1)` — the name resolves to nothing: fail-closed
//        unproven (O4.9, E3005, tier0 rule FC). Silently passing was the
//        pre-fix behavior; the FC rule forbids it.
//   [S3] `task worker(1)` — declared top-level fn: PROVEN (the control;
//        guarded by hy-check/tests/callee_and_nil.rs, which also pins the
//        ACCEPT side and the managed-hatch semantics).
//
// ---- Expected verdict (registered 2026-10-14 with the fix batch) ----
// EXPECTED-VERDICT: REJECT A1c
//   REJECT — A1c via the O4.0 spawn-callee proof (S1 fires first by span:
//   E3001 with the closure class; S2 adds HYB-E3005/FC). Legal routes: spawn
//   a declared top-level fn (S3), or take the explicit auditable hatch
//   (`managed("why", "actor")`) for a deliberate actor-loop closure.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0 — the point: as written it
//   NEEDS one (or a top-level-fn redesign). No expected runtime output is
//   pinned: these are checker-verdict tests, not execution tests.
// ============================================================================

const budget = 3

fn worker(x int) int {
    return x + budget
}

fn main() {
    shared := map[string]int{}
    gap := fn() { shared["hits"]++ }
    task gap()        // SPAWN SITE [S1] — VIOLATION: closure callee (A5)
    task mystery(1)   // SPAWN SITE [S2] — VIOLATION: undeclared callee (FC)
    task worker(1)    // control: declared top-level fn — proven
}
