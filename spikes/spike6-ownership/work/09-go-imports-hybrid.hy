// ============================================================================
// 09-go-imports-hybrid — THE ADOPTION STORY (Spike 6 rewrite). This file is
// the HYBRID SIDE: the package that examples/09-go-imports-hybrid/main.go.txt
// imports as "example.com/app/hybrid". The Go consumer needs NO Hybrid
// toolchain — committed generated Go source + prebuilt Rust artifact (Spike 2).
// Semantics and expected output unchanged (expected.txt):
//     ada@lovelace.dev <nil>
//     match: true
//
// ---- the Go consumer (examples/09-go-imports-hybrid/main.go.txt) ----
//   package main
//
//   import (
//       "fmt"
//       "example.com/app/hybrid" // the Hybrid-compiled package
//   )
//
//   func main() {
//       email, err := hybrid.ValidateEmail("ada@lovelace.dev")
//       fmt.Println(email, err)        // ada@lovelace.dev <nil>
//       ok := hybrid.SimplePattern("ab*c")
//       fmt.Println("match:", ok)      // match: true
//   }
// ------------------------------------------------------------------------
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): the input/output strings, the fixed subject string.
//   Reads are copies; nothing is shared across tasks.
// Layer 2 (Rust-side owned): none manipulated directly — the pinned `regex`
//   crate's compiled Regex lives entirely behind a handle.
// Layer 3 (boundary handles, abi-types.md):
//   re = OWN handle to a Rust-side regex::Regex (generation-tagged id;
//        released by the Go wrapper's cleanup when it goes out of scope);
//   re.is_match(...) = BORROW-mode call (call-scoped loan on the handle).
//   Boundary ABI: the email (18 B) and the pattern (26 B) exceed the 16 B
//   copy threshold → pinned (ptr,len) views for ONE call each, never
//   stored; bool returns by value; compile errors cross per Spike 5
//   (HyResult two-word + sentinel table) and surface through `?`.
//   Hybrid→Go EXPORT surface: `pub fn` with (string, error) maps directly to
//   a Go func signature after Go-source emission (emission-level, not a
//   checked boundary).
//
// ---- Sendability check sites (task spawn / channel send) ----
//   NONE.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

import "rust/regex"          // pinned crate; API extracted via rustdoc JSON

const email_pattern = `^[^@\s]+@[^@\s]+\.[^@\s]+$`

// exported to Go as: func ValidateEmail(email string) (string, error)
pub fn validate_email(email string) (string, error) {
    re := regex.compile(email_pattern)?  // own handle; compile error via `?`
    if !re.is_match(email) {             // borrow-mode call on the handle
        return "", errors.new("invalid email address")
    }
    return email, nil
}

// exported to Go as: func SimplePattern(pattern string) bool
pub fn simple_pattern(pattern string) bool {
    re, err := regex.compile(pattern)
    if err != nil {
        return false                     // uncompilable pattern: no match
    }
    return re.is_match("abbbc")          // fixed subject (RESULTS note R9)
}
