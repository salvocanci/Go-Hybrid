// 32-closure-local-alias-move-reject.hy — issue #137:
// local rebind inside closure must not bypass non_owned_origin and alias tracking.
//
// EXPECTED-VERDICT: REJECT A1b
//
// Background
// ----------
// In check_closure_boundaries, Stmt::Local handling called define_binding
// directly without record_alias, record_may_share, or record_local_borrow_aliases.
// As a result, local aliases created inside closures (`alias := m`) lost their
// inherited non_owned_origin and may-share edges from the captured outer binding,
// allowing `move alias` at a task spawn to bypass HYB-E3004.
//
// Rationale
// ---------
// `alias := m` inside a closure references the captured outer map `m`.
// The closure capture itself is non-owned (the outer scope retains `m`, and the
// closure may run multiple times). Moving `alias` violates O5.1 / O5.4 because
// the sending closure frame does not exclusively own the underlying storage.

fn worker(m map[string]int, done chan<- bool) {
    for i in 0..1000 {
        m["k"] = i
    }
    done <- true
}

fn main() {
    m := map[string]int{"k": 0}
    done := make(chan bool, 2)

    spawn_it := fn() {
        alias := m
        task worker(move alias, done) // REJECTION SITE: move captured alias
    }

    spawn_it()
    spawn_it()
    <-done
    <-done
}
