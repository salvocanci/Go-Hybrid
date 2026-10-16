# Spike 2: What can Hybrid emit that Go will link?

**Status:** thresholds pre-registered 2026-10-11 BEFORE any run (SPEC §14.7).
**Code:** `work/` (throwaway). **Question (SPEC §5 Spike 2):** which emission +
linking routes work with `go build` as a SINGLE command, and what does each
require on a downstream machine?

## Routes under test

| # | Go-side emission | Rust-side route |
|---|------------------|-----------------|
| R1 | Go source (+ `//line` mapping back to `.hy`) | — (pure Go, no Rust) |
| R2 | Go source + Go assembly trampolines (`.s`) | — |
| R3 | Object/archive-only (no source) | — (binary-only packages) |
| R4 | Go source (from R1) | Rust `staticlib` linked via cgo LDFLAGS |
| R5 | Go source (from R1) | asm-called Rust fns via the spike-1 address-broker |

## Pre-registered thresholds

| id | expectation (registered before running) | decision if confirmed |
|----|------------------------------------------|----------------------|
| E1 | R1: single `go build` works; compile errors AND runtime panics in generated code point at `.hy` files via `//line` | adopt Go-source emission as primary |
| E2 | R2: `go build` accepts emitted `.s` next to emitted `.go` (spike 1 already evidences) | adopt for trampolines |
| E3 | R3: **FAIL** — binary-only packages were removed (Go 1.13); `go build` demands source (or module cache archives it built itself) | rule out source-less distribution; emit source |
| E4 | R4: single `go build` links the Rust staticlib; requires a C toolchain (cgo) on the machine | adopt as default Rust route |
| E5 | zero-install: downstream module builds with committed generated `.go` + prebuilt `.a`, NO Rust toolchain, gcc present, CGO on | adoption story: commit artifacts |
| E6 | CGO_ENABLED=0: **FAIL** for any Rust-calling package (cgo preamble carries LDFLAGS) | document: pure-Go packages OK without Rust; Rust-calling packages need cgo |
| E7 | cross-compile GOARCH=arm64 on amd64 host: **FAIL** without a cross C toolchain (cgo limitation) | document; Hybrid pins per-target prebuilt artifacts |
| E8 | `go vet` / `gofmt` behave sanely on emitted code | quality gate for the emitter |

## Method

`work/emit.py` — a mini "compiler" (template emitter, NOT a real front end) that
turns `sample.hy` into `emitted/hello.hy.go` with `//line` directives; `work/run.sh`
drives all tests; every check prints PASS/FAIL with evidence captured into this
file. Zero-install test uses `work/zeroinstall/` (a separate downstream Go module
importing the emitted package by `replace` directive). Clean-machine caveat: the
sandbox HAS gcc — "clean machine without C toolchain" cannot be simulated; E6
(CGO_ENABLED=0) is the proxy. Recorded as a limitation.

## Results

All 14 checks PASS on the sandbox (go1.26.9, gcc 14.2, linux/amd64), 2026-10-11:

| id | result | evidence |
|----|--------|----------|
| E1a | **PASS** | single `go build` of emitted source with `//line` directives |
| E1b | **PASS** | runs; output "hello, spike2 (from Hybrid)" |
| E1c | **PASS** | `panic("boom from Hybrid source")` stack shows `work/sample.hy:15` |
| E1d | **PASS** | injected syntax error reported at `sample.hy:10` (mapped) |
| E2 | **PASS** | emitted `trampoline_amd64.s` compiled+linked by `go build`; `asmDouble(21)=42` |
| E3 | **PASS** | `//go:binary-only-package` → "binary-only packages are no longer supported" |
| E4 | **PASS** | one `go build` links the Rust staticlib; output `hybrid_add(40,2)=42` |
| E5 | **PASS** | downstream module builds+runs with committed generated `.go` + prebuilt `.a`, PATH stripped of cargo/rustc (verified empty), gcc present, CGO on |
| E6 | **PASS** | CGO_ENABLED=0 → "build constraints exclude all Go files" (cgo file excluded → import fails), as registered |
| E6b | **PASS** | pure-Go emitted package cross-builds CGO=0 GOARCH=arm64 |
| E6c | **PASS (finding)** | asm-bearing package on foreign arch → "missing function body" for the amd64-only decl; emitter must gate per-arch asm + Go decls with build tags |
| E7 | **PASS** | cgo cross-compile GOARCH=arm64 blocked without a cross C toolchain |
| E8a | **PASS** | `gofmt -l` clean on emitted code (after adding the `//` separator after the DO-NOT-EDIT line) |
| E8b | **PASS** | `go vet` clean |

Bonus evidence: `gofmt` parse errors on generated code ALSO report at the
`//line`-mapped `.hy` position — the mapping covers compiler, linker-by-proxy,
runtime traces, and gofmt.

## Zero-install consumption trade-offs (verified)

| story | works? | requires on the consumer machine |
|-------|--------|----------------------------------|
| Pure-Go Hybrid package (no Rust calls) | YES — even CGO_ENABLED=0 and cross-arch | nothing beyond Go itself |
| Hybrid package calling Rust (committed generated `.go` + prebuilt `.a`) | YES (E5) | a C toolchain + cgo on (default on major platforms); NO Rust toolchain, NO Hybrid toolchain |
| Hybrid package calling Rust, consumer sets CGO_ENABLED=0 | NO (E6) | — (documented: same constraint as any cgo dependency) |
| Cross-compiling a Rust-calling package | NO without a cross C toolchain (E7) | per-target prebuilt artifacts + cross linker (same as cgo ecosystem) |
| Source-less binary distribution | NO (E3, binary-only packages removed) | — |

Conclusion for the adoption story (SPEC §5 Spike 2 question): commit generated Go
source + prebuilt per-target Rust archives; consumers need only Go (+ a C
toolchain for Rust-calling packages, which cgo users already have). The Hybrid
toolchain is required only to COMPILE `.hy` sources, not to consume them.

## Verdict

**Adopt, in this order (SPEC §5 preference order confirmed):**
1. **Go source emission is the primary back end** — most robust across Go versions, zero-install for pure-Go packages, full `//line` diagnostic mapping, gofmt/vet-clean.
2. **Go assembly emission for trampolines** — works, with the requirement that per-arch asm files carry per-arch build-tag gating of their Go decls (E6c finding).
3. Object-file emission for a pinned Go version: **not viable for distribution** (E3); only relevant if source emission hits a wall later — none seen.
4. **Rust side: staticlib linked by the cgo LDFLAGS preamble of a generated bridge package** (E4/E5), optionally with the spike-1 address-broker + asm trampolines for sub-10ns crossings (spike 1).

Consequences for the build-vs-extend decision: a Borgo-style source-to-source
design (option B) has all its linking questions answered affirmatively; the
"no FFI" goal is satisfiable at ~2.8ns/call via the trampoline route.
