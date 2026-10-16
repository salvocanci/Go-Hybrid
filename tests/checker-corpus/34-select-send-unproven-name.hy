// EXPECTED-VERDICT: REJECT FC
// EXPECTED-DIAGNOSTIC: HYB-E3005
// Pre-registered 2026-10-14 before running this fixture against the checker.
// Rationale: SPEC-LANGUAGE.md C4/C5 and O4.9 (FC) require proof for the
// value crossing a select-send boundary. `unresolved` has no binding,
// so its shape cannot be proved; the known `chan int` destination does
// not supply that proof. Reject with FC/HYB-E3005, rather than A1c or a
// grammar error. This is a checker-only negative fixture, not runnable Go.
// No ownership moves, closures, or managed suppression obscure the site.

fn main() {
    out := make(chan int, 1)
    select {
        out <- unresolved: {}
    }
}
