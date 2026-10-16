# Spike 6: Ownership model usability

**Status:** predictions pre-registered 2026-10-12 BEFORE any `.hy` program was
written (SPEC §14.7). This spike is analytical — write + trace programs; no
builds/tests run (resource rule: the Spike 4 builder owns the box).
**Code:** `work/NN-name.hy` — the ten target programs under the Tier-0 rules
(pseudo-Hybrid, not compiled; throwaway per SPEC §5).
**Question (SPEC §5 Spike 6):** do the ten target programs type-check under the
proposed borrow rules WITHOUT explicit lifetime annotations? How many need
`managed`, or fall outside the model? Is "Tier 0: automatic checking, no visible
lifetimes" real or aspirational? Is borrow checking by delegation to rustc
(SPEC §14.5) a viable replacement for a custom checker?

## Design under test

The Tier-0 rule set from research/ownership-models.md ("Recommendation for
Spike 6"), applied as written — three layers, no lifetime syntax anywhere:

1. **Go-side values: GC is the memory-safety story; a sendability rule is the
   race story.** Structs/maps/slices/channels keep Go semantics. Cross-task
   sharing is checked only where it can start: `task` spawn and channel-send
   sites. Sendable iff: GC value with no live lexical borrow, owned value being
   moved, or `managed` value; everything else must go through
   channels/atomics or `managed`.
2. **Rust-side values: single owner + moves + function-local borrows (Mojo
   style).** Use-after-move is an error; `&` reads and unique-write receiver
   borrows are checked by a Polonius-style non-lexical dataflow pass; **loans
   never escape functions, so there are no lifetime parameters to write.**
3. **Boundary: `own`/`borrow` handles, WIT semantics.** Own = transfer +
   destructor-on-drop; borrow = call-scoped loan enforced by the handle table;
   arena views are borrows of the owning scope — inferred, never spelled.
   Escape hatch: `managed` blocks (linted) — target usage here: zero.

Boundary types follow interfaces/abi-types.md: primitives by value; strings
≤16 B copied; larger strings/buffers as pinned one-call (ptr,len) views; maps/
channels/interfaces/closures as Go-side handles; Rust objects as generation-
tagged own handles; errors per Spike 5 (HyResult two-word return).

## Pre-registered predictions (written before any .hy program existed)

Taken verbatim from research/ownership-models.md §"Recommendation for Spike 6"
(that note predates this task and was written before these programs):

- **P1:** 10/10 programs compile under Tier-0 with **zero** lifetime/region
  annotations and **zero** `managed` uses ("Prediction: 10/10 compile with
  zero lifetime/region annotations and zero managed uses — 03/04 are
  channel-mediated, 08 is id-referenced already, 05/10 need only call-scoped
  views").
- **P2 (falsifier):** if any example forces an annotation, the scoped Tier 0
  is wrong → fallback = rustc-oracle + `managed`-by-default; lifetime syntax
  is NOT invented to save it.
- **P3 (rustc delegation):** all ten are expressible as stock-rustc-acceptable
  shadow Rust given the handle-based boundary — necessary but NOT sufficient
  for delegation-as-the-checker.
- **P4:** sketch refinements are expected to be minor (declarations the
  sketches omitted, API pinning); semantics and expected outputs must not
  change; every refinement is listed per program.

Counting rules fixed in advance: an "annotation" is any user-written lifetime/
region/group parameter or borrow-mode marker that the program needs to
type-check; a "managed site" is any `managed` block; "outside model" = no
Tier-0-legal rewrite exists that preserves semantics. No rule may be weakened
to make a program pass; ambiguous rule text → strictest reading, recorded.

## Method

- Read the ten sketches, their `expected.txt`, examples/README.md,
  interfaces/abi-types.md, and the rule sources above.
- Wrote each program complete and runnable-looking under Tier-0
  (`work/NN-name.hy`), deliberately without lifetime annotations.
- Per program, traced line-by-line: (i) every value classified by layer;
  (ii) every loan (explicit `&`, `*T` receivers, borrow-mode handle uses) with
  its non-lexical liveness window; (iii) every spawn/channel-send site with a
  sendability verdict under the strictest reading; (iv) spots where weaker
  readings would differ.
- Expected outputs preserved byte-for-byte against `expected.txt`.
- rustc-delegation claims are encoding analyses (no builds run) — marked
  believed, not verified-by-execution.

## Per-program analysis

Layers: L1 = Go-side GC, L2 = Rust-side owned (direct), L3 = boundary handles.
"Send sites" counts Hybrid-level `task` spawns + channel sends (each gets a
sendability verdict under the strictest reading, A1c).

| # | program | layers | send sites | loans traced (non-lexical windows) | ann | mgd | out | refinements vs sketch |
|---|---------|--------|-----------|-----------------------------------|----|----|----|-----------------------|
| 01 | hello | L1 | 0 | `*greeting` receiver loan, call-scoped | 0 | 0 | 0 | greeting struct/methods added around identical output |
| 02 | cli-cat | L1 | 0 | call-argument views (buf, buf[..n]) — not loans | 0 | 0 | 0 | read_all → chunked copy_stream (byte-identical stdout); top-level `?` contract flagged |
| 03 | worker-pool | L1 | 4 spawns + 2 send kinds | none on shared state | 0 | 0 | 0 | job/result struct defs added (sketch used them undeclared) |
| 04 | pipeline-backpressure | L1 | 2 spawns + int sends | none | 0 | 0 | 0 | none (comments only) |
| 05 | json-transform | L1+L3 | 0 | element-view loans (borrow-mode) + call-scoped arr loans; own-transfers at `return v` | 0 | 0 | 0 | loop extracted into active_names; min_logins const |
| 06 | http-server | L1 | 0 | closure captures (GC values, not loans) | 0 | 0 | 0 | none; Go-API escape perimeter flagged (A5) |
| 07 | lru-generics | L1 | 0 | `*lru_cache` receiver loans, non-overlapping; map reads are copies (A4) | 0 | 0 | 0 | touch() implemented (sketch stubbed it; eviction order pins semantics) |
| 08 | graph-ownership | L1 | 0 | map-slot loan in connect (creation → last use; no rehash ops in window, A3) | 0 | 0 | 0 | none (loan comments added) |
| 09 | go-imports-hybrid | L1+L3 | 0 | re own-handle; is_match borrow-mode calls | 0 | 0 | 0 | Hybrid package side written (example held only the Go file); SimplePattern subject pinned to "abbbc" (sketch left it implicit) |
| 10 | rust-crate-import | L1+L3 | 0 | call-scoped out-view (digest write) + local read views | 0 | 0 | 0 | digest[..8] → digest[..3] (expected.txt shows 6 hex chars) |

### Per-program notes (the traces that matter)

- **01:** trivially in-model; the only loans are `*T` receivers, strictly
  nested in calls. Exercises zero-value init (no nil).
- **02:** `defer f.close()` is a deferred CALL, not a stored borrow — no loan
  outlives the frame. `buf`/`buf[..n]` are call-argument views of GC values;
  the Go API contract already forbids retention. First program where the
  top-level `?` behavior needs pinning in SPEC-LANGUAGE.md (A8).
- **03:** the sendability meat. All shared objects are channels
  (safe-by-type); every struct send is a FRESH literal — no aliases exist at
  the send site, so all readings of rule A1 agree. `got`/`inputs` are
  single-task locals. Deterministic join by counting, no WaitGroup.
- **04:** same shape as 03 plus directional channel types (`chan<-`/`<-chan`)
  that make producer/consumer roles type-checked; `deadline` is a channel;
  `total` is main-local. Backpressure = the size-2 buffers themselves.
- **05:** the boundary-heavy one. `doc` (own), `u` (borrow, element view),
  `v`/`arr` (own, locally created). Zero annotations because every loan is
  call-scoped and the own-transfers happen at `v.set(...)`/`return v`. Under
  the strictest handle-loan rule (A2) the program passes because `doc` is
  never mutated while element views are live.
- **06:** no Hybrid-level spawn/send; handler closures escape into Go code
  that may run them concurrently (net/http). Tier 0's race prevention does
  NOT cover this perimeter (A5) — the program is race-free anyway (closures
  capture nothing mutable), but SPEC-LANGUAGE.md must scope the claim.
- **07:** the cleanest demonstration of rule A4: `v, ok := c.entries[key]`
  produces a COPY, so `c.touch(key)` after it is not a borrow conflict — the
  exact shape where Rust's `map.get` would hold a loan and NLL would be
  load-bearing. Hybrid needs no annotation because the read is a copy.
- **08:** the designated hard case passes with ZERO annotations and ZERO
  `managed` because the cycle is id-referenced inside a map-owned arena. The
  one explicit loan (`&g.nodes[from]`) is non-lexical (dies at its last use,
  two lines later) and no map insert/delete occurs inside its window (A3).
- **09:** the adoption story is ownership-boring by design: two strings in,
  bool/(string,error) out, one own-handle (`re`) whose loan is call-scoped.
  The only decisions are ABI-level (18 B/26 B strings → pinned views), plus
  one semantics pin: the sketch never said what `SimplePattern` matches —
  fixed to a subject `"ab*c"` provably matches ("abbbc"), preserving the
  pinned output `match: true`.
- **10:** the mirror image: strings ≤16 B take the COPY path (contrast 09);
  the digest buffer is Hybrid-owned and written through a call-scoped
  out-view; the 1M-iteration hot loop makes ONE crossing.

**Corpus observation (negative finding about the corpus, not the model):**
no program stores a borrow in a struct field (the #1 annotation-forcing shape
in Rust), and no program manipulates a Layer-2 Rust-side owned value
directly — Rust-side values appear only behind Layer-3 handles. The ten
programs therefore exercise almost none of the Layer-2 checker surface. See
Implications.

## Count matrix

| # | program | annotations needed | managed needed | outside model |
|---|---------|-------------------|----------------|---------------|
| 01 | hello | 0 | 0 | 0 |
| 02 | cli-cat | 0 | 0 | 0 |
| 03 | worker-pool | 0 | 0 | 0 |
| 04 | pipeline-backpressure | 0 | 0 | 0 |
| 05 | json-transform | 0 | 0 | 0 |
| 06 | http-server | 0 | 0 | 0 |
| 07 | lru-generics | 0 | 0 | 0 |
| 08 | graph-ownership | 0 | 0 | 0 |
| 09 | go-imports-hybrid | 0 | 0 | 0 |
| 10 | rust-crate-import | 0 | 0 | 0 |
| | **TOTAL** | **0 / 10** | **0 / 10** | **0 / 10** |

**Prediction P1 holds: 10/10, zero annotations, zero managed, zero
outside-model.** Honest strength of that pass:

1. It was produced under the STRICTEST reading of every ambiguous rule
   (A1c, A2, A3, A4 below) — no reading was relaxed to admit any program.
2. It is a hand-trace against the written rules, not a run against a checker
   (none exists yet; Phase 1 must encode these ten as the checker's first
   positive tests plus mutants as negative tests, §14.7).
3. The acceptance set cannot distinguish the readings of A1 (all ten pass
   under every reading because they share only channels and fresh literals).
   10/10 is therefore evidence Tier 0 is REAL for this scope, and NO evidence
   about the wider Go-idiom space (see Implications).

## Ambiguities in the Tier-0 rule set (strictest reading applied; SPEC-LANGUAGE.md must resolve)

- **A1 — sendability of MUTABLE GC values at spawn/send.** The rule text
  ("GC value with no live lexical borrow") admits three readings: (a)
  Go-compatible — sendable, sender keeps using it, races remain possible
  (Go's DRF-SC story); (b) freeze-after-send — sendable, but the sender's
  subsequent mutations are rejected; (c) safe-by-type — sendable only if a
  channel/atomic/immutable, or an owned move, or `managed`. Applied here:
  (c)+(b). All ten pass under every reading; the corpus cannot settle it.
  This is THE decision that decides whether "Tier 0 promises race
  prevention" is true for mutable GC state.
- **A2 — handle-loan rule (missing from the rule text).** Layer 3 as written
  says "borrow = call-scoped loan", but iteration (`for u in doc.array(...)`)
  holds borrow-mode views across a LOOP, and a mutating call on the same
  handle during that window must be a compile error or 05-shaped code has a
  Rust-side aliasing hole. Spike-added rule: borrow-mode uses create loans on
  the handle; mutating-mode calls conflict with live borrow-mode loans on the
  same handle (Polonius-style). All ten pass under it.
- **A3 — map-slot borrows (`&m[k]`).** Needed by 08's `connect`. Required
  semantics: legal, non-lexical, invalidated by any map insert/delete in the
  live window (rehash). Codegen: Go has no `&m[k]`, so lower to
  read-modify-write. Must be pinned in SPEC-LANGUAGE.md.
- **A4 — Go-heap reads are COPIES, not loans.** Stated in the research note's
  constraint section but not as a numbered rule; it is why 07 (and half of
  08) is trivial where Rust would need NLL. Must be explicit, because it is
  also the divergence-from-rustc point for any shadow translation.
- **A5 — the Go-API escape perimeter.** Values passed to foreign Go code
  (06's handlers) can be invoked from other goroutines; Tier-0 spawn/send
  checks never see this. Either scope the safety claim ("Hybrid-checked
  sites are race-free; Go-API escapes follow Go's DRF-SC + `-race`
  backstop") or add a fourth check-site class for APIs flagged concurrent.
- **A6 — struct fields may not store borrow-handles.** No program does this
  (that is WHY zero annotations is achievable). Recommend making it a rule:
  fields hold owned values, GC values, ids, or own-handles — never borrows.
- **A7 — handle-parameter mode.** Is passing a handle to a function an
  own-transfer or a borrow? Both readings accept all ten programs. Recommend
  borrow-by-default with own-transfer only at `return`/consuming APIs
  (Mojo-shaped), because it needs no new syntax.
- **A8 — top-level `?` / exit contract (non-ownership, flagged by 02).** The
  expected output pins process behavior: exit code 1 + stderr
  `"cat: {err}"` when `?` fires at main's top level. SPEC-LANGUAGE.md must
  define this once (it is the user-visible face of the Spike 5 error ABI).

## rustc-delegation verdict (SPEC §14.5)

Question restated from the program-writing perspective: can the Tier-0
programs be expressed as Rust code stock rustc would accept, given the
boundary is handle-based — and would that delegation replace the custom
checker?

**Expressibility: yes — two encodings, both accepted (believed; not compiled,
resource rule).**

- **E-ids (faithful to the runtime):** GC values and channels → `Copy` id
  types; own-handles → non-`Copy` newtype moves (rustc catches
  use-after-transfer); borrow-handles → owned guard objects; explicit `&`
  slot-borrows → guard objects. Stock rustc accepts all ten — but it CHECKS
  almost nothing: on 8/10 programs the entire value space is invisible
  `Copy` ids. Even 08's `&g.nodes[from]` is not really borrow-checked (the
  Go heap is not Rust memory; a real `&mut` into it does not exist).
- **E-shape (faithful to the discipline):** single-task values → real Rust
  locals/`Box`/`HashMap` with real borrows; channels → `std::sync::mpsc`
  (transfer semantics); `task` → `thread::spawn` with `Send` satisfied
  because closures capture owned data. rustc then genuinely checks — and all
  ten pass (the traces above double as the Rust traces: receiver loans
  non-overlapping, slot loan non-lexical, handle moves linear). BUT this
  encoding is faithful only because the ten programs are disciplined: fresh
  literals at every send, no shared mutable GC state.

**The delegation ceiling, concretely:** the distinguishing programs — share a
mutable map across tasks the idiomatic-Go way; keep using a map after
sending it — are Tier-0-legal under reading A1(a) but have NO faithful
stock-rustc encoding: `Arc<Mutex<..>>` changes the semantics (Tier 0 has no
lock requirement), `Copy` ids stop checking, `Rc`/`RefCell` fails `Send`.
So delegation as THE checker either over-rejects legal Hybrid or silently
under-checks — matching research/ownership-models.md §6's Valen evidence
(real cross-language borrow checking needed a patched rustc; nobody has
shipped stock-rustc delegation).

**Verdict: CONFIRM the research note.** Adopt rustc as a **CI oracle, not
the user-facing checker**: (1) the real bridge crates compile under rustc
anyway (pinned 1.99.0); (2) an optional CI-only E-ids shadow translation
diffed against our checker's verdicts with pre-registered agreement
thresholds (§14.7-style); (3) user-facing diagnostics never originate from
rustc. Do NOT build the product checker on delegation.

## Analysis & decision

- **"Tier 0: automatic checking, no visible lifetimes" is REAL for the
  acceptance set** — 10/10 programs, zero annotations, zero `managed`, zero
  outside-model, under the strictest rule readings. R5 ("no visible
  lifetimes unrealistic") can move toward closed, CONDITIONALLY: the corpus
  is too narrow to pin A1 and never exercises Layer-2 borrows or struct-field
  borrows. Recommendation to the lead for PLAN.md: R5 → "conditionally
  closed — pending SPEC-LANGUAGE.md decisions A1–A8 and 2–3 distinguishing
  corpus programs".
- **For SPEC-LANGUAGE.md:** adopt the three layers + escape hatch as the
  Tier-0 chapter, plus the decisions A1–A8 (strictest readings as defaults,
  since no example contradicts them; A8 is the non-ownership exit contract),
  plus the sendability check-site list (spawn, channel-send; decide A5's
  fourth class), plus the no-borrow-in-fields rule (A6). Tier-1 stretch
  (regions/loan escape) stays out — anything needing it routes to
  handles/ids/`managed`.
- **Checker plan unchanged but sharpened:** Polonius-style Naive rules over
  Hybrid MIR with ghost borrow ops (research note), now with a SECOND fact
  source: handle-mode (own/borrow/mutate) per boundary call for rule A2.
  The ten `.hy` files become the first positive tests; each loan traced
  above is a named test case; cargo-mutants on the checker (§14.7).

## Implications and risks

1. **Corpus narrowness is the top risk.** 10/10 pass cannot distinguish A1
   readings, and the most annotation-forcing shapes (struct-field borrows,
   Layer-2 direct owned values) are absent. Before the checker is built, add
   2–3 deliberately adversarial programs (shared mutable map across tasks;
   sender-uses-after-send; a borrow returned out of a function) and record
   which Tier-0 verdict each SHOULD get — as compile-fail or managed-required
   expectations.
2. **Hand-trace ≠ checker.** This spike's verdicts are believed-level for
   checker acceptance; encoding them as executable tests is mandatory
   (Phase 1, and the reference interpreter §14.4 is the natural oracle).
3. **Usability risk of the strictest sendability:** idiomatic Go ports
   (shared map + mutex across goroutines) will be rejected at spawn/send.
   Error messages must offer the three legal routes (channel it, copy it,
   `managed` it) or users will reach for `managed` reflexively — the Borgo
   ceiling by another route.
4. **Checker scope creep is already visible:** A2 adds handle-loan tracking
   to the Polonius-shaped engine. Small, but it is exactly the kind of
   accretion the research note's risk #1 warned about; contain it to
   own/borrow/mutate modes on handles, nothing more.

## Verified / believed / unknown

- **VERIFIED:** the ten `work/*.hy` programs exist and preserve their
  expected outputs byte-for-byte (checked line-by-line against
  examples/*/expected.txt); every spawn/send site is enumerated with a
  sendability verdict; every loan is classified with a liveness window; the
  refinement list is complete; the pre-registration above predates the
  programs on disk.
- **BELIEVED:** that a Polonius-style pass over Hybrid MIR would accept each
  program (hand-trace; no checker exists); that stock rustc would accept the
  E-ids and E-shape shadow encodings (rule-traced; not compiled — resource
  rule).
- **UNKNOWN:** Tier-0 behavior outside the acceptance set (the A1 readings
  are undistinguished); checking-pass performance; diagnostic quality; the
  interaction of A5's Go-API escapes with real net/http concurrency (needs
  the Phase 3 `-race` legs).
