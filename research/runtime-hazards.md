# Runtime interaction hazards — test-or-decision record (Task 5-a)

Every SPEC.md §12 "Runtime interaction hazards checklist" item gets a hazard,
cited evidence (fetched live 2026-10-11; Go sources at tag `go1.26.9`,
doc.rust-lang.org served `std 1.99.0` — matching our pins), and a decision:
a **DESIGN RULE** or a **TEST TO WRITE** (spec for Spike 3/4/5 or CI). Feeds
Spike 3 (handles + `runtime.Pinner` + arenas, in progress) and
`interfaces/abi-types.md`. Cross-refs: research/rustygo.md, research/rust2go.md,
research/wit-abi.md, research/rustgo.md, research/tinygo.md, PLAN.md Design
Decisions in Force (asm trampoline + mmap'd guarded stack + address-broker;
2.82 ns measured).

## Summary decision table

| # | Item | Rule / test | Confidence | Lands in |
|---|------|-------------|-----------|----------|
| 1 | Allocators | RULE: side-owned free via generated typed-drop thunks; arena/handle only; leak-counter tests | High | interfaces/abi-types.md + Spike 3 tests |
| 2 | Signals | RULE: Go owns handlers; guest never installs; SIGURG reserved; 4 characterization tests | High | abi-types.md + Spike 3/4 tests |
| 3 | Threads/TLS | RULE: bridge state Send+Sync; !Send only under generated LockOSThread wrapper; migration-hammer + negative-compile tests | High | Spike 3/4 tests + emitter rule |
| 4 | Foreign pools | RULE: Hybrid owns thread budget (GOMAXPROCS-derived); no ctor-time spawns; oversubscription test | High | abi-types.md + Spike 4 test |
| 5 | Stacks | RULE: Rust runs only on mmap'd guarded stack (Spike 1 M4); dies-on-guard + small-Go-stack tests | High | Spike 3 test + ABI doc |
| 6 | Linking | RULE: ONE staticlib per binary; panic=abort; external link; two-staticlib negative + panic-contract tests | High | abi-types.md + CI |
| 7 | Process state | RULE: no fork primitive; env via os only; Rust init only from Go init(); fork/env/ctor-order tests | Medium (ctor order UNVERIFIED) | stdlib rules + Spike 3/5 tests |
| 8 | cgo pointer rules | RULE: never require cgocheck=0/invalidptr=0; null-not-dangling; generator-enforced pinning; cgocheck2 CI leg | High | CI + emitter lint test |
| 9 | Finalizers/handles | RULE: AddCleanup-based, idempotent, concurrent-safe release; release-storm + GC-torture tests | High | Spike 3 tests |
| A | ABI stability | RULE: C-layout descriptors, versioned, runtime handshake; stale-descriptor test | High | interfaces/abi-types.md |
| B | Toolchain upgrades | RULE: pinned + full-suite canary on bump; next-Go CI leg non-blocking | High | gates/G0.md + CI |
| C | Platform matrix | RULE: Linux amd64 MVP, arm64 second; per-target prebuilt artifacts | High | PLAN.md (already) |
| D | Debugging | RULE: keep DWARF (never -w); //line (done); SetCgoTraceback is cgo-path-only; gdb-across-frames test deferred | Medium | Phase 5 + spike test |
| E | Link mode for trampoline | RULE: address-broker (no cgo_import_static) + external linking; C linker required — documented | High | abi-types.md (already evidenced) |

---

## 1. Allocators

