// ============================================================================
// 11-a6-borrow-in-struct-field — Checker corpus #11 (pre-registered BEFORE
// any checker exists; human ruling 2026-10-12, QUESTIONS.md Q1).
//
// PURPOSE: exercise A6 on its REJECT side: a borrow-handle stored in a
// struct field. This is the #1 annotation-forcing shape in Rust (spike-6
// corpus observation: "no program stores a borrow in a struct field —
// that is WHY zero annotations is achievable"); Hybrid's answer is a
// rule, not lifetimes: fields hold owned values, GC values, ids, or
// own-handles — never borrows.
//
// TYPE NOTE: `serde_json.view` = the borrow-handle TYPE of an element view
// (spike-6 05's `u`): a call-scoped loan into the owning handle's array.
// The FIELD DECLARATION is the primary violation (A6 is a type rule);
// the assignment inside the loop is the second flagged site.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `trail` ([]string), the 71 B JSON text literal,
//   strings returned by `u.string(...)` (copied at the boundary).
// Layer 2 (Rust-side owned): the serde_json graphs — behind Layer 3 only.
// Layer 3 (boundary handles): `doc` = OWN handle (parse). `u` = borrow
//   handle (element view, loop-scoped loan). `auditor.cur` would hold a
//   borrow-handle — the A6-forbidden field.
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   NONE — single-task program; the violation is the field type.
//
// ---- Expected verdict (PRE-REGISTERED 2026-10-12, before any checker) ----
// EXPECTED-VERDICT: REJECT A6
//   REJECT — A6 (borrow-handle stored in a struct field). Not contested:
//   spike-6 recommends making it a rule ("fields hold owned values, GC
//   values, ids, or own-handles — never borrows"), and it is what keeps
//   loan windows function-local forever. Fix: process the element inside
//   the loop body (each iteration's loan dies at its last use); if you
//   need it later, store the INDEX or a copied value and re-view through
//   the handle when needed (id discipline — spike-6 08).
//
// ---- Annotations / managed ----
//   lifetime annotations: 0 — the fix is a rule, not a lifetime (that is
//   the point). `managed` blocks: 0.
// ============================================================================

import "rust/serde_json"

struct auditor {
    trail []string
    cur   serde_json.view     // VIOLATION (A6): borrow-handle as a FIELD —
}                             // fields hold owned / GC / id / own-handle
                              // values, never borrows

fn audit(doc serde_json.value) ([]string, error) {
    a := auditor{trail: []string{}}
    for u in doc.array("users")? {          // u: element view (borrow handle)
        a.cur = u                           // VIOLATION site: borrow stored
        a.trail = append(a.trail, u.string("name")?)
    }
    return a.trail, nil
}

fn main() {
    doc := serde_json.parse(`{"users":[{"name":"ada","logins":5},{"name":"linus","logins":2}]}`)?
    for _, n in audit(doc)? {
        fmt.println("user: {n}")
    }
}
