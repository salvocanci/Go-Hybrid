# Research Claims Verification (SPEC.md §3)

Compiled 2026-10-11 from the prior-art study in `research/`. Per SPEC §0.1: every
§3 claim marked CONFIRMED / CORRECTED / UNVERIFIABLE, with evidence in the linked
note. Statuses below are the spec-author's memory vs. what the sources actually say.

## Prior-art table

| Project | SPEC's claimed role | Verdict | Detail |
|---------|--------------------|---------|--------|
| **rustygo** (KarpelesLab) | Go→Rust compiler w/ Rust runtime; ~125/141 tests; goroutines/channels/select/net/http; single-threaded due to scheduler memory corruption | **CONFIRMED (all four), one CORRECTED number** | Active (v0.0.3, 2026-09-29), MIT. Tests: **127/141** today. Single-threading: ROADMAP M2 failure matrix — GOMAXPROCS=2 → 14/20 correct w/ stalls; =4 → 0/20, 18 segfaults, 1 `pick` assertion. Root suspects: saved-context acquires a worker's native SP; `map.rs` UnsafeCell; `heap::Global` double-checked init; missing Context owner-tag. See [rustygo.md](rustygo.md). |
| **rustgo** (FiloSottile) | asm-level Rust calls from Go bypassing cgo; ~40ns/call; archived | **CONFIRMED technique; CORRECTED twice** | Repo now **deleted (404)**, not merely archived. Actual cost: **4.58–5.11 ns/call** (2–11% over a Go call; cgo 69–74ns = ~15x slower) — the "~40ns" in our SPEC was cgo-era folklore. Technique verified via surviving demo repo + article. See [rustgo.md](rustgo.md). |
| **rust2go** (ihciah) | FFI framework w/ async; production use at ByteDance | **CONFIRMED (async); CONFIRMED w/ nuance (ByteDance)** | Active (429★, pushed 2026-10-05). Async = atomic slot + waker + hand-written amd64/arm64 asm trampolines; **29.19ns cgo → 2.324ns asm** on go1.22. ByteDance: author's personal project, used in production by his team there — not an official ByteDance product. Pain points: cross-compilation is issue #1; requires `GODEBUG=invalidptr=0,cgocheck=0`; no enums/maps/cycles. See [rust2go.md](rust2go.md). |
| **Borgo** (borgo-lang) | Rust-like language compiling to Go source; closest prior art; why it stopped | **CONFIRMED (all); RESOLVED: it stopped** | ~12.5k-line Rust compiler, zero parse deps, HM inference, Maranget exhaustiveness (from Roc, UPL-1.0). Dead: last commit 2024-10-27, 167/168 commits by one author, **no license at all** (#41), no releases, issue "Dead Project?" unanswered. See [borgo.md](borgo.md). |
| **TinyGo** | Alternative Go compiler (LLVM); possible Go-side backend; runtime/GC choices | **CONFIRMED; CORRECTED as an embeddable component** | Usable as a black-box toolchain, not as a library (pins one LLVM commit, no stable API). Runtime is a configurable matrix: **6 GC strategies × 5 schedulers × 4 unwind strategies**. Building LLVM from source is not viable on our 2-core/4GB box. See [tinygo.md](tinygo.md). |
| **CXX** (dtolnay) | Limits representing `Option`, ownership | **CONFIRMED** | `Option<T>` row in README types table literally reads "tbd"; ownership only via builtin smart-pointer pairings. See [interop-tools.md](interop-tools.md). |
| **Crubit** (google) | Limits representing `Option`, ownership | **CORRECTED (refined)** | DOES bridge `std::optional` ↔ `Option<T>` (layout-compatible Rust-side). Real limits: `-fno-exceptions`, panic→abort, unchecked C++ lifetime conventions, non-movable types, no template automation. See [interop-tools.md](interop-tools.md). |
| **c2rust / Corrode** | Why syntax-level translation yields unsafe output | **CONFIRMED** | C carries no aliasing/ownership/lifetime info ⇒ translator must emit raw pointers + `unsafe`. c2rust output: "unsafe and unidiomatic… first step in a longer migration". Safety recovery (c2rust-analyze + Polonius) is prototype-stage. See [interop-tools.md](interop-tools.md). |
| **WASM component model / WIT** | Language-neutral interface defs; shared ABI/type layer? | **CONFIRMED as IDL; CORRECTED as literal ABI** | WIT's type universe + `own`/`borrow` resource semantics + worlds are runtime-independent and reusable as Hybrid's IDL. The Canonical ABI is defined against linear memory + i32 handle tables — must be **re-lowered onto the C ABI** for a native Go↔Rust link. See [wit-abi.md](wit-abi.md). |

## Root-cause hypotheses (SPEC §3)

| # | hypothesis | verdict | evidence |
|---|-----------|---------|----------|
| 1 | Runtime model mismatch (GC + growable stacks vs ownership + fixed stacks) | CONFIRMED as the central tension | rustygo's whole runtime exists to reconcile this; rust2go's `GODEBUG` requirement is a symptom |
| 2 | Stack management conflicts (Go stacks grow AND move) | CONFIRMED, with precision | Go stacks are *non-moving* heap objects scanned by GC; the hazard is Go **stack** movement + invisible pointers, not a "moving GC" — matches SPEC's own correction; rustygo M2's "saved context acquires a worker's native stack pointer" is exactly this class |
| 3 | GC boundary safety | CONFIRMED as hazard, tractable | cgo pointer rules + cgocheck enforce the same invariants; Spike 1's mmap'd-stack design sidesteps stack scanning (documented hazards in RESULTS.md) |
| 4 | Type-system translation loss | CONFIRMED | Borgo's mapping tables (enum→tagged struct+iota, Result→(T,error) at fn boundaries, Option→(T,bool)) prove a workable subset; CXX/Crubit limits confirm the edges |
| 5 | Build system fragmentation | CONFIRMED | rustygo: needs both toolchains; rust2go: cargo build.rs shells out to `go build -buildmode=c-archive`; Borgo died partly on two-toolchain UX; our Spike 2 proves single-command `go build` emission is achievable |

## Searches to run (SPEC §3)

GitHub/arXiv searches superseded by direct source study this session (agents
read the repos themselves — stronger evidence than search-result triage).
Remaining for later sessions: arXiv "verified compiler translation",
"concurrent scheduler verification"; Go runtime sources for Spike 3-5
(`runtime/proc.go`, `runtime/stack.go`, `runtime/mgc.go`, internal ABI docs);
Polonius/borrow-checker research for Spike 6. Recorded as pending, not done.

## Meta-lessons for Hybrid (cross-cutting)

1. **The graveyard is informative**: rustgo (deleted), Borgo (dead, unlicensed),
   Corrode (archived). Common death causes: single maintainer, no license, no
   releases/binary distribution, two-toolchain UX friction, silent abandonment.
   Hybrid's countermeasures: dual MIT/Apache license on day one; CI + releases;
   one-command build; this repo as the durable home.
2. **The sub-10ns crossing is real and reproducible** (rustgo 4.6ns, rust2go
   2.3ns, our own spike-1 2.82ns safe variant) — but every author warns about
   the same trade: long-running foreign calls block preemption. Hybrid needs
   the bounded-blocking-pool answer (Spike 4's question) before shipping it.
3. **Source-to-source emission survives Go's toolchain churn** (Borgo→Go source
   worked for years; binary-only is dead). Spike 2 confirms with `//line`
   diagnostics mapping.
4. **GOMAXPROCS>1 corruption in rustygo is the exact risk class** our boundary
   design must not inherit: never let foreign code touch Go-managed stack
   state; our trampoline never stores cross-call state (verified under
   scheduler migration).
