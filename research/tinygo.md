# TinyGo — research note (Task 4-c)

## Identity / project matrix

| repo | role | license | activity (2026-10-11) | status |
|---|---|---|---|---|
| [tinygo-org/tinygo](https://github.com/tinygo-org/tinygo) | Alternative Go compiler on LLVM; runtime/GC/scheduler for "small places" | BSD-3-Clause (portions of Go stdlib under Go's BSD-3; portions of LLVM under Apache-2.0 w/ LLVM exception — see repo `LICENSE`) | 17,809 stars; pushed 2026-10-09; 555 open issues; default branch `dev` | Active, healthy, not archived. Repo size ≈ 14 MB (API) / 18 MB shallow clone |

Related but not cloned (too big, not needed): `bytecodealliance/wasmtime` (165 MB) — see `wit-abi.md`.

## What it actually is (verified)

TinyGo is a **from-scratch Go compiler** (not a fork of `gc`) that reuses the
official Go toolchain *libraries* — `go/types` and `golang.org/x/tools/go/ssa`
— as its front end, and uses **LLVM** as its back end via the
`tinygo.org/x/go-llvm` bindings (`go.mod`). README: "It reuses libraries used
by the Go language tools alongside LLVM to provide an alternative way to
compile programs written in the Go programming language." It targets
microcontrollers, WASM/WASI (both core WASM and the component model /
wasip2), and hosted CLI tools (there are `src/runtime/os_linux.go`,
`os_darwin.c`, `os_windows.go`, plus `runtime_unix.c`). It keeps the Go
memory model — README: "we want to keep the Go memory model (which implies
garbage collection of some sort)" — which is why it ships a *menu* of garbage
collectors rather than borrowing Go's.

Version coupling facts: `go.mod` declares `go 1.25.0` (so it tracks a recent
Go language release with a lag); `cgo/libclang_config_llvm15.go` …
`libclang_config_llvm22.go` exist, i.e. **LLVM 15–22 is supported**; the exact
LLVM commit TinyGo builds against is pinned in `llvm-version.txt` (a raw
commit hash), and `BUILDING.md` says "LLVM, Clang and LLD are quite light on
dependencies" but "building LLVM … can take over an hour" on a fast machine.

## Architecture / design (with file-path evidence)

**Compiler pipeline** (verified in `builder/build.go` and `compiler/`):

1. **Load & typecheck**: `loader/` wraps `go/types` + SSA build via
   `golang.org/x/tools/go/ssa` (imports in `compiler/compiler.go`).
2. **SSA → LLVM IR per package**: `compiler.CompilePackage(...)`
   (`builder/build.go:445`) walks Go SSA and emits one LLVM module per package
   (`compiler/compiler.go`, `compiler/func.go`, `compiler/interface.go`).
