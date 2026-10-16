// ============================================================================
// 30-const-closure-alias-write-reject — Checker corpus #30 (soundness issue
// #123, the follow-up gap in #37's E3006 fix, reported against main).
//
// PURPOSE: T22 deep immutability must hold on the paths the first E3006
// fix never walked. Closure bodies sit outside Pass B (the A5 perimeter —
// flatten, uses, and calls never descend into an `FnLit`), so
// `process_assign` never saw a write inside a closure, and
// `const_write_root` only tested the place's own root binding, never the
// alias/copy behind it. `delete()` never routed through E3006 at all. On
// main every form below was ACCEPT with 0 diagnostics — including the race
// shape: BOTH writers live in closure bodies, nothing crosses the spawn
// site, the emitter lowers `const cells` to `var cells = []int{0}`, and
// `hyb check` said `OK (0 diagnostics)` while `go run -race` reported
// `WARNING: DATA RACE` / `Found 1 data race(s)` (issue #123; the same
// shape as #37's evidence reached through the remaining blind spot).
//
// ---- Tier-0 rule set applied ----
// T22 (SPEC-LANGUAGE): `const` is the only DEEP immutability in MVP — the
// binding, its elements, and every field under it are frozen; reads stay
// legal (deep immutability bans the write, not the value).
//   [W1] `cells[0] = 2` inside a closure body — REJECT (HYB-E3006, IMMUT):
//        the fn-end scan walks every FnLit reachable from the body.
//   [W2] `cells = [5]` rebind inside a closure body — REJECT (same scan).
//   [W3] `alias := cells; alias[0] = 1` — REJECT: `const_write_root` now
//        follows alias parents / may-share peers to the immutable root.
//   [W4] `delete(tags, ...)` on a `const` map, direct and in-closure —
//        REJECT: a delete mutates the collection exactly like an index
//        write.
//   The accept side (shadowing copies, plain `let`/`var` writes, reads)
//   stays pinned in hy-check/tests/const_write.rs.
//
// ---- Expected verdict (registered with the fix batch) ----
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
const tags = map[string]int{"a": 1}

fn worker() {
    f := fn() {
        cells[0] = 2          // WRITE SITE [W1] — element write inside a closure
    }
    f()
}

fn main() {
    task worker()             // runtime shape: both writers are closure-bodied
    g := fn() {
        cells = [5]           // WRITE SITE [W2] — rebind inside a closure
    }
    g()
    alias := cells
    alias[0] = 1              // WRITE SITE [W3] — element write through a copy
    delete(tags, "a")         // WRITE SITE [W4] — delete on a const map
    h := fn() {
        delete(tags, "b")     // WRITE SITE [W4] — delete inside a closure
    }
    h()
}
