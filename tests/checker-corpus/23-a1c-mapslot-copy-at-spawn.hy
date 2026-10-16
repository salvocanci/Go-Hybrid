// ============================================================================
// 23-a1c-mapslot-copy-at-spawn — Checker corpus #23 (bounty track, issue #6).
// The legal twin of 21: same program, ONE change — read the map-slot loan's
// field into a local BEFORE the spawn, so a copy (A4) crosses the spawn
// site instead of the live loan itself.
//
// PURPOSE: without this twin, 21 could be misread as "map-slot loans can
// never reach a task" — too strong a lesson. The actual rule is narrower:
// the LOAN (the pointer) cannot cross a spawn/send site unsendable; the
// VALUE it points at, read out before the loan's last use, is an ordinary
// Go-heap read and therefore a copy (O9/A4) — sendable like any other
// plain int. This is also the fix-it this corpus's own diagnostic sketches
// recommend first ("snapshot what you need before the send" — VERDICTS.md,
// the 19 sketch) — pinned here for the map-slot-loan shape specifically.
//
// RULE CITATION: A4, "Go-heap reads are copies, not loans" (SPEC-LANGUAGE.md
// O9) — reading a map-slot through its loan yields a copy, and that read is
// also the loan's last use, so L1 is dead before the spawn site is reached;
// A1c (O4) then sees only plain `int`/channel values at the check-site, all
// safe-by-type.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `e`, `e.services`, `svc` (map-slot loan — dies at
//   the read below), `current` (int — a COPY), `n` (int), `done` (channel).
// Layer 2 (Rust-side owned): none.
// Layer 3 (boundary handles): none.
//
// ---- Loans traced (non-lexical windows) ----
//   L1 = `svc := &e.services["frontend"]` — unique map-slot loan (O8).
//   L1's LAST USE is `current := svc.replicas` — a Go-heap read, hence a
//   COPY (A4/O9), not a further loan. The window closes there, strictly
//   BEFORE the spawn site below: no live loan reaches [S1].
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   [S1] `task bump_report("frontend", 3, current, done)`:
//        "frontend" — string literal: sendable. 3 / current — int copies:
//        sendable (A1c safe-by-type; `current` is a COPY per A4, not the
//        loan). done — channel: sendable.
//   No live loan, no mutable GC pointer, nothing `move`d or `managed` —
//   every argument is already in a sendable class.
//
// ---- Expected verdict (derived from VERDICTS.md rule key + SPEC O3/O4/O9
// BEFORE running the checker) ----
// EXPECTED-VERDICT: ACCEPT
//   ACCEPT — 0 annotations, 0 managed. Reading-distinguishing power: pins
//   that A1c's rejection in 21 tracks the LOAN crossing the spawn, not the
//   map-slot's mere existence upstream — the narrower, correct lesson.
//
// ---- Checker reproduction (per BOUNTY.md: pay only after reproduction) ----
//   `hyb check 23-a1c-mapslot-copy-at-spawn.hy --json` on the pinned
//   toolchain: verdict=accept, 0 errors — agrees with the hand-derived
//   verdict above.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

struct service {
    replicas int
    tag      string
}

struct env {
    services map[string]service
}

fn bump_report(id string, n int, replicas int, done chan<- bool) {
    fmt.println("{id}: {replicas + n}")
    done <- true
}

fn main() {
    e := env{services: map[string]service{
        "frontend": {replicas: 2, tag: "prod"},
    }}

    done := make(chan bool, 1)
    svc := &e.services["frontend"]   // LOAN L1: map-slot borrow (creation)
    current := svc.replicas          // L1 LAST USE — a COPY (A4); window
                                      // closes here, before the spawn below
    task bump_report("frontend", 3, current, done)  // [S1]: copies + a
                                      // channel only — every value sendable
    <-done
}
