//! spike6_positive.rs — the checker's positive tests (O19: spike results are
//! re-verified, not re-derived).
//!
//! The ten spike-6 ownership programs (spikes/spike6-ownership/work/*.hy)
//! hand-traced 10/10 "0 lifetime annotations, 0 `managed`, 0 outside-model"
//! under the strictest rule readings BEFORE the checker existed. The Tier-0
//! checker must ACCEPT all ten with ZERO errors (warnings would also be
//! suspicious here — none of them uses `managed`): a rejection on any of
//! these is over-strictness — a bug in the checker, not in the programs
//! (VERDICTS.md: "any checker that rejects this is over-strict").

use hy_check::{check_file, Verdict};
use hy_diag::Severity;
use hy_syntax::parse_file;

const WORK_DIR: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../../spikes/spike6-ownership/work"
);

const PROGRAMS: &[&str] = &[
    "01-hello.hy",
    "02-cli-cat.hy",
    "03-worker-pool.hy",
    "04-pipeline-backpressure.hy",
    "05-json-transform.hy",
    "06-http-server.hy",
    "07-lru-generics.hy",
    "08-graph-ownership.hy",
    "09-go-imports-hybrid.hy",
    "10-rust-crate-import.hy",
];

#[test]
fn spike6_programs_all_accept_with_zero_errors() {
    for name in PROGRAMS {
        let path = format!("{}/{}", WORK_DIR, name);
        let src =
            std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("reading {}: {}", path, e));
        let ast = parse_file(&path, &src)
            .unwrap_or_else(|diags| panic!("{} must parse (parser contract): {:?}", name, diags));
        let result = check_file(&ast);

        let errors: Vec<_> = result
            .diagnostics
            .iter()
            .filter(|d| d.severity == Severity::Error)
            .collect();
        assert!(
            errors.is_empty(),
            "{}: expected zero errors, got {:?}",
            name,
            errors.iter().map(|d| d.render_head()).collect::<Vec<_>>()
        );
        assert_eq!(
            result.verdict,
            Verdict::Accept,
            "{}: expected accept, got {:?}",
            name,
            result.diagnostics
        );
        // none of the spike-6 programs uses the managed hatch (O6): zero
        // managed lint warnings, zero managed blocks.
        assert_eq!(
            result.managed.managed_blocks, 0,
            "{}: no `managed` blocks expected",
            name
        );
        assert!(
            result.diagnostics.is_empty(),
            "{}: expected zero diagnostics of any severity, got {:?}",
            name,
            result
                .diagnostics
                .iter()
                .map(|d| d.render_head())
                .collect::<Vec<_>>()
        );
    }
}

#[test]
fn spike6_spawn_send_sites_are_counted() {
    // 03-worker-pool has exactly 3 syntactic check-sites (each counted once,
    // not per runtime iteration): the `task worker(...)` spawn, the worker's
    // `results <- result{...}` send, and main's `jobs <- job{...}` send —
    // none resolved via managed, no managed blocks.
    let path = format!("{}/03-worker-pool.hy", WORK_DIR);
    let src = std::fs::read_to_string(&path).unwrap();
    let ast = parse_file(&path, &src).unwrap();
    let result = check_file(&ast);
    assert_eq!(result.managed.total_sites, 3, "{:?}", result.managed);
    assert_eq!(result.managed.sites_via_managed, 0);
    assert_eq!(result.managed.managed_blocks, 0);
}
