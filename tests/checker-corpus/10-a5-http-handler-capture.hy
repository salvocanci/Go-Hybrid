// ============================================================================
// 10-a5-http-handler-capture — Checker corpus #10 (pre-registered BEFORE
// any checker exists; human ruling 2026-10-12, QUESTIONS.md Q1).
//
// PURPOSE: exercise A5 (the Go-API escape perimeter) on the shape that
// forces the decision: a MUTABLE GC value CAPTURED by a handler closure
// handed to foreign Go code (net/http), which may run it on other
// goroutines (one per request in production). There is NO Hybrid
// spawn/send site anywhere — the value escapes through the Go API instead.
//
// DECIDED under the scoped-claim ruling (spike-6 RESULTS A5 + Q1 item 6
// "no overclaiming"): ACCEPT — Tier 0's checked subset is spawn/send
// sites; Go-API escapes follow Go's DRF-SC story with `go test -race` as
// the backstop. SPEC-LANGUAGE.md must state the race-freedom claim exactly
// that narrowly, with the `managed` boundary in the same paragraph.
//
// CONTESTED (the corpus's second contested program): if SPEC-LANGUAGE
// adopts the FOURTH CHECK-SITE class ("APIs flagged concurrent"), this
// program FLIPS to REJECT (or requires atomic-mediated `hits`). That
// decision is explicitly open — flagged for SPEC-LANGUAGE.md (OQ1), NOT
// silently decided here. This is request-counter middleware; every Go
// service has one. Whichever way SPEC-LANGUAGE rules, it rules on code
// written daily.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `hits` (int — MUTABLE GC value captured by the
//   closure), `mux`, the handler closures themselves (GC closures;
//   conversion to http.handler is Go interop — spike-6 06), `w`/`r`,
//   `code`/`body` (value copies).
// Layer 2 (Rust-side owned): none.
// Layer 3 (boundary handles): none — net/http + httptest are GO packages;
//   Hybrid→Go interop is call-level after Go-source emission (Spike 2),
//   NOT the checked Rust boundary.
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   NONE in Hybrid code (no `task`, no channel send). PERIMETER: the
//   `hits` capture in the closure passed to `mux.handle(...)` escapes
//   into Go code — unchecked under the scoped claim (A5).
//
// ---- Expected verdict (PRE-REGISTERED 2026-10-12, before any checker) ----
// EXPECTED-VERDICT: ACCEPT (CONTESTED)
//   ACCEPT under the A5 scoped-claim ruling (no check site exists for the
//   checker to own). Flips to REJECT if the fourth check-site class lands
//   (OQ1). HONESTY NOTE: production net/http serves handlers concurrently
//   — `hits++` from two overlapping requests is a REAL Go data race; the
//   in-process smoke client below is sequential, so this acceptance run
//   is race-free. The verdict is about which SITES the checker owns, not
//   about the runtime behavior of foreign code.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

import "net/http"

fn main() {
    hits := 0                    // mutable GC value, captured below

    mux := http.new_serve_mux()
    mux.handle("/ping", http.handler(fn(w http.response_writer, r *http.request) {
        hits++                   // runs on Go's request goroutines — the A5
        fmt.fprintln(w, "pong {hits}")  // escape perimeter, not a check site
    }))

    // in-process smoke client (sequential, as in spike-6 06)
    for _ in 0..3 {
        code, body := httptest.get(mux, "/ping")?
        fmt.println("{code} {body}")
    }
}
