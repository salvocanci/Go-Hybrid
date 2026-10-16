# Spike Report — Phase 0 Feasibility (SPEC §5 spike gate)

**Status:** all six spikes executed on both required tiers; this report
closes Phase 0 and feeds gate G0 (`gates/G0.md`). Written 2026-10-12 after
Spikes 0–6; Spike 4's worker tier (job 005 v9, all green, 521 s) confirms
the sandbox numbers and corrects one interpretation (the ~0.9 ms syswin
pair cost is intrinsic, not environment-specific — see the relaxed-targets
ledger).
**Rule:** nothing here is aspirational — every number traces to a
pre-registered threshold in the spike's RESULTS.md and a run that exists in
git history.

## Executive summary

The SPEC's core hypotheses **held**, with three pre-registered fallbacks
firing exactly as designed and two real crashes found and absorbed into the
design (the best kind of spike outcome). The architecture is now decided
end-to-end:

> Hybrid emits **Go source** (zero-install adoption), keeps Go's GC and
> scheduler, and crosses into Rust through a **~2.4 ns guard-checked
> trampoline** on the caller's own goroutine stack — with **owning-side
> generation-tagged handle tables** for objects, **two-word HyResult**
> returns for errors, a **two-tier blocking design** (entersyscallblock
> lane + bounded concurrency-sized pool) for foreign calls that block, and
> a **Tier-0 ownership model** (GC + sendability checks on the Go side,
> single-owner + function-local borrows on the Rust side, own/borrow
> handles at the boundary) that the ten MVP target programs traverse with
> **zero lifetime annotations and zero escape hatches**.

No kill/pivot criterion was triggered; the SPEC's "if two core spikes fail"
clause never armed. Phase 1 (SPEC-LANGUAGE.md → MVP-0) is cleared to start
after G0.

## Per-spike verdicts

