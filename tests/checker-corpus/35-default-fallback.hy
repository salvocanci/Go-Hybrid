// EXPECTED-VERDICT: ACCEPT
// EXPECTED-OUTPUT: idle
// Pre-registered 2026-10-14 before running this fixture against the checker.
// Rationale: SPEC-LANGUAGE.md C4 permits an optional default arm and uses
// it when no communication is ready. The string send is safe-by-type (O4)
// and its unbuffered channel has no receiver, so the default arm must run
// without blocking and print exactly "idle". This pins ordinary parser
// correctness and default-arm emission as well as the checker verdict.
// No task spawning, managed hatch, mutable sharing, or runtime race case.

fn main() {
    ch := make(chan string)
    select {
        ch <- "ready": fmt.println("sent")
        default: fmt.println("idle")
    }
}
