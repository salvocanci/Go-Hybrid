//! capture_freeze.rs — regression tests for the issue #109 fix: a closure
//! value that captures a reference-bearing outer binding is a live ALIAS of
//! that binding's storage. Before the fix, `ch <- move a` / `task t(move m)`
//! froze only the plain-alias chain — the closure kept writing through the
//! capture and the program was ACCEPT while `go run -race` reported a
//! write/write DATA RACE (receiver vs closure, issue #109). The fix links
//! the closure binding to its captures with may-share edges at definition,
//! so a later move of either freezes the other (O5.2) and the post-move
//! call is HYB-E3003 (A1b).

use hy_check::{check_file, Verdict};
use hy_diag::Severity;
use hy_syntax::parse_file;

fn check(src: &str) -> hy_check::CheckResult {
    let path = "inline.hy";
    let ast = parse_file(path, src)
        .unwrap_or_else(|diags| panic!("must parse (parser contract): {:?}", diags));
    check_file(&ast)
}

fn codes(r: &hy_check::CheckResult) -> Vec<String> {
    r.diagnostics
        .iter()
        .filter(|d| d.severity == Severity::Error)
        .map(|d| d.code.clone())
        .collect()
}

// ---------------------------------------------------------------------------
// Rejects — the capture is a frozen alias after the move (A1b)
// ---------------------------------------------------------------------------

#[test]
fn capture_used_after_move_send_is_e3003() {
    // Issue #109's channel shape: consumer owns the map, `f()` still writes.
    let r = check(
        "fn consumer(ch <-chan map[string]int) {\n\
         \x20   m := <-ch\n\
         \x20   m[\"y\"] = 1\n\
         }\n\n\
         fn main() {\n\
         \x20   a := map[string]int{}\n\
         \x20   f := fn() {\n\
         \x20       a[\"x\"] = 1\n\
         \x20   }\n\
         \x20   ch := make(chan map[string]int, 1)\n\
         \x20   task consumer(ch)\n\
         \x20   ch <- move a\n\
         \x20   f()\n\
         }\n",
    );
    let cs = codes(&r);
    assert!(
        cs.iter().any(|c| c == "HYB-E3003"),
        "expected HYB-E3003 for the post-move closure call (alias read), got {:?}",
        cs
    );
    assert_eq!(r.verdict, Verdict::Reject);
}

#[test]
fn capture_used_after_move_spawn_is_e3003() {
    // The task-spawn form: `task touch(move m)` then `f()`.
    let r = check(
        "fn touch(m map[string]int) {\n\
         \x20   m[\"x\"] = 1\n\
         }\n\n\
         fn main() {\n\
         \x20   m := map[string]int{}\n\
         \x20   f := fn() {\n\
         \x20       m[\"y\"] = 1\n\
         \x20   }\n\
         \x20   task touch(move m)\n\
         \x20   f()\n\
         }\n",
    );
    let cs = codes(&r);
    assert!(
        cs.iter().any(|c| c == "HYB-E3003"),
        "expected HYB-E3003 for the spawn-move + capture form, got {:?}",
        cs
    );
    assert_eq!(r.verdict, Verdict::Reject);
}

#[test]
fn nested_closure_capture_used_after_move_is_e3003() {
    // The capture sits one closure deeper — the outer binding is still
    // captured transitively and must freeze with it.
    let r = check(
        "fn main() {\n\
         \x20   a := map[string]int{}\n\
         \x20   f := fn() {\n\
         \x20       g := fn() {\n\
         \x20           a[\"x\"] = 1\n\
         \x20       }\n\
         \x20       g()\n\
         \x20   }\n\
         \x20   ch := make(chan map[string]int, 1)\n\
         \x20   ch <- move a\n\
         \x20   f()\n\
         }\n",
    );
    let cs = codes(&r);
    assert!(
        cs.iter().any(|c| c == "HYB-E3003"),
        "expected HYB-E3003 through the nested capture, got {:?}",
        cs
    );
    assert_eq!(r.verdict, Verdict::Reject);
}

#[test]
fn rebound_closure_capture_used_after_move_is_e3003() {
    // `f = fn(){...}` rebinds: the fresh closure re-records its capture
    // edges (rebind clears and re-records, #27), so the freeze still holds.
    let r = check(
        "fn main() {\n\
         \x20   a := map[string]int{}\n\
         \x20   f := fn() {\n\
         \x20       a[\"x\"] = 1\n\
         \x20   }\n\
         \x20   f = fn() {\n\
         \x20       a[\"y\"] = 2\n\
         \x20   }\n\
         \x20   ch := make(chan map[string]int, 1)\n\
         \x20   ch <- move a\n\
         \x20   f()\n\
         }\n",
    );
    let cs = codes(&r);
    assert!(
        cs.iter().any(|c| c == "HYB-E3003"),
        "expected HYB-E3003 after the closure rebind, got {:?}",
        cs
    );
    assert_eq!(r.verdict, Verdict::Reject);
}