**Hazard.** Two allocators coexist (Go `mallocgc`+GC; Rust's). A cross-side
free corrupts the other runtime's heap metadata — no error, just corruption.
Worse: Go's GC and *stack copier* scan pointer-typed slots, so a Rust heap
pointer stored in Go-visible memory is neither a valid Go pointer (invalidptr
crash) nor traceable (dangling borrow).

**Evidence.** go.dev/cmd/cgo ("Passing pointers"): *"Whether a pointer is a Go
pointer or a C pointer is a dynamic property determined by how the memory was
allocated; it has nothing to do with the type of the pointer."* Pinning: *"Go
pointers passed as function arguments to C functions have the memory they
point to implicitly pinned for the duration of the call"*; pkg.go.dev/runtime
(Pinner): *"it allows C memory to safely retain that Go pointer even after
the cgo call returns, provided the object remains pinned."* `runtime/cgo.Handle`:
*"provides a way to pass values that contain Go pointers… between Go and C
without breaking the cgo pointer passing rules."* rust2go's typed
`c_{Trait}_{fn}_drop` entries exist because a `dyn Any` round-trip loses the
vtable (research/rust2go.md).

**Decision — DESIGN RULES.** (1) Memory is freed by the side that allocated
it, always via a *generated, typed* drop thunk (rust2go pattern) or an arena
scope — never raw free across the boundary. (2) Cross-boundary identity is an
index into a handle table (WIT own/borrow), not a pointer; the generator pins
Go memory for borrow duration automatically.
**TESTS (Spike 3):** (a) leak test — Rust test build with `#[global_allocator]`
byte counter; release N handles (explicit Close + cleanup path); after
`runtime.GC()` + drain the counter returns to baseline. (b) GC-torture leg
(collect every allocation, rustygo pattern): no crash, no double-free.
(c) Arena scope exits in Go → all Rust bytes freed; ASAN use-after-free probe
stays clean.

## 2. Signals

**Hazard.** The Go runtime installs handlers for most of the signal table on
Go threads, uses **SIGURG for async preemption**, special-cases **SIGPIPE**
by fd number, and turns **SIGSEGV/SIGBUS/SIGFPE** into Go panics. A Rust
crate calling `sigaction` (crash handlers, alt signal stacks) breaks the Go
scheduler/panic machinery; conversely Rust's stack-overflow detection *needs*
its SIGSEGV to hit a guard page.

**Evidence.** runtime/signal_unix.go (go1.26.9): *"sigPreempt is the signal
used for non-cooperative preemption… We use SIGURG because it meets all of
these criteria"* — `const sigPreempt = _SIGURG`. os/signal doc.go: *"A write
to a broken pipe on file descriptors 1 or 2… will cause the program to exit
with a SIGPIPE signal. A write to a broken pipe on some other file descriptor
will take no action… and the write will fail with a syscall.EPIPE error."*
Non-Go code rules (same doc): *"must use the SA_ONSTACK flag with
sigaction"*; *"If the non-Go code installs a signal handler for any of the
synchronous signals (SIGBUS, SIGFPE, SIGSEGV), then it should record the
existing Go signal handler… Otherwise some Go run-time panics will not occur
as expected"*; also no signal-mask changes on Go-created threads. Preemption
inside Rust: `doSigPreempt` acts only when `isAsyncSafePoint` holds, which
needs `findfunc(pc)` to resolve the PC (runtime/preempt.go) — a Rust PC is
not preempted; long Rust calls block async preemption of that goroutine
(Spike 1 caveat; Spike 4 owns the scheduler answer).

**Decision — DESIGN RULES.** (1) The Go runtime owns all handlers; guest Rust
crates MUST NOT install handlers or alter masks — hard trust-boundary
constraint (SPEC §12 security row); later escape hatch: a brokered
`hybrid/signals` package following the doc.go rules. (2) Generated Go code
never `Notify`s SIGURG. (3) The mmap'd guarded stack (Spike 1 M4) is what
makes Rust's guard-page expectation work.
**TESTS:** T1 SIGPIPE — inside a Rust call on the guarded stack, write to a
closed pipe: fd 3 → `EPIPE`, process alive; fd 1 → death by SIGPIPE
(Go-compatible CLI semantics). T2 SIGSEGV — Rust null-deref on the guarded
stack: characterize the contract (expected: Go runtime prints a signal
traceback and exits; a foreign PC is not convertible to a Go panic). T3 —
tight Rust loop × forced GC + default GODEBUG → no crash; preemption lands
only after return. T4 — repeat T1–T3 under `GODEBUG=asyncpreemptoff=1` to
bisect preemption interaction.

## 3. Threads and thread-local state

**Hazard.** Goroutines migrate between Ms; Rust `thread_local!` state,
`!Send` types and locks held across a call are only safe if the goroutine is
pinned for the whole call. A thread-local read in bridge code silently
returns another thread's value after migration.

**Evidence.** pkg.go.dev/runtime `LockOSThread`: *"LockOSThread wires the
calling goroutine to its current operating system thread… A goroutine should
call LockOSThread before calling OS services or non-Go library functions that
depend on per-thread state."* Rust std::thread (TLS): *"A thread-local key
owns the value it contains and will destroy the value when the thread
exits."* `Send`: *"An example of a non-Send type is the reference-counting
pointer Rc… they might try to update the reference count at the same time,
which is undefined behavior."* rustygo's rt_global!/rt_shared! file exists
because of exactly this class (package vars accidentally `thread_local!` —
research/rustygo.md).

**Decision — DESIGN RULES.** (1) Everything the bridge generator emits/links
must be `Send + Sync` (or lock-guarded): the bridge API is migration-safe by
construction; `thread_local!` in bridge code is linted out. (2) User-facing
`!Send` foreign types get a compiler-generated `LockOSThread` wrapper
(GLFW/Android pattern); sharing such a handle to another goroutine is a
*compile error* (handle entry is `!Sync` on the Rust side, so rustc enforces
it — borrow the check, don't rebuild it).
**TESTS:** T1 migration hammer — GOMAXPROCS=2…8, 100 goroutines × stateful
Rust entry; results scheduling-independent (`-race -cpu=1,2,8`). T2
negative-compile: pass a `!Send` handle to another goroutine → compile error
with a named message. T3 — locked-goroutine use of a `!Send` object while
others migrate → PASS; same object shared unlocked → rejected.

## 4. Foreign runtimes and thread pools

**Hazard.** rayon/Tokio default to one worker thread **per CPU core** on top
of Go's GOMAXPROCS threads → ~2× oversubscription on few cores; startup and
shutdown ownership is undefined (pools leak, or die mid-flight at exit).

**Evidence.** docs.rs/tokio (runtime): *"The multi-thread scheduler executes
futures on a thread pool, using a work-stealing strategy. By default, it will
start a worker thread for each CPU core available on the system."*
docs.rs/rayon (ThreadPoolBuilder): *"the Rayon runtime will select the number
of threads automatically. At present, this is based on the RAYON_NUM_THREADS
environment variable (if set), or the number of logical CPUs (otherwise)"*.
pkg.go.dev/runtime: GOMAXPROCS *auto-updates* — *"The Go runtime periodically
updates the default value based on changes to the total logical CPU count,
the CPU affinity mask, or cgroup quota"* — so a one-shot startup read is
stale-prone. rustygo's matrix (0/20 correct at GOMAXPROCS=4) is the
cautionary tale (research/rustygo.md).

**Decision — DESIGN RULES.** (1) Hybrid owns the process thread budget:
generated main computes `budget := runtime.GOMAXPROCS(0)` at bridge init and
passes it explicitly (rayon `num_threads`, Tokio `worker_threads`); the
generator unsets/overrides `RAYON_NUM_THREADS`. (2) Foreign pools start only
via explicit Hybrid API (first use), never at import/ctor time (item 7);
shutdown via `hybrid.Shutdown()` (pool Drop). At exit Go's runtime owns the
process — detached foreign threads die without Rust destructors (std::thread:
*"When the main thread of a Rust program terminates, the entire program shuts
down, even if other threads are still running"*), documented like finalizers:
best-effort only.
**TEST (Spike 4):** on the 2-core sandbox, GOMAXPROCS=2 + rayon
`num_threads(2)` + concurrent CPU-bound Go and Rust work → CPU-time/wall-time
≤ 2.1. Negative control (recorded, not CI): rayon defaults → ratio ≈ 2×.

## 5. Stacks

**Hazard.** Go stacks start at 2 KiB and grow by *copying* (`morestack`);
Rust assumes a multi-MiB fixed stack with a guard page. Rust on a goroutine
stack ⇒ deep recursion or a big local array silently smashes the Go stack; a
Go stack *copy* under Rust frames would invalidate raw stack addresses.

**Evidence.** runtime/stack.go (go1.26.9): `stackMin = 2048`; `newstack`:
*"Called from runtime·morestack when more stack is needed. Allocate larger
stack and relocate to new stack. Stack growth is multiplicative."* Rust
std::thread: *"The default stack size is platform-dependent and subject to
change. Currently, it is 2 MiB on all Tier-1 platforms"*; *"the stack size of
the main thread is not determined by Rust."* Guard pages (POSIX
`pthread_attr_setguardsize`): *"the implementation allocates extra memory at
the overflow end of the stack as a buffer against stack overflow… If an
application overflows into this buffer an error shall result (possibly in a
SIGSEGV signal being delivered to the thread)."* Cross-refs: rustgo's
arbitrary-16KiB-frame confession; rustygo's *"Rust frames hold raw addresses
into the stack, so Go-style stack copying is not available"*.

**Decision — DESIGN RULES.** (1) In force (Spike 1): all guest Rust executes
on a per-M mmap'd, guard-paged stack (1 MiB default) switched by the NOSPLIT
trampoline; running Rust on the goroutine stack (rustgo-style M3) is
rejected — measured-but-unsafe. (2) Trampolines are NOSPLIT (never trigger
`morestack`); guarded-stack size is a descriptor field.
**TESTS:** T1 — default 2 KiB-stack goroutine calls a Rust fn using ~700 KB
of locals → succeeds (the switch, not the Go stack, is used). T2 —
recursion-depth sweep: exceed max depth for 1 MiB → process dies *on the
guard page* (clean abort, PC in guard range), never silent corruption. T3 —
keep Spike 1 regressions (20k-deep recursion, GC hammer) as permanent CI.

## 6. Linking

**Hazard.** (a) Each Rust staticlib bundles std + all deps and *"exports all
public symbols of them"* — two staticlibs in one Go binary ⇒ duplicate std
symbols, two unwinder/personality instances. (b) `panic=unwind` across the
C-ABI boundary is UB. (c) The address-broker design implies external link
mode ⇒ a C toolchain at build time.

**Evidence.** Rust Reference (linkage): a staticlib is *"a static library
containing all of the local crate's code along with all upstream
dependencies"*; *"because the resulting static library contains the code of
all the dependencies, including the standard library, and also exports all
public symbols of them, linking the static library… may need special care"*;
*"If you need to link multiple Rust subsystems, you will need to generate a
single staticlib… Multiple Rust staticlib files are likely to conflict."*
Unwinding consistency: *"If a Rust artifact is potentially unwinding, then all
its crates must be built with the unwind panic strategy. Otherwise, unwinding
can cause undefined behavior."* Rustonomicon: *"unwinding into Rust from
another language, or unwinding into another language from Rust is Undefined
Behavior. You must absolutely catch any panics at the FFI boundary!"* rustc
codegen options: *"abort: terminate the process upon panic… If any crate in
the crate graph uses abort, the final binary (bin, dylib, cdylib, staticlib)
must also use abort."* Go: cmd/cgo doc.go — external mode *"invokes the host
linker (usually gcc)"*; cmd/link: *"-linkmode mode — Set link mode (internal,
external, auto)"*. Our broker exists because modern Go rejects hand-written
`//go:cgo_import_static` (Spike 1).

**Decision — DESIGN RULES.** (1) Exactly **one** Rust staticlib per binary:
the bridge crate (single Cargo workspace root emitted by `hybrid build`)
aggregates every Rust dependency — duplicate-std is structurally impossible.
(2) Bridge crate compiles `panic=abort`; boundary panic contract = *abort
with message* (panic hook prints, then abort); Go never recovers a Rust
panic. Tension with Spike 5 (error representation): `catch_unwind→Result`
needs `panic=unwind` globally — deferred; abort is the MVP default. (3)
External link mode accepted (Spike 2 E4/E6: Rust-calling packages need
cgo+C linker; pure-Go packages still build CGO_ENABLED=0); PIE: host distro
default stands, asserted in CI.
**TESTS:** T1 (negative, CI-docs): two trivial staticlibs in one cgo binary →
duplicate-symbol link error (record observed). T2 panic contract: Rust
`panic!` → SIGABRT, message printed, no hang, no Go recovery. T3 — full
suite with PIE-forced link → PASS.

## 7. Process-level state

**Hazard.** (a) `fork()` from a multithreaded process keeps only the calling
thread — Go's Ms, locks and Rust pools are gone or deadlocked in the child.
(b) `os.Setenv` mutates Go's locked copy *and* the C environment; C `getenv`
is unsynchronized. (c) Init order: Go `init()` runs sequentially before main;
Rust ctor-style constructors (`.init_array`) run at ELF load time — possibly
before the Go runtime initializes, in unknown relative order.

**Evidence.** POSIX fork: *"A process shall be created with a single thread.
If a multi-threaded process calls fork(), the new process shall contain a
replica of the calling thread and its entire address space, possibly
including the states of mutexes and other resources. Consequently, to avoid
errors, the child process may only execute async-signal-safe operations
until such time as one of the exec functions is called."* Go guards it
itself: `newstack` → `throw("stack growth after fork")` (runtime/stack.go).
Env: syscall/env_unix.go keeps `envs` under `envLock sync.RWMutex` and calls
`runtimeSetenv`; runtime/env_posix.go: *"Update the C environment if cgo is
loaded"* (`setenv_c` → `_cgo_setenv` via `asmcgocall`). POSIX getenv: *"The
getenv() function need not be thread-safe."* Init: Go spec
(#Package_initialization): *"Package initialization—variable initialization
and the invocation of init functions—happens in a single goroutine,
sequentially, one package at a time."* Rust ctor prior art (mmastrac/linktime,
ex-rust-ctor): *"Module initialization functions for Rust (like
`__attribute__((constructor))` in C/C++). Run code before main."* Go itself
acknowledges constructor interleaving: *"For -buildmode=c-archive the Go
runtime will initialize signals at global constructor time"* (os/signal doc.go).

**Decision — DESIGN RULES.** (1) Hybrid offers **no fork primitive**;
subprocesses via `os/exec` (Go's ForkExec path, runtime-safe). Guest crates
calling libc `fork()` are outside the supported envelope — documented with
the POSIX quote. (2) Hybrid env access is `os.Getenv/Setenv` only; Rust
`std::env` reads allowed but never guaranteed concurrent with Go env mutation
(we cannot lock glibc's getenv — same constraint as any cgo program).
(3) All Rust initialization runs from a Hybrid-generated Go `init()` calling
an explicit `hybrid_rt_init(descriptor)` — deterministic order per the spec
quote. Guest `#[ctor]`/`.init_array` is **forbidden** (lint + docs); its
ordering vs Go runtime startup is UNVERIFIED (below).
**TESTS:** T1 ctor characterization — staticlib with `#[ctor]` printing, in
a Go binary via the broker: record whether it runs before Go's runtime.main,
after package init, or never; the observation justifies rule 3. T2 env race
(informational): `os.Setenv` ×10⁵ vs Rust `std::env::var` ×10⁵ concurrently —
record outcome; expected benign on glibc but not guaranteed; not a CI gate.
T3 — `os/exec` round-trip with a live Rust pool + handles in the parent →
parent unaffected, child is fresh.

## 8. cgo pointer rules

**Hazard.** Go pointers that *contain* unpinned Go pointers must not cross to
C/Rust; `cgocheck` polices that on the cgo path — but our asm trampoline path
is **not** instrumented, so the same violations would be silent.
Separately `invalidptr` crashes on Rust-shaped values in pointer-typed slots
(rust2go's `GODEBUG=invalidptr=0,cgocheck=0` requirement — a process-wide
safety downgrade we refuse to inherit).

**Evidence.** go.dev/cmd/cgo: *"Go code may pass a Go pointer to C provided
the memory to which it points does not contain any Go pointers to memory that
is unpinned"*; *"C code may not keep a copy of a Go pointer after the call
returns, unless the memory it points to is pinned with runtime.Pinner"*;
*"These rules are checked dynamically at runtime. The checking is controlled
by the cgocheck setting of the GODEBUG environment variable. The default
setting is GODEBUG=cgocheck=1… These checks may be disabled entirely using
GODEBUG=cgocheck=0. Complete checking… is available by setting
GOEXPERIMENT=cgocheck2 at build time."* invalidptr (pkg.go.dev/runtime):
*"invalidptr=1 (the default) causes the garbage collector and stack copier to
crash the program if an invalid pointer value (for example, 1) is found in a
pointer-typed location"* — rust2go's `NonNull::dangling()` empty-`Vec` case
(research/rust2go.md, issue #92).

**Decision — DESIGN RULES.** (1) **Never** require `cgocheck=0` or
`invalidptr=0`: all Hybrid tests/CI run default GODEBUG; the ABI fixes root
causes — empty Rust containers lower to **null** (never dangling-aligned
pointers); Rust heap addresses never live in Go GC-visible pointer-typed
slots (they travel as `uintptr` inside handle/arena structs with a documented
non-pointer invariant, or not at all). (2) The generator owns what the cgo
runtime can't see: emitted wrappers pin borrow args for the call (Pinner),
emit `runtime.KeepAlive` after it, arena-copy anything that outlives it; a
static lint on emitted Go asserts no `unsafe.Pointer(...)` conversion of
bridge-returned values and no stored raw foreign pointers. (3) CI legs:
default GODEBUG always + one `GOEXPERIMENT=cgocheck2` leg once any real cgo
call exists (the broker init).
**TESTS:** T1 — Spike-3 suite passes unmodified under `GOEXPERIMENT=cgocheck2`
+ default GODEBUG. T2 (negative, emitter-level) — feed the emitter a boundary
type with an interior Go pointer + unsafe conversion → generator rejects.
T3 — handle round-trip under GC torture (item 9).

## 9. Finalizers and handles

**Hazard.** Finalizers/cleanups run on a separate goroutine at an unspecified
time — *sequentially for finalizers, concurrently for cleanups* — so handle
release can fire long after the Go object died, concurrently with live calls
on other handles, and is **not guaranteed to run before exit**. A release
that touches the dying object, blocks, or races the table corrupts state or
deadlocks the single finalizer goroutine.

**Evidence.** pkg.go.dev/runtime `SetFinalizer`: *"the garbage collector…
runs finalizer(obj) in a separate goroutine"*; *"The finalizer is scheduled
to run at some arbitrary time after the program can no longer reach the
object"*; *"There is no guarantee that finalizers will run before a program
exits"*; *"A single goroutine runs all finalizers for a program,
sequentially."* `AddCleanup` (go1.24+): *"New Go code should consider using
AddCleanup instead, which is much less error-prone than SetFinalizer"*;
*"Cleanups run concurrently with any user-created goroutines. Cleanups may
also run concurrently with one another (unlike finalizers)."*; *"If a cleanup
function must run for a long time, it should create a new goroutine."* Debug
aid: `GODEBUG=checkfinalizers=1` runs *"multiple partial non-parallel
stop-the-world collections to identify common issues with finalizers and
cleanups"*. rustygo's "finalizers closing fds 0/1/2 → silent exit 0" bug is
the same class (research/rustygo.md); the `KeepAlive` doc's mid-`Write`
fd-close example is the premature-release failure mode.

**Decision — DESIGN RULES.** (1) Release uses
`runtime.AddCleanup(ptr, fn, handleID)` — the cleanup receives the **handle
id by value**, never the dying object (AddCleanup's `arg` design; `arg==ptr`
is a built-in panic check). (2) Release is **idempotent** and
**concurrent-safe** (per-handle mutex / sharded table lock), never blocking
(short Rust drop thunk only). (3) Cleanup is a leak safety-net, not
correctness: explicit `Close` is the API; exit-time release is best-effort.
**TESTS:** T1 release storm — 10⁵ handles, drop refs, `runtime.GC()` + drain
via WaitGroup fed from cleanup; Rust allocator counter returns to baseline;
drop thunk fires exactly 10⁵ times (no double free). T2 — cleanup storm
overlapping live traffic on other handles (`-race` + `checkfinalizers=1`
leg). T3 premature release — GC during a borrow-style Rust call → the
generator's `KeepAlive` keeps the borrow alive for the call.

---

## §12 integration concerns — decision-only rows

**ABI stability.** Rust: *"any function that you write in Rust will use the
Rust ABI (which is also not stabilized)"* (Embedded Rust Book). Go: *"It is
intended that programs written to the Go 1 specification will continue to
compile and run correctly, unchanged, over the lifetime of that
specification"* (go.dev/doc/go1compat). RULE: the boundary is C-layout only
(`#[repr(C)]` + `extern "C"` + `#[no_mangle]` vs generated Go decls); the
descriptor schema (type table, stack budget, drop entries, handle ops) is
**versioned and hashed**; bridge init compares the Go-side hash against a
Rust static — mismatch aborts with a clear message. Single-staticlib (item 6)
means Rust-internal ABI never crosses a compilation boundary. TEST: stale
descriptor → startup handshake error, never corruption. → `interfaces/abi-types.md`.

**Toolchain upgrades.** RULE: pins stay (go1.26.9 / 1.99.0); an upgrade branch
runs the full spike corpus — Spike 1 probes (20k-deep recursion, scheduler
migration, GC hammer, race) are precisely the canary for trampoline ABI rot —
plus regenerates all generated code and rebuilds the staticlib
(source-distribution model, Spike 2 E5). CI carries a non-blocking "next Go
minor" leg. → `gates/G0.md` + CI.

**Platform matrix.** MVP = Linux amd64, arm64 second: both Go ports —
*"amd64 (64-bit x86, the most mature port)"*, *"arm64 (64-bit ARM)"*
(go.dev/doc/install/source) — and Rust Tier-1. Cross-compiling the Rust side
needs a cross C toolchain (Spike 2 E7) ⇒ distribution stays "source build on
target, or committed per-target prebuilt `.a` + generated Go" (E5 PASS).
arm64 trampoline after amd64 is green; expected bug class: LR-register
handling (rust2go's arm64 LR-clobber lesson). TEST: full suite on arm64
hardware (worker tier has none — recorded gap; Actions arm64 runners planned).

**Debugging across frames.** RULE: keep DWARF everywhere — never pass `-w`
(*"Omit the DWARF symbol table"*, cmd/link); `//line` → `.hy` attribution
already proven (Spike 2 E1c/E1d). Go tracebacks stitch foreign frames only
via `runtime.SetCgoTraceback` (*"records three C functions to use to gather
traceback information from C code"*) — cgo path only; our asm path gets no
automatic stitching. Documented MVP story: Go tracebacks stop at a named
`hybrid_cross_<fn>` trampoline frame; Rust frames appear in Rust's own
abort/panic backtrace (`RUST_BACKTRACE=1`). Trampoline CFI/`.eh_frame`
emission is Phase 5 (rustgo's "confuse the hell out of debuggers" warning).
TEST (Phase 5, characterization): gdb break on a Rust symbol — record whether
backtrace unwinds Go frames above before promising it.

**Linking implications of the trampoline design.** We do NOT use
`cgo_import_static` (rejected by modern Go, Spike 1) — the address-broker cgo
package + pure-Go/asm trampoline package is the Go-1.26-proof pattern. It
implies external link mode (cmd/cgo doc.go: external mode *"invokes the host
linker (usually gcc)"*) and therefore a C toolchain for any Rust-calling
build (Spike 2 E6; pure-Go emitted packages unaffected). Accepted and
documented; internal link mode is not attempted.

## UNVERIFIED (explicit)

- **Rust ctor vs Go runtime startup order** (item 7 T1): whether `.init_array`
  from the staticlib runs before/after Go runtime init in an externally-linked
  Go binary is undocumented anywhere fetchable — characterization test
  required before relying on any ordering.
- **glibc `getenv`/`setenv` race specifics** (item 7): man7.org unreachable
  from this sandbox; only the POSIX "need not be thread-safe" statement and
  Go source mechanics cited. T2 is informational, not a gate.
- **Exact preemption behavior while SP is on the mmap'd Rust stack** (item 2):
  code-reading of `isAsyncSafePoint`/`findfunc` says a Rust PC is simply not
  preempted; T3 verifies empirically (Spike 1 already saw no crashes).
- **glibc default pthread guardsize (1 page) for Rust spawned threads**
  (item 5): POSIX allows ≥0; the glibc-specific default was not fetchable —
  irrelevant to our design (we make our own guard pages) but noted.
- **Delve/gdb cross-language frame walking** (Debugging row): no first-party
  doc fetched; deferred to the Phase 5 characterization test.

## Sources fetched (2026-10-11)

go.dev: /cmd/cgo/, /ref/spec, /doc/go1compat, /cmd/link/, /doc/install/source ·
pkg.go.dev: /runtime, /runtime/cgo · golang/go@go1.26.9 (raw):
src/runtime/{runtime,stack,mfinal,pinner,signal_unix,sigtab_linux_generic,
preempt,env_posix}.go, src/os/signal/doc.go, src/syscall/env_unix.go,
src/cmd/cgo/doc.go · doc.rust-lang.org (std 1.99.0): /std/thread/,
/std/macro.thread_local.html, /std/marker/trait.Send.html,
/rustc/codegen-options/, /reference/linkage.html, /nomicon/unwinding.html,
/embedded-book/interoperability/rust-with-c.html · docs.rs/rayon
(ThreadPoolBuilder) + rayon-rs/rayon FAQ (raw) · docs.rs/tokio/runtime ·
pubs.opengroup.org: fork, getenv, pthread_attr_setguardsize ·
mmastrac/rust-ctor README (raw; now "linktime").
