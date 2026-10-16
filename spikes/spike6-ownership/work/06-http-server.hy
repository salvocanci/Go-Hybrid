// ============================================================================
// 06-http-server — Spike 6: examples/06-http-server under Tier-0 rules.
// Semantics and expected output unchanged (expected.txt):
//     200 hello from Hybrid
//     200 40+2=42
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `mux`, the handler closures (GC closures), `next`
//   (http.handler interface value captured by `logging`'s closure), `w`/`r`,
//   `a`/`b`, `path`. Closures capturing GC values are themselves GC values;
//   conversion to a Go interface (`http.handler(fn...)`) is Go interop.
// Layer 2 (Rust-side owned): none.
// Layer 3 (boundary handles): none — net/http, strconv, httptest are GO
//   packages; Hybrid→Go interop is call-level after Go-source emission
//   (Spike 2), NOT the checked Rust boundary.
//
// ---- Sendability check sites (task spawn / channel send) ----
//   NONE in Hybrid code (no `task`, no channel send).
//   PERIMETER NOTE (RESULTS A5): handler closures ESCAPE INTO Go code that
//   may run them on other goroutines (net/http serves one goroutine per
//   request in production). Tier-0's spawn/send checks do not see Go-API
//   escapes; the race story there is Go's (DRF-SC) with `go test -race` as
//   the backstop. This program's closures capture nothing mutable — race-
//   free under that contract (the in-process smoke client is sequential
//   anyway).
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

import "net/http"

fn logging(next http.handler) http.handler {
    return fn(w http.response_writer, r *http.request) { // closure over `next`
        fmt.eprintln("{r.method} {r.url.path}")
        next.serve_http(w, r)
    }
}

fn main() {
    mux := http.new_serve_mux()

    mux.handle("/hello", http.handler(fn(w, r) {
        fmt.fprintln(w, "hello from Hybrid")
    }))

    mux.handle("/add/", http.handler(fn(w, r) {
        a := strconv.atoi(r.url.query.get("a"))?
        b := strconv.atoi(r.url.query.get("b"))?
        fmt.fprintf(w, "{a}+{b}={a + b}\n")
    }))

    // in-process smoke client (the acceptance test drives exactly these).
    // `logging` above stays defined-but-unwired, as in the sketch: wiring it
    // would add stderr lines not present in expected.txt.
    for _, path in ["/hello", "/add/?a=40&b=2"] {
        code, body := httptest.get(mux, path)?
        fmt.println("{code} {body}")
    }
}
