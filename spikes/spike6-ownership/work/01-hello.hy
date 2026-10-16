// ============================================================================
// 01-hello — Spike 6: examples/01-hello rewritten under the Tier-0 ownership
// rules (research/ownership-models.md "Recommendation for Spike 6").
// Semantics and expected output unchanged (expected.txt):
//     hello, Hybrid!
//     count=1 ok=true
//     0: Go
//     1: Rust
//     2: Hybrid
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `g` (greeting struct), its name/count fields, `langs`
//   ([]string), every string and int. GC is the memory-safety story; reads
//   are COPIES, never loans (rule A4 in RESULTS.md). The `(g *greeting)`
//   receiver of `bump` is a unique-write loan, live for the call only;
//   nothing overlaps it — a Polonius-style non-lexical pass accepts it.
// Layer 2 (Rust-side owned): none in this program.
// Layer 3 (boundary handles): none — no Rust is called.
//
// ---- Sendability check sites (task spawn / channel send) ----
//   NONE.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0 (target met). `managed` blocks: 0 (target met).
// ============================================================================

struct greeting {
    name  string
    count int                 // zero value: Hybrid has no nil, no null
}

fn greeting.build(base string) greeting {
    g := greeting{name: base} // count starts at its zero value: 0
    g.bump()
    return g                  // GC value returned by copy
}

fn (g *greeting) bump() {     // *T receiver: unique-write loan of g, call-scoped
    g.count += 1
}

fn (g greeting) render() string { // value receiver: shallow copy, read-only
    return "hello, {g.name}!" // string interpolation
}

fn main() {
    g := greeting.build("Hybrid")
    fmt.println(g.render())              // hello, Hybrid!
    fmt.printf("count=%d ok=%v\n", g.count, g.count == 1)

    let langs = ["Go", "Rust", "Hybrid"] // GC slice; `let` = no rebinding
    for i, l in langs {                  // iteration reads are copies (A4)
        fmt.println("{i}: {l}")
    }
}
