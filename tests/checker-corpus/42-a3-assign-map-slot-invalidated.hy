// ============================================================================
// 32-a3-assign-map-slot-invalidated — Checker corpus #32 (soundness issue #138,
// reported against main e60ac97; re-assignment loan window tracking).
//
// PURPOSE: pin A3 / O8 on map slot re-assignment `x = &m[k]`. Tier-0 loan
// creation opened a non-lexical loan window on `x := &m[k]`, but a rebind
// on an existing variable (`var x *T; x = &m[k]`) skipped loan creation,
// allowing a map insert during the active loan window to pass silently.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `e` (env — GC), `e.services` (map[string]service),
//   `svc` (service pointer holding map-slot loan), `existing`/`fresh` (strings).
//
// ---- Loans traced (non-lexical windows) ----
//   L1 = `svc = &e.services[existing]` — UNIQUE map-slot loan via assignment.
//   Window: assignment → last use (`svc.tag = "scaled"`).
//   The INSERT at `e.services[fresh] = ...` falls INSIDE the window
//   → A3 VIOLATION (HYB-E3102).
//
// ---- Expected verdict ----
// EXPECTED-VERDICT: REJECT A3
//   REJECT — A3 (map-slot loan invalidated by an insert inside the live window).
// ============================================================================

struct service {
    replicas int
    tag      string
}

struct env {
    services map[string]service
}

fn scale_and_register(e *env, existing string, n int, fresh string) {
    var svc *service
    svc = &e.services[existing]        // LOAN L1: map-slot borrow via assignment
    e.services[fresh] = service{replicas: 1, tag: "new"}
                                       // VIOLATION (A3): map INSERT inside L1's live window
    svc.replicas = n                   // L1 use — AFTER the insert
    svc.tag = "scaled"                 // L1 LAST USE: window ends here
}

fn main() {
    e := env{services: map[string]service{
        "frontend": {replicas: 2, tag: "prod"},
        "api":      {replicas: 3, tag: "prod"},
    }}
    scale_and_register(e, "frontend", 5, "cache")
    fmt.println("services: {len(e.services)}")
}
