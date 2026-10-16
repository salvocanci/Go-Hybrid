// ============================================================================
// 27-const-write-reject — Checker corpus #26 (soundness issue #37, reported
// against main e60ac97; the write rejection lands with this fix batch).
//
// PURPOSE: pin T22 deep immutability on `const`. A file-level `const` lowers
// to package-level state that every task body reaches ambiently: nothing
// crosses the spawn site (`bump` receives only a channel), so the O4 spawn
// check never sees `cells`, and before this fix the index write and the
// rebind were both accepted — the emitter produced `var cells = []int{0}`,
// the two tasks raced, and `hyb check` said `OK (0 diagnostics)` while
// `go run -race` reported write/write data races (issue #37). Distinct from
// #25/#12: those carry const/let values ACROSS a spawn site; here no
// argument carries the state — the gap is the missing write rejection.
//
// ---- Tier-0 rule set applied ----
// T22 (SPEC-LANGUAGE): `const` is the only DEEP immutability in MVP — the
// binding, its elements, and every field under it are frozen; reads stay
// legal (deep immutability bans the write, not the value).
//   [W1] `cells[0] = cells[0] + 1` — element/index write whose root is a
//        `const` binding: REJECT (HYB-E3006, tier0 rule IMMUT).
//   [W2] `cells = [5]` — whole-binding rebind of a `const`: REJECT
//        (HYB-E3006, tier0 rule IMMUT).
//   The accept side (shadowing `let` copy of a const-named value, plain
//   `var`/`let` writes) is pinned in hy-check/tests/const_write.rs.
//
// ---- Expected verdict (registered 2026-10-14 with the fix batch) ----
// EXPECTED-VERDICT: REJECT IMMUT
//   REJECT — T22 deep immutability: the FIRST error carries tier0_rule
//   IMMUT (HYB-E3006). Legal routes: `let`/`var` local state with a proof
//   at the boundary (`move`/send/channel), a per-task copy merged over a
//   channel, or the explicit auditable hatch `managed("why", "mutex")`.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0 — as written the program
//   NEEDS one of the legal routes (or a per-task redesign). No expected
//   runtime output is pinned: this is a checker-verdict test, not an
//   execution test.
// ============================================================================

const cells = [0]

fn bump(done chan<- bool) {
    for _ in 0..100000 {
        cells[0] = cells[0] + 1   // WRITE SITE [W1] — VIOLATION: element write through const
    }
    done <- true
}

fn main() {
    done := make(chan bool, 2)
    task bump(done)
    task bump(done)
    for _ in 0..2 { <-done }
    cells = [5]                   // WRITE SITE [W2] — VIOLATION: whole-binding rebind of const
}
