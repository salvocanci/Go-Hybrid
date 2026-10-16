// ============================================================================
// 05-json-transform — Spike 6: examples/05-json-transform under Tier-0 rules.
// Semantics and expected output unchanged (expected.txt):
//     {
//       "active": [
//         "ada"
//       ]
//     }
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `names` ([]string), the 71-byte JSON text literal,
//   `min_logins` (int), every string returned by `u.string(...)` — copied at
//   the boundary into a Hybrid string (reads are copies; never loans).
// Layer 2 (Rust-side owned): none manipulated DIRECTLY — the serde_json
//   graphs live entirely behind layer-3 handles.
// Layer 3 (boundary handles, WIT own/borrow per interfaces/abi-types.md):
//   doc  = OWN handle (created by parse; destructor-on-drop via the Go
//          wrapper's cleanup when it goes out of scope);
//   u    = BORROW handle (element view into doc's array). `.int`/`.string`
//          are read (borrow-mode) calls. HANDLE-LOAN RULE (RESULTS A2): doc
//          receives NO mutating call while element views are live — this
//          program never mutates doc, so it passes the strictest reading.
//   v, arr = OWN handles created locally. `arr.push_string(n)` = mutating
//          call: call-scoped loan on arr, ends at the call. `v.set(...)`
//          lends arr (borrow-mode default, RESULTS A7; arr unused after —
//          also legal under the own-transfer reading). `return v` =
//          own-transfer OUT of the function.
//   Boundary ABI: the 71 B JSON text > 16 B copy threshold → pinned (ptr,len)
//   view for the ONE parse call, never stored; strings RETURNED from Rust
//   are copied; errors cross per Spike 5 (HyResult two-word + sentinel
//   table) and surface through `?`.
//
// ---- Sendability check sites (task spawn / channel send) ----
//   NONE.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0 (target met). `managed` blocks: 0 (target met).
// ============================================================================

import "rust/serde_json"  // pinned crate; boundary types checked (abi-types.md)

const min_logins = 3

fn active_names(doc serde_json.value) ([]string, error) {
    // doc: borrow-mode handle parameter — read-only use; caller keeps it.
    var names []string
    for u in doc.array("users")? {     // u: element view (borrow handle)
        if u.int("logins")? >= min_logins {
            names = append(names, u.string("name")?) // string copied at boundary
        }
    }
    return names, nil
}

fn users_json(names []string) serde_json.value {
    v := serde_json.new_object()       // own handle, created here
    let arr := serde_json.new_array()  // own handle, created here
    for n in names {
        arr.push_string(n)             // mutating call: call-scoped loan
    }
    v.set("active", arr)               // arr lent (or transferred) into v
    return v                           // own-transfer out of the function
}

fn main() {
    // JSON in: the 71 B text crosses as a pinned (ptr,len) view — no copy
    // of the buffer, and the view is never stored past the call.
    doc := serde_json.parse(`{"users":[{"name":"ada","logins":5},{"name":"linus","logins":2}]}`)?

    // transform in Hybrid: filter (logins >= 3) then map (name)
    names := active_names(doc)?        // borrow-mode call: main keeps doc

    // JSON out: Rust serializes; error is a Hybrid error value via `?`
    out := serde_json.to_string_pretty(users_json(names))?
    fmt.println(out)
}
