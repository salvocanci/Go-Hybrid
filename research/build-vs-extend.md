# Build vs. Extend vs. Start Fresh — the First Decision (SPEC.md §4)

Status: **provisional recommendation (option B)** — written 2026-10-11 after
Spike 0/1/2 evidence + prior-art study; to be re-run at review gate G0 once
Spikes 3–6 land (SPEC §4 allows revision). Score: 5 = best.

## Options

- **A. Extend/fork rustygo** — Go→Rust compiler with a Rust-based Go runtime; fix multi-threading; add a Rust-style type system on top.
- **B. Borgo-style source-to-source** — Hybrid compiles to **Go source**; Rust interop through a generated bridge (address-broker + trampolines, Spike 1; staticlib, Spike 2).
- **C. Hybrid compiles to Rust** with a thin Go-callable C-ABI shim (gives up "no FFI" unless trampolines are added Go-side).
- **D. Dual backend** — emit both Rust and Go-compatible output around a shared ABI layer.

## Scorecard

| criterion (weight) | A rustygo | B →Go source | C →Rust+shim | D dual |
|---|---|---|---|---|
| Risk to MVP (×3) | 2 | **5** | 3 | 1 |
| Time to MVP (×3) | 3 | **5** | 2 | 1 |
| Performance ceiling (×2) | 3 | 3 | **5** | **5** |
| Ecosystem compatibility (×2) | **5** | 4 | 3 | 4 |
| Maintainability (×1) | 2 | **4** | 3 | 2 |
| 2-core/4 GB build cost (×2) | 2 | **5** | 2 | 1 |
| **Weighted total (max 65)** | **34** | **59** | **37** | **27** |

## Evidence per option (this session's data)

### A — extend rustygo
- Pro: MIT, active (v0.0.3, 2026-09-29), 127/141 Go tests, net/http works — the runtime exists.
- Con (decisive): the multi-worker corruption is **unsolved upstream** — GOMAXPROCS=4 → 0/20 runs correct, 18 segfaults (ROADMAP M2). Our 2-core sandbox sits *exactly* in its failure zone. Extending means owning a concurrent Rust GC/scheduler rewrite — the riskiest component class in the whole prior-art graveyard.
- Con: its semantics are **Go semantics** (GC, goroutines) — bolting on ownership checking changes the frontend anyway; we would keep only the runtime, i.e. the riskiest 40%.
- Verdict: borrow ideas (tls.rs state discipline, prepare_park protocol, GC torture tests, differential corpus), don't build on it.

### B — source-to-source (RECOMMENDED)
- Spike 2: **14/14 green** — Go-source emission with `//line` diagnostics (compile errors, panics, gofmt all map to `.hy`), emitted asm accepted, single-command `go build`, zero-install consumption (no Rust/Hybrid toolchain downstream), binary-only distribution correctly ruled out.
- Spike 1: crossings to Rust at **2.82 ns** (safe, stack-switched, race-detector-clean, GC-hammer-clean) vs 46.8 ns cgo — the "no hand-run FFI" goal is satisfiable while Go remains the codegen + runtime.
- Prior art: Borgo proved the language design works (ADTs, `?`, Option/Result over the whole Go stdlib) and died of *community* causes (no license, no releases, bus factor 1) — not technical ones; we counter those on day one (dual license, CI, releases, AGENTS.md discipline).
- Ecosystem: full Go stdlib via a `go/ast`-based importer (reimplement; Borgo is unlicensed — reference-only); Rust crates via the bridge.
- Honest costs: Go codegen ceiling (GC pauses, no layout control); cross-GO-version drift (mitigate: pin 1.26.9, target the stable subset, CI matrix); "within 5% of native Go throughput" should be *achievable by construction* (we emit Go) — the risk moves to the Rust-crossing hot paths, which Spike 1 already prices at ~10× a Go call.
- Safety model: Hybrid code is GC-safe by construction + ownership-checked at the front end (Spike 6 to validate the model); Rust side is Rust; boundary = handles/arenas (Spike 3). Mission fit: "Rust-grade memory safety **incrementally**, without a rewrite" — B is the only option whose adoption story is literally "drop .hy files into your Go module" (verified in Spike 2 E5).

### C — compile to Rust + shim
- Highest performance ceiling and the cleanest ownership story, but: Go callers reach Hybrid through cgo-class crossings unless they adopt the trampoline machinery per-package; Go's GC cannot see the Rust heap → handle-heavy ergonomics; and every Hybrid package pays 2-core rustc builds. The adoption story inverts (Rust-first), which contradicts the mission's Go-team-first framing.

### D — dual backend
- The WIT research shows a shared IDL layer is viable — but two backends double the differential-test matrix and miscompile-triage surface on a 2-core/4 GB box. Nothing in Spikes 0–2 *requires* D. Revisit only if B hits a hard wall (e.g. a language feature Go cannot express).

## The compiler itself

- **Implementation language: Rust** (SPEC §4 default; Kani verification path; shares the target ecosystem).
- **Architecture:** staged pipeline — lexer → parser → AST → name resolution → type check → ownership check (HIR) → Go-source emitter (+ bridge/trampoline emitter for Rust interop). Every stage dumpable and deterministic (`--emit=ast|hir|go|bridge`).
- **Reuse before build:** hand-written lexer/parser (Borgo-style zero-parse-deps is proven at our scale); `golang.org/x/tools/go/packages` for the Go-importer (per SPEC §14.5); `rustdoc --output-format json` or `cargo public-api` for Rust-side API extraction; evaluate `wit-parser` (MIT/Apache-2.0+LLVM-exc) for the boundary IDL; `cbindgen`/`uniffi`/`diplomat`/`rust2go` evaluated before writing our own binding generator.
- **Sandbox budget:** small crates, `cargo check` loop in-sandbox, full builds on the Actions fleet / Kaggle worker (verified end-to-end in Spike 0: 4-core/30 GB worker, ~50 s round-trip; 20-shard fleet measured in Spike 0 part B).

## Reversal

If Spike 3 (arena/GC) or Spike 6 (ownership usability) shows the Go-source path
cannot carry the safety model, revisit C-with-trampolines at G0 — the Spike 1/2
artifacts (address-broker, trampolines, staticlib linking) are route-agnostic
and survive the pivot.
