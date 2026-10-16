// ============================================================================
// 28-composite-nil-reject — Checker corpus #28 (the PLAN follow-up row from
// the external adoption audit: composite-literal nil fields).
//
// PURPOSE: pin the N1 rule for NILS NESTED INSIDE COMPOSITE LITERALS. The
// audit's repro is (S1): `job{m: nil}` with a map-typed field passed the
// checker with 0 diagnostics — classify_composite has no per-field type
// context, so the bare-nil check at the five direct-flow sites never saw
// the nested nil, and the emitted Go died at go build (or worse: a nil map
// field that panics on first write at runtime). The literal carries its own
// type context (the struct def), so the nil rejects as a TYPE error right
// at the literal — N1's doctrine (a type contract, not a sendability doubt;
// it fires inside `managed` too, S4). Distinct from the direct-nil case
// (`var s []int = nil`, ascribed locals — the audit batch's five sites):
// here the nil never crosses a boundary as a value at all in (S2); the
// define path alone must reject it.
//
// S1: the audit's repro — spawn arg literal with a nil map field
// S2: a plain local define `j := job{m: nil}` (no boundary involved)
// S3: map literal value slot `map[string][]int{"k": nil}`
// S4: the managed hatch does NOT suppress it (type contract, O6 boundary)
//
// EXPECTED-VERDICT: REJECT N1
// ============================================================================

struct job { m map[string]int }

fn worker(j job) { j.m["k"] = 1 }

fn main() {
  // S1: the audit repro — used to emit `jobs <- job{m: nil}`-shaped Go
  // that compiled to a nil-map field written by the task.
  j := job{m: nil}
  task worker(j)

  // S2 would reject on its own (no boundary needed):
  //   j2 := job{m: nil}

  // S3 shape: map literal value slot — same slot-typed nil rejection.
  //   mm := map[string][]int{"k": nil}

  // S4 shape: managed does not suppress the type error:
  //   managed("rebuild inside the worker", "actor") { task worker(job{m: nil}) }
}