| Spike | Question | Pre-registered verdict | Decision it fired |
|-------|----------|------------------------|-------------------|
| 0 compute | Do the 3 tiers work end-to-end? | **PASS** (Kaggle 4c/30 GB, 42 s round-trip; Actions 20/20 shards; sandbox 2c/4 GB — spec's 10 GB assumption corrected) | adopt the 3-tier job protocol |
| 1 call overhead | Safe crossing < 10 ns? | **PASS row 1**: 2.82 ns sandbox / 4.36 ns worker, 0 allocs, race+GC-hammer clean | keep the trampoline; §6 budget ≤ 5 ns |
| 2 Go linking | What will Go link, zero-install? | **PASS 14/14**: Go source + `//line` + asm trampolines; `go build` one command; no-toolchain consumption | Go-source emission primary |
| 3 memory/arena | Handles vs arenas vs copies | **PASS with one pre-registered fallback** (P3: Pinner +55 ns > cgo → copy-small/pin-large); hazards P7/P8 demonstrated (UAF + stack-slot stomp) | owning-side handle tables; raw cross-language pointers forbidden in safe mode; **crash finding retired the shared mmap stack** → guard-checked fast path on the caller's stack + pooled guarded deep stacks |
| 4 scheduling | Do blocking foreign calls starve? | **PASS both tiers**: M1 naive = 169× starvation at 1k, 42×+ capped at 100k (theory-exact), plus the GC-assist wedge (M1 can freeze allocation itself); **two-tier adopted** — M2b 1.00–1.19× M0 on every worker cell at 100 000 tasks; P-release canary-proven (CPU-tick syswin/floor = 1.01); M3 pool at the predicted bound on both tiers (19.62 s vs 19.5 s at 100k), zero lost tickets; thread budgets are environment-specific (sandbox walls ~717; worker pids.max 38508) → derive-by-probe | two-tier blocking design (below) |
| 5 errors | (T, error) ↔ Result, panic contract | **PASS all**: ok path 2.58 ns / 0 allocs; error path exactly 1 alloc; `errors.Is/As` identity survives; panic = SIGABRT at the edge, never unwinds | two-word HyResult + sentinel table + wrap-on-demand |
| 6 ownership usability | Is "no visible lifetimes" real? | **PASS**: 10/10 target programs, **0 annotations / 0 managed / 0 outside-model** under the strictest rule reading; rustc delegation = CI oracle only | Tier-0 model confirmed for the MVP corpus; A1–A8 ambiguities → SPEC-LANGUAGE.md |

## The chosen design (all decisions now in PLAN.md's "in force" list)

1. **Emission:** Go source + Go asm trampolines; `go build` is the only
   build command; zero-install via committed generated source + prebuilt
   Rust artifact (Spike 2).
2. **Crossing:** address-broker cgo package (link-time only, no per-call
   cgo) + NOSPLIT trampolines; fast path on the caller's goroutine stack
   behind a `g.stackguard0` headroom check (offsets DWARF-extracted +
   canary-tested per Go version); deep path on bitmap-pooled 1 MiB guarded
   mmap stacks. 2.42 ns measured, 0 allocs.
3. **Memory:** owning-side handle tables (Go objects → Go table ids; Rust
   objects → generation-tagged refcounted ids released via
   `runtime.AddCleanup` or explicit CAS-guarded Release); borrows are
   copy-below-threshold, pinned-(ptr,len)-view above it; scoped arenas are
   an opt-in optimization. No raw cross-language pointers in safe mode.
4. **Errors:** two-word HyResult (RAX:RDX) + sentinel table + Go-side
   wrap-on-demand; panics abort at the Rust edge (child-process-verified).
5. **Scheduling (Spike 4's addition):** two-tier blocking —
   descriptor-flagged `blocking` callees cross via the
   `entersyscallblock` linkname trampoline (the stdlib's own
   syscall_linux.go pattern), admitted while concurrent-syswin ≤ cap AND
   the bridge's sampler-published thread budget has room; overflow and
   high fan-in route to a bounded blocking pool sized for concurrency
   (128/256 lanes; generation-tagged tickets; park-backoff polling; zero
   runtime internals = the portable fallback). On-stack blocking (M1) is
   forbidden for blocking callees; the lazy `entersyscall` variant (M2a)
   is characterized (it never hands off below ~20 ms) and has no v1 role.
6. **Ownership:** Tier-0 as scoped in research/ownership-models.md —
   Go-side GC + spawn/send sendability checks; Rust-side single-owner +
   moves + function-local borrows checked by a Polonius-style pass over
   Hybrid MIR; own/borrow handles at the boundary; `managed` as the linted
   escape hatch; stock rustc as a CI oracle, never the user-facing checker.

## Targets relaxed (honest ledger)

- **Pinned borrows → copy-small/pin-large** (Spike 3 P3, pre-registered
  fallback): `runtime.Pinner` costs ~55 ns/pair — more than a cgo call.
  Relaxation is per-value-size, not a safety loss.
- **Error source-chain across the boundary** (Spike 5 E4): Go `errors.Is/
  As` identity survives; Rust-side `source()` chains do not (documented
  loss; wrap-on-demand recovers text).
- **Blocking-call dispatch cost** (Spike 4 S2, re-scored): the naked
  enter/exit pair is **~0.9 ms on BOTH tiers** — the sandbox's syscall-
  interception theory was refuted by native Linux; the cost is intrinsic to
  the single-caller handoff shape (P ping-pong through parked Ms + the
  exitsyscall slow path). The ≤100 ns pre-registered threshold FAILS as
  written; the design absorbs the number: the syswin path is reserved for
  descriptor-flagged blocking callees where ~0.9 ms amortizes (every load
  cell prices the design at 1.0–1.2× M0, up to 100 000 tasks). The M3
  pool's park-backoff floor is the same ~0.9 ms — inside the 5 ms blocking
  dispatch budget.
- **M2b lane ceiling at extreme fan-in** (Spike 4 S2, sandbox): (10k, 50%,
  100 ms) runs at 4.9× M0 — a bounded-lane throughput ceiling with full
  drain and a healthy 2.8 ms canary, i.e. queueing, not starvation. On the
  worker the same shape at 100k/50%/10ms lands at 1.18× (more lanes +
  faster arrivals). Judged PASS against the SPEC decision table's actual
  bar ("without starving tasks").

## What was cut

Nothing from the never-cut list. One demotion: M2a (lazy entersyscall) —
characterized, no production role in v1. One scope note carried to Phase 1:
the Tier-0 corpus needs 2–3 adversarial programs (shared mutable map across
tasks; sender-keeps-using after send; borrow-returned-from-function) with
pre-registered expected verdicts before the checker is built — the ten
target programs cannot distinguish the three readings of the sendability
rule (Spike 6's most valuable negative finding).

## Build-vs-extend re-run (SPEC §4, required at this gate)

**OPTION B CONFIRMED — score effectively strengthened.** The provisional
59/65 was scored on Spikes 0–2. Since then every spike landed on B's side:
- Spike 3's handle model works *because* Go's GC stays the owner of Go
  objects (A/C would have to rebuild that story on a foreign heap).
- Spike 4's two-tier design leans on Go's own scheduler semantics —
  `entersyscallblock` is the runtime's contract, and Ms/Ps stay the
  runtime's to manage (a Rust-first runtime would re-implement what B gets
  for free; rustygo's M2 corruption bug is the cautionary tale).
- Spike 6's zero-annotation result depends on Go-heap reads being copies
  (A4) and channels being safe-by-type — Go semantics as the substrate.
- Spike 2's zero-install result (the adoption story) is B-exclusive.

The reversal clause stands unchanged: if a Go release breaks the asm/linkname
assumptions, the documented fallbacks are (a) cgo bridge at §5 row-3 cost,
(b) the M3 pool (no runtime internals) for blocking calls. Both are priced.

## Into Phase 1 (after G0)

1. `SPEC-LANGUAGE.md` — grammar + types + errors + concurrency + the
   Tier-0 rules with A1–A8 resolved (Spike 6's hand-off list).
2. MVP-0 walking skeleton: lexer → parser → AST → emitter for example 01,
   then the boundary generator for example 09 (the adoption story).
3. The checker corpus: the ten `.hy` programs as first positive tests +
   the adversarial three with pre-registered verdicts + cargo-mutants
   negatives (SPEC §14.7).
4. CI: the three-tier protocol already proven (jobs 001–005 + fleet).

Evidence index: spikes/*/RESULTS.md (raw numbers, pre-registrations,
amendment logs), research/*.md (prior art + hazard decisions),
jobs/00*/result (worker-tier summaries), PLAN.md Decision Log (every
non-trivial call with its reversal path).
