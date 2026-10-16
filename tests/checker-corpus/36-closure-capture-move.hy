// ============================================================================
// 28-closure-capture-move.hy — Checker corpus #28 (added WITH the fix for
// soundness issue #109; the program raced on main before it landed).
//
// PURPOSE: a closure value that captures a reference-bearing outer binding
// is a LIVE ALIAS of that binding's storage. `ch <- move a` transfers the
// map (A1b: the sender must never touch the value again), but a later `f()`
// writes straight through the capture. On main the program was ACCEPT with
// 0 diagnostics while `consumer` and the closure wrote the same map —
// proven with `hyb build --emit-go` + `go run -race`:
//
//   WARNING: DATA RACE
//   Write ... by goroutine 8: main.consumer()   (runtime.mapassign_faststr)
//   Previous write ... by main goroutine: main.main.func1()  (the closure)
//
// ---- Fix shape (may-share edges, #27 machinery) ----
// At `f := fn() {...}` the closure binding is linked (may-share) to every
// captured reference-bearing outer binding, so the move of `a` freezes `f`
// and the later call is HYB-E3003 — the alias-read twin of 20's
// alias-WRITE form.
//
// ---- Expected verdict (registered with the fix, 2026-10-15) ----
// EXPECTED-VERDICT: REJECT A1b
//   REJECT — A1b (O5.2 freeze): `f` aliases `a`'s storage; using the frozen
//   alias after the move is banned under every reading of the freeze rule.
//
// ---- Annotations / managed ----
// lifetime annotations: 0. `managed` blocks: 0. No runtime output pinned
// (checker-verdict test; the race evidence lives on issue #109).
// ============================================================================

fn consumer(ch <-chan map[string]int) {
    m := <-ch
    m["y"] = 1 // the receiver owns the moved map
    fmt.println("c={len(m)}")
}

fn main() {
    a := map[string]int{}
    f := fn() {
        a["x"] = 1 // CAPTURE: a live alias of `a`'s storage
    }
    ch := make(chan map[string]int, 1)
    task consumer(ch)
    ch <- move a // move freezes `a` and its alias `f`
    f() // VIOLATION (A1b): use of the frozen alias after the move
    fmt.println("done")
}
