// ============================================================================
// 06-borrow-returned-from-fn — Checker corpus #6 (pre-registered BEFORE any
// checker exists; human ruling 2026-10-12, QUESTIONS.md Q1).
//
// PURPOSE: the G0-named adversarial #3: "borrow-returned-from-function"
// (loan escape). `counter_for` returns `&reg.counters[i]` — idiomatic,
// LEGAL Go (pointers into slices outlive their frames all day), and
// exactly the shape Tier 0's "loans never escape functions" rule exists to
// reject: the slot loan's window would have to outlive the callee's frame,
// which is where lifetime parameters would enter if they existed.
//
// RULE CITATION: Tier-0 Layer-2 rule "loans never escape functions, so
// there are no lifetime parameters to write" (spike-6 RESULTS.md, design
// item 2). This is NOT one of A1–A8 — it is unambiguous Tier-0 text; it
// lacks only a rule NUMBER (it is A6's sibling: A6 = loan escaping into a
// struct field, this = loan escaping out of a return; same principle,
// different site). Numbering flagged for SPEC-LANGUAGE.md (OQ4).
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `reg` (registry — GC), `reg.counters` ([]counter —
//   the arena that owns every counter), `c` (the escaped *counter loan),
//   `i` (int).
// Layer 2 (Rust-side owned): none.
// Layer 3 (boundary handles): none.
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   NONE — single-task program; the violation is loan escape, not sharing.
//
// ---- Expected verdict (PRE-REGISTERED 2026-10-12, before any checker) ----
// EXPECTED-VERDICT: REJECT LOAN-ESCAPE
//   REJECT — "loans never escape functions" (Tier-0 L2 text; A6's sibling,
//   numbering flagged as OQ4). Memory-safety honesty: GC keeps the pointee
//   alive — nothing dangles; the rejection preserves the discipline
//   guarantee that every loan window stays function-local and checkable.
//   Tier-0-legal rewrites (for the fix-it): keep the loan in one frame —
//     fn (r *registry) bump(i int) { c := &r.counters[i]; c.hits++ }
//   or return the INDEX (id discipline, spike-6 08), or return a COPY
//   (reads are copies, A4). A lifetime parameter is NOT a fix — that is
//   the whole point of the rule.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

struct counter {
    name string
    hits int
}

struct registry {
    counters []counter        // the arena that owns every counter
}

fn counter_for(reg *registry, i int) *counter {
    return &reg.counters[i]   // VIOLATION (loan escape): the slot borrow
}                             // dies at function exit under Tier 0; returning
                              // it is the shape that would demand lifetime
                              // parameters — forbidden by design

fn main() {
    reg := registry{counters: [
        counter{name: "requests", hits: 0},
        counter{name: "errors",   hits: 0},
    ]}

    c := counter_for(reg, 0)  // the escaped loan lands in `c`
    c.hits++                  // mutation through it — fine in Go (the slice
                              // outlives the call); rejected at the return

    fmt.println("{c.name}={c.hits}")
}