// ---------------------------------------------------------------------------
// Accepts — precision: no post-move use, no shared storage, no capture
// ---------------------------------------------------------------------------

#[test]
fn capture_called_only_before_move_accepts() {
    // NLL-style precision: the closure never runs after the move, so the
    // sender never touches the value again — nothing concurrent exists.
    let r = check(
        "fn main() {\n\
         \x20   a := map[string]int{}\n\
         \x20   f := fn() {\n\
         \x20       a[\"x\"] = 1\n\
         \x20   }\n\
         \x20   f()\n\
         \x20   ch := make(chan map[string]int, 1)\n\
         \x20   ch <- move a\n\
         \x20   fmt.println(\"ok\")\n\
         }\n",
    );
    // AMENDMENT (pr-110 integration, logged): the contributor's base predates
    // fef40da's closure-boundary use checking, where this shape accepted.
    // fef40da's rule is the one main ships: a closure may run at ANY time
    // after its definition, so a use of a moved binding inside a closure
    // body is checked against the COMPLETED environment — fail-closed
    // (O4.9/A5), same as every unresolvable capture. NLL precision ("the
    // closure provably cannot be called after the move") needs
    // flow-sensitive closure-call analysis and is tracked as a PLAN
    // follow-up; until then the conservative reject stands.
    assert!(
        codes(&r).iter().any(|c| c == "HYB-E3003"),
        "closure use of a moved binding rejects (fef40da, conservative): {:?}",
        r.diagnostics
    );
    assert_eq!(r.verdict, Verdict::Reject);
}

#[test]
fn primitive_capture_after_move_accepts() {
    // Moving an int copies the value: the receiver owns its copy, the
    // closure writes main's original — separate storage, no race, and a
    // primitive capture creates no may-share edge.
    let r = check(
        "fn main() {\n\
         \x20   hits := 0\n\
         \x20   f := fn() {\n\
         \x20       hits = hits + 1\n\
         \x20   }\n\
         \x20   ch := make(chan int, 1)\n\
         \x20   ch <- move hits\n\
         \x20   f()\n\
         }\n",
    );
    // AMENDMENT (pr-110 integration, logged): same fef40da rule as above —
    // the closure-boundary pass cannot yet prove an int capture safe after
    // the move (the write may race with nothing today, but proving THAT is
    // the NLL follow-up). Conservative reject until the precision lands.
    assert!(
        codes(&r).iter().any(|c| c == "HYB-E3003"),
        "closure use of a moved (primitive) binding rejects (fef40da, conservative): {:?}",
        r.diagnostics
    );
    assert_eq!(r.verdict, Verdict::Reject);
}

#[test]
fn shadowing_closure_param_creates_no_false_edge() {
    // The body's `a` is the closure's OWN parameter — it never touches the
    // outer map, so moving the outer binding must not freeze `f`.
    let r = check(
        "fn main() {\n\
         \x20   a := map[string]int{}\n\
         \x20   f := fn(a map[string]int) {\n\
         \x20       a[\"x\"] = 1\n\
         \x20   }\n\
         \x20   ch := make(chan map[string]int, 1)\n\
         \x20   ch <- move a\n\
         \x20   f(map[string]int{})\n\
         }\n",
    );
    assert!(
        codes(&r).is_empty(),
        "a shadowing closure param is not a capture of the outer binding: {:?}",
        r.diagnostics
    );
    assert_eq!(r.verdict, Verdict::Accept);
}

#[test]
fn capture_without_move_accepts() {
    // corpus 10's standing shape (A5): a closure capturing mutable state
    // with NO boundary crossing is outside the checked subset — accepted.
    let r = check(
        "fn main() {\n\
         \x20   hits := 0\n\
         \x20   f := fn() {\n\
         \x20       hits = hits + 1\n\
         \x20   }\n\
         \x20   f()\n\
         \x20   fmt.println(\"{hits}\")\n\
         }\n",
    );
    assert!(
        codes(&r).is_empty(),
        "capture with no move must stay accepted (A5): {:?}",
        r.diagnostics
    );
    assert_eq!(r.verdict, Verdict::Accept);
}
