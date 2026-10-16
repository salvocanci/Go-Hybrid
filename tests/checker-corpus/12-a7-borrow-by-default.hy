// ============================================================================
// 12-a7-borrow-by-default — Checker corpus #12 (pre-registered BEFORE any
// checker exists; human ruling 2026-10-12, QUESTIONS.md Q1).
//
// PURPOSE: exercise A7 on its PINNING side: a handle passed to a function
// is BORROW-BY-DEFAULT — the caller keeps it. `count_active(doc)` is
// called TWICE and `doc` is mutated afterwards: under the recommended A7
// reading all three sites are legal; under the own-transfer-alternative
// reading the second call would be use-after-transfer. This program PINS
// the recommendation (spike-6 A7: "borrow-by-default with own-transfer
// only at return/consuming APIs, because it needs no new syntax").
//
// It is ALSO a positive control for A2's non-lexical windows: the
// mutating `doc.set(...)` is legal BECAUSE both iteration loans died at
// their loops' last use. A checker with block-scoped (over-strict) loan
// windows fails here — bug in the checker, not the corpus.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): the JSON text literal, `a`/`b` (ints), `n` (int).
// Layer 2 (Rust-side owned): the serde_json graphs — behind Layer 3 only.
// Layer 3 (boundary handles): `doc` = OWN handle (parse), held by main.
//   Calls [C1]/[C2]: borrow-mode parameter loans on `doc`, live inside
//   `count_active` only (loop loan dies at the loop's last use).
//   Call [C3]: mutating-mode call on main's OWN handle — no live loans.
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   NONE — single-task program.
//
// ---- Expected verdict (PRE-REGISTERED 2026-10-12, before any checker) ----
// EXPECTED-VERDICT: ACCEPT
//   ACCEPT — A7 borrow-by-default + A2 windows respected. Distinguishing
//   power: REJECT under the own-transfer-alternative reading of A7 (the
//   recommended reading is what this program pins). Mirror programs: 13
//   (the return-transfer route, legal under both readings), 14 (the
//   consuming-call violation).
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

import "rust/serde_json"

fn count_active(doc serde_json.value) (int, error) {
    n := 0
    for u in doc.array("users")? {    // borrow-mode loan on `doc` — dies at
        if u.int("logins")? > 0 {     // the loop's last use (non-lexical)
            n++
        }
    }
    return n, nil
}

fn main() {
    doc := serde_json.parse(`{"users":[{"name":"ada","logins":5},{"name":"linus","logins":0}]}`)?

    a := count_active(doc)?           // [C1] A7 BORROW-BY-DEFAULT: main
                                      // keeps `doc` — the call does not
                                      // consume it
    b := count_active(doc)?           // [C2] second borrow call: still fine
                                      // under borrow-by-default (REJECT
                                      // under the transfer-alternative —
                                      // this is the pinning site)

    doc.set("audited", true)?         // [C3] mutating call AFTER both loans
                                      // died: no A2 conflict (non-lexical
                                      // windows — the over-strictness guard)

    fmt.println("active={a} recount={b}")
}
