// EXPECTED-VERDICT: ACCEPT
// Pre-registered 2026-10-14 before running this fixture against the checker.
// Rationale: SPEC-LANGUAGE.md C4/C5 make select-send clauses boundary
// check-sites, but O4's safe-by-type classes still permit a known string
// and a channel value without a move or managed hatch. This positive
// control guards against rejecting all select-send clauses while the
// mutable-map case 25 and unproven-name case 27 pin distinct rejections.
// Both sends are type-compatible with their respective channel elements.

fn main() {
    message := "ready"
    messages := make(chan string, 1)
    results := make(chan int, 1)
    routes := make(chan chan int, 1)
    select {
        messages <- message: {}
        routes <- results: {}
    }
}
