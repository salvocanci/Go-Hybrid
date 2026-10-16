// ============================================================================
// 29-a3-interproc-window.hy — Checker corpus #29 (added WITH the fix for
// soundness issue #111; the program was ACCEPT with 0 diagnostics on main).
//
// PURPOSE: exercise A3 on its REJECT side where the insert/delete does NOT
// sit lexically in the loaned function's own statement list. The direct
// twins already reject (corpus 08 = same-frame insert, HYB-E3102; the
// one-line direct-delete twin likewise) — this program proves the same
// runtime event seen through a CALLEE FRAME must reject too: `bump`'s
// insert rehashes the same backing store while `e`'s non-lexical slot-loan
// window (creation -> last use at `e.n = 9`) is live.
//
// Reported as issue #111 (2026-10-15) with three sibling forms — insert
// through a shallow alias and insert inside a closure body — plus a runtime
// wrong-result proof: a helper that DELETES the loaned key and the loan's
// store-back resurrects the deleted entry (`len after = 2`) in code the
// checker accepted. The fix matches A3 events across share-group peers,
// callee parameters (bounded, fail-closed), and closure call sites.
//
// ---- Loans traced (non-lexical windows) ----
//   L1 = `e := &m["a"]` — UNIQUE map-slot loan.
//   Window: creation -> last use (`e.n = 9`).
//   The INSERT executes inside `bump(m, "fresh")`, whose call sits INSIDE
//   the window — the callee's `m[k] = cell{n: 1}` invalidates L1 (O8: any
//   map insert/delete in the live window; no frame scoping in the rule).
//
// ---- Sendability / check sites ----
//   NONE — single-task program; the violation is loan invalidation.
//
// ---- Expected verdict (registered with the fix, 2026-10-15) ----
// EXPECTED-VERDICT: REJECT A3
//   REJECT — A3 (map-slot loan invalidated by an insert inside the live
//   window): the event is spelled one frame away but executes in the
//   window. Fix hint is the same as corpus 08's — reorder so the slot
//   mutation finishes before ANY insert/delete on the map, or copy-out /
//   modify / store-back (reads are copies, O9).
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

struct cell { n int }

fn bump(m map[string]cell, k string) {
    m[k] = cell{n: 1} // INSERT — executes inside main's loan window
}

fn main() {
    m := map[string]cell{"a": cell{n: 0}}
    e := &m["a"] // LOAN L1: map-slot borrow (creation)
    bump(m, "fresh") // call INSIDE the window — callee inserts (A3)
    e.n = 9 // L1 LAST USE: window ends here
}
