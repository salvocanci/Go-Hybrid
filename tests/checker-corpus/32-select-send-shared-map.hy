// EXPECTED-VERDICT: REJECT A1c
// EXPECTED-DIAGNOSTIC: HYB-E3002
// Pre-registered 2026-10-14 before running this fixture against the checker.
// Rationale: SPEC-LANGUAGE.md C4/C5 and O4 apply the same sendability
// classification to a select-send clause as to a statement send. `counts`
// is a named mutable GC map, not a safe-by-type value or ownership move.
// Sending it in this clause must therefore reject with A1c/HYB-E3002.
// The empty arm keeps this about the send-site classification only:
// no spawned workers, runtime race demonstration, loans, or managed hatch.

fn main() {
    counts := map[string]int{}
    out := make(chan map[string]int, 1)
    select {
        out <- counts: {}
    }
}
