//! self_shadow_origin.rs — regression tests for the self-shadowing define
//! hole in the O5.1 non-owned-move guard (HYB-E3004, PR #61's
//! `non_owned_origin`).
//!
//! `m := m` inside an inner block (the classic Go re-declare idiom) reads
//! the OUTER `m`, but `process_local` defines the new binding first and only
//! then records alias / may-share links — which resolve `m` against the NEW
//! inner binding itself (`record_alias` sees `m -> m`, `share_edge` drops the
//! self-edge). The outer parameter / receiver / range variable's
//! `non_owned_origin` was therefore lost, and
//!
//! ```text
//! fn spawn(m map[string]int, done chan bool) {
//!     if true {
//!         m := m
//!         task worker(move m, done)
//!     }
//! }
//! ```
//!
//! was accepted with 0 diagnostics while the caller kept writing the same
//! map (`go run -race`: `WARNING: DATA RACE`; `go vet` is clean). Moving the
//! parameter directly, or a differently named copy (`m2 := m`), already
//! rejected HYB-E3004 — the spelling of the copy must not matter.

use hy_check::{check_file, Verdict};
use hy_diag::Severity;
use hy_syntax::parse_file;

fn check(src: &str) -> hy_check::CheckResult {
    let path = "inline.hy";
    let ast = parse_file(path, src)
        .unwrap_or_else(|diags| panic!("must parse (parser contract): {:?}", diags));
    check_file(&ast)
}

fn errors(r: &hy_check::CheckResult) -> Vec<(String, Option<String>)> {
    r.diagnostics
        .iter()
        .filter(|d| d.severity == Severity::Error)
        .map(|d| (d.code.clone(), d.tier0_rule.clone()))
        .collect()
}

/// `{BODY}` runs inside an inner block of `spawn`, whose parameters are all
/// non-owned (the caller, `main`, keeps writing `m` and `s` afterwards).
const PROGRAM: &str = "\
struct holder {
    m map[string]int
}

struct outer {
    h holder
}

fn worker(m map[string]int, done chan bool) {
    for i in 0..1000 {
        m[\"k\"] = i
    }
    done <- true
}

fn hworker(h holder, done chan bool) {
    h.m[\"k\"] = 1
    done <- true
}

fn sworker(s []int, done chan bool) {
    s[0] = 1
    done <- true
}

fn iworker(n int, done chan bool) {
    done <- true
}

fn same(m map[string]int) map[string]int {
    return m
}

fn spawn(m map[string]int, h holder, o outer, s []int, n int, done chan bool) {
    if true {
{BODY}
    }
}

fn main() {
    m := map[string]int{\"k\": 0}
    h := holder{m: m}
    o := outer{h: h}
    s := []int{0}
    done := make(chan bool, 1)
    spawn(m, h, o, s, 1, done)
    for i in 0..1000 {
        m[\"k\"] = i
    }
    s[0] = 2
    <-done
}
";

fn program(body: &str) -> String {
    PROGRAM.replace("{BODY}", body)
}

fn assert_rejects_e3004(label: &str, src: &str, origin: &str) {
    let r = check(src);
    assert_eq!(r.verdict, Verdict::Reject, "{}: {:?}", label, r.diagnostics);
    let first = r
        .diagnostics
        .iter()
        .find(|d| d.severity == Severity::Error)
        .unwrap_or_else(|| panic!("{}: expected an error", label));
    assert_eq!(first.code, "HYB-E3004", "{}: {:?}", label, r.diagnostics);
    assert_eq!(first.tier0_rule.as_deref(), Some("A1b"), "{}", label);
    assert!(
        first.message.contains(origin),
        "{}: the diagnostic must cite the shadowed binding ({}): {}",
        label,
        origin,
        first.message
    );
}

#[test]
fn self_shadowing_copy_of_parameter_rejects_e3004() {
    assert_rejects_e3004(
        "m := m",
        &program(
            "        m := m
        task worker(move m, done)",
        ),
        "parameter `m`",
    );
}

#[test]
fn self_shadowing_spellings_of_parameters_reject_e3004() {
    let cases: &[(&str, &str, &str)] = &[
        (
            "parenthesized",
            "        m := (m)
        task worker(move m, done)",
            "parameter `m`",
        ),
        (
            "ascribed",
            "        var m map[string]int = m
        task worker(move m, done)",
            "parameter `m`",
        ),
        (
            "re-slice",
            "        s := s[:]
        task sworker(move s, done)",
            "parameter `s`",
        ),
        (
            "call returning its argument (#38 shape)",
            "        m := same(m)
        task worker(move m, done)",
            "parameter `m`",
        ),
        (
            "shallow struct copy (#27 may-share)",
            "        h := h
        task hworker(move h, done)",
            "parameter `h`",
        ),
        (
            "struct projection (#27 may-share)",
            "        o := o.h
        task hworker(move o, done)",
            "parameter `o`",
        ),
        (
            "composite literal embedding a projection",
            "        h := holder{m: h.m}
        task hworker(move h, done)",
            "parameter `h`",
        ),
        (
            "move-send",
            "        m := m
        ch := make(chan map[string]int, 1)
        ch <- move m
        fmt.println(len(ch))",
            "parameter `m`",
        ),
    ];
    for (label, body, origin) in cases {
        assert_rejects_e3004(label, &program(body), origin);
    }
}

#[test]
fn self_shadowing_copy_of_receiver_rejects_e3004() {
    let src = "\
struct state {
    m map[string]int
}

fn worker(s state, done chan bool) {
    s.m[\"k\"] = 1
    done <- true
}

fn (s state) spawn(done chan bool) {
    if true {
        s := s
        task worker(move s, done)
    }
}

fn main() {
    s := state{m: map[string]int{\"k\": 0}}
    done := make(chan bool, 1)
    s.spawn(done)
    s.m[\"k\"] = 2
    <-done
}
";
    assert_rejects_e3004("receiver s := s", src, "method receiver `s`");
}

/// Negative controls: scalar shadows, copy-outs into fresh literals, fresh
/// values under the same name, non-moving shadows, and a shadow of an OWNED
/// local all stay accepted.
#[test]
fn self_shadowing_without_shared_storage_still_accepts() {
    let cases: &[(&str, &str)] = &[
        (
            "scalar shadow",
            "        n := n
        task iworker(move n, done)",
        ),
        (
            "scalar copy-out into a fresh map",
            "        m := map[string]int{\"k\": m[\"k\"]}
        task worker(move m, done)",
        ),
        (
            "fresh value under the same name",
            "        m := map[string]int{\"k\": 0}
        task worker(move m, done)",
        ),
        (
            "shadow without a boundary move",
            "        m := m
        fmt.println(m[\"k\"])",
        ),
    ];
    for (label, body) in cases {
        let r = check(&program(body));
        assert_eq!(r.verdict, Verdict::Accept, "{}: {:?}", label, r.diagnostics);
        assert!(errors(&r).is_empty(), "{}: {:?}", label, r.diagnostics);
    }

    let owned = "\
fn worker(m map[string]int, done chan bool) {
    m[\"k\"] = 1
    done <- true
}

fn main() {
    m := map[string]int{\"k\": 0}
    done := make(chan bool, 1)
    if true {
        m := m
        task worker(move m, done)
    }
    <-done
}
";
    let r = check(owned);
    assert_eq!(
        r.verdict,
        Verdict::Accept,
        "owned shadow: {:?}",
        r.diagnostics
    );
}
