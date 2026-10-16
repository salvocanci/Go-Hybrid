// ============================================================================
// 07-a2-mutate-during-handle-loan — Checker corpus #7 (pre-registered BEFORE
// any checker exists; human ruling 2026-10-12, QUESTIONS.md Q1).
//
// PURPOSE: exercise A2 (the spike-added handle-loan rule) on its REJECT
// side: a MUTATING-mode call on a boundary handle while borrow-mode loans
// are live on the same handle. Shape: "flag the document while iterating
// it". Without A2 this is a Rust-side aliasing hole (spike-6 RESULTS:
// "a mutating call on the same handle during that window must be a compile
// error or 05-shaped code has a Rust-side aliasing hole").
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): the 71 B JSON text literal (crosses the ONE parse
//   call as a pinned (ptr,len) view, never stored).
// Layer 2 (Rust-side owned): the serde_json graphs — entirely behind the
//   Layer-3 handle, never manipulated directly.
// Layer 3 (boundary handles): `doc` = OWN handle (created by parse).
//   `for u in doc.array("users")?` — borrow-mode loans on `doc` (element
//   views `u`), LIVE for the whole loop. `doc.set(...)` = MUTATING-mode
//   call → conflicts with the live borrow-mode loans (A2).
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   NONE — single-task program; the violation is a handle-loan conflict.
//
// ---- Expected verdict (PRE-REGISTERED 2026-10-12, before any checker) ----
// EXPECTED-VERDICT: REJECT A2
//   REJECT — A2 (mutating-mode call on a handle during a live borrow-mode
//   loan window). Not contested: the rule was spike-added precisely for
//   this shape; spike-6 05 passes only because it never mutates doc during
//   iteration. Fix (the teaching fix-it): collect-then-mutate — boundary
//   reads are COPIES (A4), so gather what you need into locals, let the
//   loan die at the loop's last use (non-lexical), THEN make the mutating
//   call. See 12 for the legal after-the-loop mutation shape.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

import "rust/serde_json"

fn main() {
    doc := serde_json.parse(`{"users":[{"name":"ada","logins":5},{"name":"linus","logins":0}]}`)?

    for u in doc.array("users")? {    // borrow-mode loan on `doc`: LIVE for
        if u.int("logins")? == 0 {    // the whole loop (element views `u`)
            doc.set("pruned", true)?  // VIOLATION (A2): mutating-mode call
        }                             // on `doc` during the live loan window
    }

    fmt.println(serde_json.to_string_pretty(doc)?)
}
