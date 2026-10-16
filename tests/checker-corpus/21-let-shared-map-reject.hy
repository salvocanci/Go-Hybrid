// ============================================================================
// 21-let-shared-map-reject — Checker corpus #21 (regression for the `let`
// class-4 immutability soundness bug, issue #12; added AFTER the checker
// existed — a corpus GROWTH per BOUNTY.md's "adversarial corpus" track and
// issue #6, not a rewrite of a pre-registered verdict).
//
// PURPOSE: pin that a `let`-bound MUTABLE GC value does NOT become
// immutable-by-type. SPEC-LANGUAGE.md T22 is explicit: `let x = e` creates
// an immutable BINDING, but it is SHALLOW — "interior mutation through an
// alias is still possible"; only `const` is deeply immutable. The O4 class-4
// row names "const values", not `let` values. A `let`-bound map is
// therefore a named mutable GC value (§9.4: "not sendable") and MUST be
// rejected at a spawn site.
//
// Before the issue-#12 fix, `LocalKind::is_immutable()` (Let | Const) fed
// `Binding.immutable`, and sendability.rs short-circuited every
// classification to `Outcome::Ok` when it was set — so this program was
// ACCEPTED (0 diagnostics) and the emitted Go raced (`go run -race`:
// DATA RACE on the shared map, plus a `concurrent map writes` runtime
// fatal). The `var`/`:=` twin (01) was always rejected; only the `let`
// spelling laundered the map into class 4.
//
// ---- Tier-0 rule set applied ----
// `shared` is a map[string]int — a named mutable GC value. `let` is
// shallow (T22), so it is NOT class 4. Not channel/atomic, not moved, not
// `managed` -> NOT SENDABLE. VIOLATION (A1c) at the spawn site.
//
// ---- Expected verdict ----
// EXPECTED-VERDICT: REJECT A1c
//   REJECT — A1c. The fix: `process_local` grants the class-4 immutability
//   shortcut only to `LocalKind::Const`, never to `LocalKind::Let`.
// ============================================================================

fn worker(m map[string]int) {
    for i in 0..1000 {
        m["k"] = i
    }
}

fn main() {
    let shared = map[string]int{"k": 0}
    task worker(shared)               // SPAWN SITE — VIOLATION (A1c):
    for i in 0..1000 {                // `shared` is a mutable GC map; `let`
        shared["k"] = i               // is shallow (T22), so it is NOT
    }                                 // class-4 immutable
}
