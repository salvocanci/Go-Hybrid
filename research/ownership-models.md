# Ownership Without Visible Lifetimes — research note (Task 5-b)

Study for Spike 6: how other languages prevent UAF/data-races without users
writing lifetime annotations, and what Hybrid's Tier-0 ("automatic checking, no
visible lifetimes", SPEC §5 Spike 6 / PLAN R5) should actually promise. Live
evidence fetched 2026-10-11 (pages + raw files; no clones). Quotes verbatim;
anything not fetched today is marked UNVERIFIED.

## Constraint set

Hybrid compiles to **Go source** (Spike 2 14/14): the Go-side heap is GC'd and
shared across goroutines; the Rust side has real ownership; the boundary is
handle-based per the Spike 3 direction (WIT `own`/`borrow` + handle table,
research/wit-abi.md; address-broker + trampoline, Spike 1). The ten `examples/`
are the acceptance set — 03/04 share state only via channels, and 08 already
solves cycles with **id-references into a map-owned arena** ("references by
id: no shared mutable borrows"). The recommended model must make those shapes
*fall out*, not fight them.

## Identity matrix

| project | role here | license | activity (2026-10-11) | status |
|---|---|---|---|---|
| [Vale](https://github.com/ValeLang/Vale) | generational references + regions | Apache-2.0 (`LICENSE` fetched from `master`) | ~2k stars (badge); "Vale is archived and no longer being worked on" (README) | dead; successor below |
| [Valen](https://github.com/valen-lang/valen) | Vale's successor: group borrowing + rustc interop | Apache-2.0 (API) | 502★, created 2026-08-15, pushed 2026-10-11 | prototype ("barely past the proof-of-concept stage", README) |
| [Hylo](https://github.com/hylo-lang/hylo) (ex-Val) | mutable value semantics, no references | Apache-2.0 (README "License" section) | ~1.6k★ (badge), last commit July 2026 | old impl; "Most of our efforts now go towards the new compiler at https://github.com/hylo-lang/hylo-new" (README); hylo-new ~52★, commits today |
| [Mojo](https://github.com/modular/mojo) | ownership + argument conventions + origins | Apache-2.0 **with LLVM exceptions** (`LICENSE`: "The Modular repository is licensed under the Apache License v2.0 with LLVM Exceptions") | 29,940★, pushed 2026-10-09 (API; `modular/mojo` and `modular/modular` share numbers — one repo, renamed/merged) | production push; "Mojo is now fully open source" since 2026-08-18 (blog) |
| [Polonius](https://github.com/rust-lang/polonius) | the NLL borrow-check algorithm | Apache-2.0 (API) | 1,753★, created 2018-05-01, pushed 2026-10-02, 41 open issues | experimental crate; never replaced rustc's checker |
| [Gleam](https://github.com/gleam-lang/gleam) | immutability-only contrast row | Apache-2.0 (API) | 21,987★, pushed 2026-10-08 | mature (BEAM) |
| Borgo / Go | ceilings and contrasts | (none) / BSD-style | research/borgo.md; go.dev/ref/mem | n/a |

## 1. Vale — single ownership, no borrow checker, runtime generation checks

**Mechanism.** Every heap allocation carries a generation counter; a reference
is "simply a pointer with a 'remembered generation' number next to it"
(verdagon.dev/blog/generational-references). Dereferences call `__check`, which
compares the remembered generation to the allocation's current one and traps on
mismatch — UAF becomes a deterministic abort. Data races are handled by thread
isolation + message passing ("Similar to Rust, each thread's memory is isolated
from the rest", regions post side-note). Optional **region borrow checking**
removes the checks. **Fearless FFI** walls off foreign memory (separate stacks,
scrambled cross-references, copy-based message passing).

**Annotation burden.** Pure-GR mode: zero — "memory-safe single ownership
without garbage collection or a borrow checker" (README). Region mode: visible
region parameters — "By adding the `r'` to strongestDesire's `this &Unit`,
we're telling the compiler that this will come from a region we call `r'`";
"`'r ro` and `i'` are regions" (zero-cost-refs-regions post). Regions are
lifetimes under another name; Vale's docs admit the model churned four times.

**Runtime cost.** Generation checks on every deref, near-zeroed inside
regions; "regions and hybrid-generational memory would eliminate every single
generation check" in their cellular-automata benchmark (vale.dev/memory-safe —
which concedes those features are "upcoming… not available yet").

**Compile-time cost.** Minimal in GR mode; region mode adds a region checker.

**Maturity / licensing.** Archived (README note, Sep 2026); Apache-2.0; ideas
live on in Valen. **Fit for Hybrid.** GR-style runtime checks are the *opposite*
of our budget (the Go side already has a GC — memory safety there is free), but
Vale's region story is the cautionary tale for Tier-1 stretch, and Fearless
FFI's safe/unsafe memory separation is directly reusable at our boundary.

## 2. Valen — group borrowing, borrow-checking *across* the rustc boundary

The successor (Evan Ovadia, with Nick Smith) pivots to **compile-time** safety:
group borrowing allows mutable aliasing within declared "groups". "These are
group annotations… Note that the call site doesn't explicitly have to supply a
group for `r`, the compiler will infer it" (verdagon.dev/blog/group-borrowing,
Aug 2025). Crucially for us: "group borrowing can actually be a superset of
Rust's borrow checking, making it so we can borrow-check over the boundary…
this prototype is doing some borrow checking over the boundary!" (golden-spike
post, Sep 17 2026). The price: cross-language generics + borrow checking
required a **patched rustc** — users build `valen-lang/rust`, branch
`per-instance-mir`, and a companion-compiler dance (README build instructions).
Annotations: callee-side group parameters (`fn attack [mut r: group Entity](ref
[r] a: Entity, …)`), inferred at call sites. Runtime cost zero. Maturity:
months-old prototype, Apache-2.0, solo author. **Fit:** the strongest live
evidence for *seam-level* borrow checking with Rust — and equally strong
evidence that doing it against stock rustc tops out.

## 3. Hylo — value semantics; lifetimes "simply do not exist"

**Mechanism.** No references at all: "references become second-class citizens:
they are only created implicitly, at function boundaries, and cannot be stored
in variables or object fields. Hence, variables can never share mutable state"
(Implementation Strategies for Mutable Value Semantics, JOT, repo `Docs/`).
All types are value types; mutation happens through *projections* — subscripts
that `yield` a value in `let`/`inout`/`set`/`sink` access modes (`&` "does not
mean 'address of'—it simply marks a mutation", hylo-lang.org/introduction).
UAF is impossible because nothing outlives its unique owner; data races:
"Hylo's foundation of mutable value semantics ensures that ordinary code is
memory safe, typesafe, and data-race-free" (introduction) — concurrency
`spawn`s receive disjoint projections of a split container (concurrency tour),
though "The concurrency approach of Hylo is still under design".

**Checking.** "Safety guarantees in Hylo programs are verified by an abstract
interpreter processing an intermediate representation, Hylo IR, that models
lifetime properties with ghost instructions" (Borrow checking Hylo, IWACO
2023, Racordon & Abrahams — abstract fetched). Lowered IR shows the ghost
ops verbatim: `borrow [let]`/`end_borrow`, `project`/`end_project`
(`Docs/Subscripts.md`). **Annotation burden: zero** — "Lifetime annotations
were not elided, they simply do not exist in Hylo because it uses a simpler
model, devoid of references" (introduction). **Runtime cost:** none (copies and
COW are explicit-ish; no check instructions). **Compile-time:** the abstract
interpreter pass. **Unsafe:** opt-in and *literally named* — stdlib pointers
expose `public subscript unsafe(): Pointee` with a `- Requires:` doc comment
and no static check (`StandardLibrary/Sources/Core/Pointer.hylo`). **Maturity:**
"under active development and is not ready to be used yet"; Apache-2.0;
compiler being rewritten (hylo-new). **Fit:** the only system with *zero*
annotations by construction — but its price is no shared heap at all, while
Hybrid *inherits* Go's shared heap. We can borrow the ghost-instruction IR
shape for our checker and the named-unsafe discipline, not the language model.

## 4. Mojo — invisible-borrow-by-default + a lifetime checker

**Mechanism.** "Mojo helps avoid these errors by ensuring there is only one
variable that owns each value at a time, while still allowing you to share
references with other functions" (Ownership manual, v1.1.0). The trick is
**argument conventions**: the default is an immutable reference with no sigil
at call sites — "Mojo doesn't require a sigil on the caller side to pass by
immutable reference" — while `mut` gives a mutable reference, `var` takes
ownership (postfix `^` transfers), `ref`/`out`/`deinit` are special. SPEC's
memory of `borrowed`/`inout`/`owned` is the 2023-era spelling — **CORRECTED**:
current docs (1.0.0 and 1.1.0, live-checked) use
`default`/`mut`/`var`/`ref`/`out`/`deinit`; same semantics, Python-shaped
keywords. Aliasing errors are compile errors: "error: passing `my_string` mut
is invalid since it's also passed as an immutable reference" (manual).
**Lifetime inference:** a compiler pass tracks *origins*; "Most of the time,
origins are handled automatically by the compiler. However, in some cases
you'll need to interact with origins directly", e.g. `Span` views parameterized
on an origin, where "the origin parameter is inferred from the list argument,
and then used as the origin for the returned Span" (Lifetimes, origins, and
references). The old "ELIDs" term no longer appears in current docs
(UNVERIFIED-live for the term itself). `@parameter` survives only as a
**deprecated** legacy-closure decorator ("The @parameter decorator is deprecated
and will be removed in a future release", 1.0.0 reference) — compile-time
parameters are now bracket-declared. **Data races:** not addressed by the
fetched ownership docs (no thread/race/Send-Sync content) — Mojo's checker
targets UAF/aliasing. **Runtime cost:** zero checks; the ergonomic cost is
*implicit copies* ("def creates an implicit copy of the list because it's
mutated"). **License — CORRECTED vs SPEC-era knowledge:** Mojo was source-available-restrictive,
but "We are happy to announce that the Mojo🔥 language is now fully open source
under the Apache 2.0 license (with LLVM exceptions)!" (modular.com/blog/mojo-open-source,
2026-08-18; stdlib earlier, compiler then). Still reference-only for us: a
Bazel+LLVM monorepo we will not vendor, single-company governance (Qualcomm
acquisition noted on the same page). **Fit:** the best evidence that
"immutable borrow by default + caller-side inference + a lifetime checker" is
shippable — the interaction model Tier 0 should copy for Hybrid's Rust-side
values.

## 5. Polonius — the NLL dataflow engine (could it power Tier 0?)

**What it is.** "This is a core library that models the borrow check" (README)
— it implements Matsakis's "An alias-based formulation of the borrow checker"
(Apr 2018): regions become sets of loans, `'a ⊆ 'b` becomes a subset relation
over loans, and the whole checker is Datalog rules over facts (loans, regions,
program points) that rustc can dump with `-Znll-facts`. Naive rules are
readable; `-a LocationInsensitive` is "faster, but may yield spurious errors";
the optimized Datafrog variant ran a clap function's facts in 3.856 s (README
example — whole-crate scale, a warning about naive-rule cost).

**Status.** The book still says "Polonius has been provisionally integrated
into rustc… However, it is not really ready for widespread use" — stale text;
the repo (Apache-2.0, 1.7k★, sporadic pushes, 2026-10-02) never replaced rustc's
hand-written NLL checker. **Could it power Tier 0?** Yes, *scoped*: for
**function-local** borrows, loans never escape, so there are no region
parameters to name — the exact reason Hylo needs none. A Hybrid MIR with
borrow/invalidation facts (Hylo's ghost instructions are the same shape) plus
Naive-Polonius rules gives non-lexical, inference-only checking of every
function body; at `task`/channel-send sites we add one more fact type
(sendable-or-not) and reuse the same dataflow. That is a small, testable engine
(the Naive rules fit in a screenful) — not a lifetime system. What Polonius
does NOT give: anything about goroutine-shared Go heap state; that is a
sendability discipline, not a loan graph.

## 6. rustc delegation (SPEC §14.5) — evaluated

SPEC §14.5: "consider generating a shadow Rust translation of every Hybrid
program purely to run `rustc`'s borrow checker, then map its diagnostics back
to Hybrid source."

**What it catches** (if the shadow translation is faithful): use-after-move,
`&mut` aliasing, and lifetime errors on the Rust-shaped subset — Hybrid's
owned values, arena views, boundary handles — for free, with a battle-tested
checker. Encodings can stretch it: mapping `task`→`std::thread` and Go-heap
handles→non-`Send`/non-`Sync` types would even catch some cross-task races.

**What it cannot catch, or gets wrong:**
- *Go-heap semantics don't exist in Rust.* GC'd maps/slices/structs shared
  across goroutines have no faithful Rust analogue. The only sound lowering is
  rustygo's: shared objects become **runtime handle-table indices** — which are
  `Copy`, i.e. invisible to the borrow checker (research/rustygo.md: the emitted
  code is safe Rust, yet rustygo's own multithreading corruption happened
  inside exactly this runtime layer).
- *False positives on legal Hybrid code:* rustc will reject aliasing that Go
  semantics allow (example 08's `&g.nodes[from]` while the map lives on) unless
  we lower it to handles — at which point rustc stops checking it. SPEC §14.5
  itself says to note "error quality, inference differences".
- *Diagnostic ergonomics:* span mapping is proven (Spike 2 E1a/E1c: `//line`
  directives make panics land on `sample.hy:15`), but rustc's *messages*
  (E0499-speak about borrows the user never wrote) would leak our lowering
  strategy into every error.
- *Coupling & cost:* user-facing correctness would depend on rustc internals
  (diagnostics churn; we pin 1.99.0, but every Hybrid build then compiles a
  second, throwaway Rust translation — pure compile-time tax). Valen's
  experience is the ceiling check: real cross-language borrow checking needed a
  **patched rustc fork** (`per-instance-mir`); nobody has shipped stock-rustc
  delegation.

**Verdict on §14.5:** keep rustc as an **oracle, not the checker** — the Rust
bridge crates we generate for real (they must compile anyway) plus an optional
CI-only shadow translation, diffed against our own checker's verdicts
(§14.7-style pre-registered agreement thresholds). That captures the
"battle-tested checker" value with zero user-facing coupling.

## 7. Borgo's lesson and the Gleam/Go contrast row

**Borgo** (research/borgo.md): transpiles Rust-*syntax* to Go with **no
ownership checking at all** — `mut` is a lint, issue #44 (ownership +
goroutines) unanswered; "no move semantics, no ownership… the value
proposition stops at the frontier of what Go's runtime model can express".
That is Hybrid's floor: syntax borrowing without a checker is a ceiling, not a
safety story. **Gleam**: races prevented by removing mutation — "Gleam is an
immutable language… the values they reference are immutable" (tour.gleam.run),
with BEAM process isolation doing the rest. **Go itself**: UAF prevented by
GC; data races explicitly *not* — "programmers are strongly encouraged to use
appropriate synchronization to avoid data races… races are errors and that
tools can diagnose and report them" (go.dev/ref/mem, DRF-SC). Hybrid cannot
take Gleam's route (our point is Go-heap interop), and must not take Go's
(Tier 0 promises race prevention).

## Comparison table

| approach | catches UAF | catches data races | user annotations | runtime cost | implementable by us | verdict |
|---|---|---|---|---|---|---|
| Vale GR mode | yes (trap) | via thread isolation | **none** | generation check/deref | n/a (we have GC) | adopt nothing; Fearless-FFI ideas only |
| Vale regions | yes | via thread isolation | **region params on fns** | ~zero | big lift | Tier-1 stretch cautionary tale |
| Valen group borrowing | yes, across boundary | unclear (single-threaded today) | group params on fns (callers inferred) | zero | needs patched rustc | watch; do not copy |
| Hylo MVS | yes by construction | yes (disjoint projections; design WIP) | **none — lifetimes don't exist** | zero | model too alien for Go heap | borrow IR ghost-ops + named-unsafe |
| Mojo | yes (lifetime checker) | not in fetched docs | none at call sites; `mut`/`var` on params | zero (implicit copies in def) | partially | **adopt interaction model for Rust-side values** |
| Polonius-as-engine | yes (what we feed it) | only via extra sendability facts | none (inference-only if loans are local) | zero | **yes — small Datalog/dataflow pass** | **engine for Tier 0** |
| rustc delegation | Rust-shaped subset only | only via Send/Sync encoding (lossy) | none | zero | oracle-mode only | **CI oracle, not user checker** |
| Borgo | no | no | — | — | — | the ceiling we must beat |
| Gleam | (n/a, immutable) | yes by immutability | — | BEAM costs | n/a | contrast row only |

## Recommendation for Spike 6

**Tier 0 is real if we scope it to three layers, none of which has lifetime
syntax:**

1. **Go-side values: GC is the memory-safety story; a sendability rule is the
   race story.** Structs/maps/slices/channels keep Go semantics (GC kills UAF
   for free — Borgo's floor becomes our foundation). Cross-task sharing is
   checked only where it can start: `task` spawn and channel-send sites. A
   value is sendable iff it is a GC value with no live lexical borrow, an owned
   value being moved, or a `managed` value. Everything else must go through
   channels/atomics or `managed`.
2. **Rust-side values: single owner + moves + function-local borrows, Mojo
   style.** Owned values move on assignment; use-after-move is an error.
   Inside a function body, borrows (`&` read, unique-write for `*T` receivers
   per example 08) are checked by a Polonius-style non-lexical dataflow pass
   over Hybrid MIR (borrow/end_borrow ghost ops, Hylo's shape; Naive rules,
   location-insensitive variant if profiling demands). **Loans never escape
   functions, so there are no lifetime parameters to write — ever.** Functions
   needing longer-lived access return handles/indices (the example-08 id
   pattern) or use `managed`.
3. **The boundary: `own`/`borrow` handles, WIT semantics.** Own = transfer +
   destructor-on-drop; borrow = call-scoped loan enforced by the handle table
   with debug-mode lend-count assertions (wit-abi.md lesson: pair the
   convention with generated assertions, don't trust it). Views into arenas
   (examples 05/10) are borrows whose region is the owning scope — inferred,
   checked by the same pass, never spelled.

**Escape hatch.** `managed` blocks per SPEC §7/§8: opt-in GC/atomic-refcounted
shared mutability for cyclic or heavily-shared graphs; inside them the
contract is Go's DRF-SC discipline with debug-build race instrumentation
available, and the block is linted so "Tier 0 safe" claims exclude it. This is
Vale's check-override/`unsafe` discipline and Hylo's *named* `unsafe[]`
subscript, shaped for a GC'd world.

**Spike 6 protocol:** write examples 01–10 in pseudo-Hybrid under this rule
set; count (a) programs rejected, (b) `managed` sites, (c) any annotation
sites. Prediction: 10/10 compile with **zero** lifetime/region annotations and
**zero** `managed` uses — 03/04 are channel-mediated, 08 is id-referenced
already, 05/10 need only call-scoped views. If any example forces an
annotation, the scoped Tier 0 above is wrong and we fall back to rustc-oracle +
`managed`-by-default before inventing lifetime syntax.

## Top 3 risks and mitigations

1. **Checker scope creep → a second lifetime system.** rustc's own NLL took
   years; Polonius itself is "not really ready for widespread use".
   *Mitigation:* the rule set above is deliberately total (GC + local loans +
   sendability at spawn/send); any feature that would need loan escape is
   rerouted to handles/`managed`, never to annotations. Mutation-test the
   checker (cargo-mutants, §14.7); pre-register that it never appears in a
   user-facing signature.
2. **Sendability over/under-rejection.** Over-rejection pushes users to
   `managed` everywhere (Borgo ceiling by another route); under-rejection
   misses Go-map aliasing races — exactly rustygo's `map.rs` `UnsafeCell`
   class. *Mitigation:* conservative default (reject when any live lexical
   borrow escapes a spawn/send); a state-ownership discipline table for the
   runtime (rustygo `tls.rs` lesson); loom/shuttle model-checking of the
   primitives (§14.5); `go test -race` on every emitted program as the
   backstop oracle.
3. **rustc coupling & version churn** (oracle mode, bridge crates, and the
   temptation of §14.5 delegation). *Mitigation:* rustc appears only in CI
   oracle mode and in compiling the real bridge crates (pinned 1.99.0);
   user-facing diagnostics never originate from rustc; a matrix job (R2)
   guards pins; Valen's patched-rustc outcome is documented as the boundary of
   this road.

## Licensing

Vale/Valen/Hylo/Polonius/Gleam: Apache-2.0; Mojo: Apache-2.0 with LLVM
exceptions (same family as wit-bindgen/wasm-tools in our stack). All
compatible with dual MIT/Apache-2.0 for *idea* reuse; nothing here warrants
vendoring code except possibly Polonius's Naive rules (Apache-2.0, tiny,
re-derivable anyway — we would reimplement the Datalog rules from the
README/paper, which are facts/techniques).

## Verification log

Fetched live (2026-10-11, no clones): ValeLang/Vale README + LICENSE; valen
README; verdagon.dev posts (golden-spike, group-borrowing, generational-
references, zero-cost-refs-regions); vale.dev/memory-safe; hylo-lang.org
introduction + language-tour (concurrency, subscripts); hylo repo README,
`Docs/Subscripts.md`, `StandardLibrary/Sources/Core/Pointer.hylo`, MVS PDF;
IWACO 2023 abstract; Mojo ownership + lifetimes + `@parameter` docs (1.0.0 &
1.1.0); modular.com/blog/mojo-open-source; modular/mojo + modular/modular
LICENSE files; polonius README + book; Matsakis's alias-based post;
tour.gleam.run/everything; go.dev/ref/mem. API metadata succeeded for
polonius/gleam/modular/valen; Vale/hylo/hylo-new hit the shared-IP rate limit —
star counts from img.shields.io badges (approximate, UNVERIFIED-live). Mojo's
older `borrowed`/`inout`/`owned` spelling and the "ELIDs" term are absent from
current docs (UNVERIFIED-live as historical terms).