3. **Partial evaluation of package init**: `interp/` runs `runtime.initAll`
   at *compile time* with a rollback-per-function memory model
   (`interp/README.md`: "it just tries to execute everything and if it hits
   something it cannot interpret … it rolls back the execution of that
   function"). This is a compile-time evaluator worth studying for Hybrid's
   constant/boundary checks.
4. **LLVM transform passes**: `transform/` — `interface-lowering.go`,
   `allocs.go`, `gc.go` (stack-object insertion), `stacksize.go`,
   `rtcalls.go`, `unwind.go`, then `transform.Optimize(...)`
   (`builder/build.go:1348`).
5. **C/CGo**: its *own* cgo implemented with **libclang**
   (`cgo/libclang.go`, `cgo/cgo.go`) — "Good CGo support, with no more
   overhead than a regular function call" (README). Note: a precedent for
   parsing C headers and emitting bindings *without* the gc toolchain.
6. **Link**: lld + LTO, driven by `builder/`.

**GC menu** — `compileopts/options.go:13`:
`validGCOptions = ["none", "leaking", "conservative", "custom", "precise", "boehm"]`,
implemented in `src/runtime/gc_{none,leaking,conservative,custom,precise,boehm}.go`
(+ `gc_boehm.c`, `gc_blocks.go`, `gc_globals_*.go`). Defaults:
`Config.GC()` falls back to **"conservative"**
(`compileopts/config.go:155-163`); the `wasip1` wasm target defaults to
**"precise"** (`targets/wasip1.json:11`). Highlights:

- `gc_none.go` — no allocation at all; allocations become linker errors.
- `gc_leaking.go` — allocate-only (arena) allocator.
- `gc_conservative.go` — block-based heap, every word treated as a potential
  pointer; layout info passed to `alloc` is *discarded*.
- `gc_precise.go` — pointer layout stored as a bitstring in the first word of
  each object (format `pppp…sss1`, documented in a long comment); precise for
  most heap objects.
- `gc_boehm.go/.c` — the Boehm–Demers–Weiser conservative GC linked in via C,
  with all GC calls serialized behind locks.

**Scheduler menu** — `compileopts/options_test.go:13` lists valid values
`none, tasks, asyncify, threads, cores` (files
`src/runtime/scheduler_{none,tasks,threads,cores}.go`,
`scheduler_cooperative.go`). Verified semantics:

- `scheduler.tasks` = **cooperative round-robin FIFO runqueue + sleep queue,
  no parallelism** — `scheduler_cooperative.go`: "a very simple cooperative
  round robin scheduler… While the cooperative scheduler has concurrency, it
  does not have parallelism." Goroutine stacks are switched by **hand-written
  per-arch assembly** (`src/internal/task/task_stack_amd64.S` +
  `task_stack_amd64.go` with an exact `calleeSavedRegs` layout struct).
- `scheduler.threads` (`scheduler_threads.go`): OS threads,
  `hasParallelism = true`, `hasScheduler = false`.
- `scheduler.none`: no goroutines at all.
- Panic strategies `print`/`trap`; unwind via `none`, `return`
  (`panic_unwind_return.go`), `setjmp` (`panic_unwind_setjmp.go`),
  `asyncify` (`panic_unwind_asyncify.go`).

**Target descriptors**: `targets/*.json` (hundreds of them) form a tiny
inheritance-based config schema — e.g. `targets/microbit.json` is
`{"inherits": ["nrf51"], "build-tags": [...], "flash-method": "msd", …}` and
can set `scheduler`, `gc`, `panic-strategy`, build tags, linker scripts.

**Boundary precedent — `//go:wasmexport` / `//go:wasmimport`**: the compiler
itself understands these pragmas (`compiler/symbol.go:30-31`:
`wasmExport`, `wasmExportPos` fields; `compiler/goroutine.go:145+`:
`createWasmExport()` generates an exported *wrapper* that "needs to start a
new goroutine each time the exported function is called"). TinyGo's WASI
Preview 2 support is itself **generated from WIT** —
`src/internal/wasi/random/v0.2.0/random/random.wasm.go` (fetched from `dev`)
begins: `// Code generated by wit-bindgen-go. DO NOT EDIT.` and contains
`//go:wasmimport wasi:random/random@0.2.0 get-random-bytes`.

## The claims check

| claim (SPEC.md:189) | verdict | evidence |
|---|---|---|
| "TinyGo: alternative Go compiler (LLVM)" | **CONFIRMED** | README ("reuses libraries used by the Go language tools alongside LLVM"); `go.mod` dep `tinygo.org/x/go-llvm`; `BUILDING.md` LLVM build flow; pinned commit in `llvm-version.txt`. |
| "…whether it could serve as the Go-side backend" | **CONFIRMED as an invocable toolchain / CORRECTED as an embeddable component** | It emits native objects for linux/darwin/windows and wasm, has its own cgo (libclang) and `wasmimport/export` pragmas — so Hybrid *could* drive `tinygo build` as a black box. But it is not designed as a library: no stable Go API surface for embedding, it pins one exact LLVM commit, and it tracks Go releases with a lag (`go 1.25.0` in `go.mod` vs Go 1.26 installed in our env). |
| "…its runtime and GC choices" | **CONFIRMED and expanded** | Six GC strategies (`compileopts/options.go:13`), five scheduler modes, four panic/unwind strategies — see Architecture above. This was understated in the spec: the runtime is a *configurable matrix*, selected per target JSON. |

**Cost of driving LLVM on our 2-core / 4 GB build box (key question):**

- **Building LLVM from source: not viable here.** `BUILDING.md` says the
  build "can take over an hour" on a good machine; on 2 cores expect several
  hours, and linking LLVM alone can transiently need multiple GB RAM — risky
  with 4 GB and no swap (`free -h`: 0 B swap). Disk is fine (8.3 GB free) but
  time/RAM are not.
- **Viable paths that avoid compiling LLVM**: (1) consume a **prebuilt
   TinyGo release tarball**, which statically links LLVM/libclang/lld — zero
   LLVM build cost, one ~100–300 MB download; (2) build TinyGo against
   Debian 13's `llvm-19-dev` + `libclang-19-dev` (LLVM 19 is inside
   TinyGo's supported 15–22 range; only `libllvm19` runtime is present on
   the box today, so the `-dev` packages would need installing); (3) don't
   use LLVM at all on the Go side — use stock `gc` + cgo (what the lead
   agent already pinned: go1.26.9).
- **Running TinyGo (not building it)** on 4 GB is fine for small/medium
  programs: per-package modules keep peak RSS modest, but whole-program LTO
  linking of large dependency graphs is the memory hotspot. Hybrid's Go side
  is expected to be small, so this is acceptable.

## What Hybrid should extract (concrete techniques)

1. **Target-descriptor schema with inheritance** (`targets/*.json` +
   `compileopts/target.go`): a tiny JSON with `inherits`, build tags, GC /
   scheduler / panic-strategy knobs. Hybrid's per-target boundary config
   (Go-side calling convention, panic policy, handle-table flavor) should be
   exactly this shape.
2. **Directive-driven boundary**: `//go:wasmexport` / `//go:wasmimport` prove
   that a *compiler-reserved pragma family* is enough to define exports,
   imports, and wrapper generation (including "start a goroutine per foreign
   call" semantics, `compiler/goroutine.go:145+`). Hybrid's
   `hybrid:export` / `hybrid:import` pragmas follow this precedent — and can
   be *simulated today* in stock Go with `//go:cgo_import_static` /
   `//go:export`-style linkname tricks before Hybrid owns a compiler.
3. **A GC menu as an incremental-safety ladder**: `none → leaking →
   conservative → precise` maps surprisingly well onto Hybrid's "adopt
   Rust-grade safety incrementally" pitch — a Go-side module can start
   conservative and move to precise once boundary layouts are known
   (`gc_precise.go`'s per-object pointer-bitstring is directly borrowable
   as a design).
4. **Partial evaluator with rollback** (`interp/README.md`): evaluate what
   you can at compile time, roll back on anything opaque, run at runtime
   instead. Hybrid can use the same trick to constant-fold boundary layout
   decisions and validate descriptors at build time without a full VM.
5. **libclang-based header ingestion** (`cgo/libclang.go`): TinyGo parses C
   headers directly without the gc cgo tool — evidence that Hybrid's Rust
   side can be fed by parsed `rustdoc`/`rmeta`-like descriptors rather than
   by invoking cargo repeatedly.
6. **Don't write a Go parser**: TinyGo (a small team, ~18 MB of source)
   implements a whole Go compiler front end by *reusing* `go/types` +
   x/tools SSA. Hybrid's Go-side tooling should lean on the same libraries.

## Failure modes / lessons

- **Cooperative scheduler + foreign calls**: with `scheduler.tasks`, any
  long-running or blocking call into Rust *stalls every goroutine* (no
  preemption). TinyGo itself works around this in `createWasmExport()` by
  spawning a fresh goroutine per foreign entry. Hybrid's boundary must
  either hand foreign calls to a thread pool or document the stall.
- **Conservative GC retention across the boundary**: the default
  `conservative` GC treats every word as a pointer, so Go→Rust shared
  buffers referenced from a scanned stack can be retained (and, worse, a
  stale interior word can *pin* memory). Hybrid should require `precise`
  stack maps (or explicit root registration) for modules that share memory
  with Rust.
- **LLVM version churn tax**: supporting LLVM 15–22 simultaneously
  (`cgo/libclang_config_llvm*.go`) plus pinning one exact commit
  (`llvm-version.txt`) is a standing maintenance cost. If Hybrid ever
  embeds LLVM it inherits this tax; if it only *consumes* TinyGo releases
  it does not.
- **Per-arch stack-switching assembly** (`src/internal/task/task_stack_*.S`,
  ~15 architectures) is the single most expensive part of their runtime to
  maintain — a reason for Hybrid to avoid custom coroutines and bridge
  stacks the way cgo does.
- **Language lag**: TinyGo tracks Go with a delay; code depending on
  bleeding-edge stdlib may not compile. Hybrid must pin a TinyGo release and
  document the supported Go subset.

## Licensing (compat with dual MIT/Apache-2.0)

TinyGo is **BSD-3-Clause** (© The TinyGo Authors), with embedded portions of
the Go standard library (BSD-3-Clause, © Go Authors) and portions of LLVM
(Apache-2.0 with LLVM exception), all clearly marked in the repo `LICENSE`.
BSD-3-Clause is permissive and fully compatible with a dual MIT/Apache-2.0
project: we may depend on, vendor, and even patch TinyGo, as long as
copyright notices are retained. No copyleft contamination risk.

## Verdict for Go-Hybrid

TinyGo is a stronger *design library* than a *backend*. It convincingly
answers the spec's question "could it serve as the Go-side backend?" with
"yes, as an external toolchain we invoke" — it has native targets, its own
cgo, and wasm import/export pragmas that anticipate exactly the boundary
Hybrid needs — but embedding it as a library or patching its compiler would
drag in LLVM-version pinning and a Go-language-version lag that a 2-core /
4 GB build box and a small team cannot afford. **Recommendation**: keep the
pinned stock Go toolchain (go1.26.9 + cgo) as Hybrid's primary Go-side
backend; keep TinyGo as (a) the WASM path if/when Hybrid targets
components (its `wasmimport/wasmexport` + wit-bindgen-go integration is the
fastest route), (b) a studied reference for our target-descriptor JSON, GC
ladder, and compile-time partial evaluator, and (c) a fallback if cgo
overhead or runtime flexibility becomes a blocker. Never build LLVM
ourselves on this box; if TinyGo is needed, consume official release
tarballs with pre-linked LLVM.

