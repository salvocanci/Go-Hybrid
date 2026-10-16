// ============================================================================
// 13-a7-own-transfer-at-return — Checker corpus #13 (pre-registered BEFORE
// any checker exists; human ruling 2026-10-12, QUESTIONS.md Q1).
//
// PURPOSE: exercise A7's own-transfer-at-RETURN route (positive). `summary`
// creates an own handle, populates it, and RETURNS it — the transfer-out
// site; the caller then MUTATES the returned handle, proving the transfer
// conferred ownership. Legal under the recommended A7 (borrow-by-default +
// transfer at return/consuming APIs) AND under the own-transfer-alternative
// reading (nothing is used after a transfer except the returned value): a
// deliberate both-readings positive — the two readings disagree on 12 and
// 14, not here.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): the JSON text literal, `n` (int), `s` (string).
// Layer 2 (Rust-side owned): the serde_json graphs — behind Layer 3 only.
// Layer 3 (boundary handles): `doc` = OWN handle (parse; passed to
//   `summary` borrow-by-default — its iteration loan dies at the loop's
//   last use). `v` = OWN handle created INSIDE `summary`; `return v` is
//   the own-transfer-OUT site. `s` in main = the transferred-in handle —
//   main owns it and may mutate it.
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   NONE — single-task program.
//
// ---- Expected verdict (PRE-REGISTERED 2026-10-12, before any checker) ----
// EXPECTED-VERDICT: ACCEPT
//   ACCEPT — A7 own-transfer at `return v` ([T1]); caller mutates the
//   returned handle ([T2]) — the transfer made it the caller's. [T3] is
//   marked NON-DISTINGUISHING on purpose (noted in-line) so the future
//   checker test does not over-pin A7 at a site both readings accept.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

import "rust/serde_json"

fn summary(doc serde_json.value) (serde_json.value, error) {
    v := serde_json.new_object()      // OWN handle, created here
    n := 0
    for u in doc.array("users")? {    // borrow-mode loan on `doc` (A7
        if u.int("logins")? > 0 {     // borrow-by-default): dies at the
            n++                       // loop's last use (non-lexical)
        }
    }
    v.set("active", n)                // mutating call on the OWN handle:
    return v                          // call-scoped loan only
                                      // [T1] OWN-TRANSFER OUT (A7 route:
                                      // transfer happens at `return`)
}

fn main() {
    doc := serde_json.parse(`{"users":[{"name":"ada","logins":5},{"name":"linus","logins":0}]}`)?

    s := summary(doc)?                // `doc` borrowed in (A7 default);
                                      // non-distinguishing: main never uses
                                      // `doc` again either way

    s.set("cached_at", "2026-10-12")? // [T2] caller MUTATES the returned
                                      // handle: the transfer made it ours

    fmt.println(serde_json.to_string_pretty(s)?)
    // [T3] to_string_pretty(s): if declared consuming, this is `s`'s last
    // use (legal); if borrowing, also legal. NON-DISTINGUISHING site —
    // do not over-pin A7 here.
}
