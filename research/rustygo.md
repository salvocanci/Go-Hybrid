# rustygo (KarpelesLab) — research note

## Identity

- Repo: https://github.com/KarpelesLab/rustygo (default branch: `master`; `main` 404s)
- Description (repo title tag, verbatim): "A Go to Rust compiler: compile Go
  packages into Rust source with a Rust runtime (GC, sched…)"
- License: **MIT** — `LICENSE` reads "MIT License / Copyright (c) 2026 Karpelès
  Lab Inc." Same stated in README ("MIT. Copyright © 2026 Karpelès Lab Inc.")
- Status: **active, not archived**. Changelog shows `v0.0.3` released
  2026-09-29; `docs/ROADMAP.md` carries status notes dated 2026-10-06; CI badge
  in README (`actions/workflows/ci.yml`). Also published as the `rustygo` crate
  on crates.io with docs.rs badge.
- Stack pins: Rust MSRV 1.89 (edition 2024); compiler targets the Go release
  pinned in `go.mod` (GOTEST harness ran on `go1.26.5`); one repo + one version
  number, two halves: compiler in Go (`cmd/rustygo`, `internal/`), runtime in
  Rust (`Cargo.toml`, `src/`).
- Star count: not retrievable during this pass (GitHub API rate-limited from
  this sandbox; HTML issue/insights pages are React-rendered). Treat star count
  as UNVERIFIED-live; the repo's own artifacts are all verified from the
  `master` tarball (364 KB, 311 paths).
- Research method note: no full clone/read. Metadata via repo page + README via
  raw.githubusercontent, tree via codeload tarball listing; only the files cited
  below were read. (A previous attempt at this task timed out reading
  everything; this pass was API/tarball-surgical.)

## What it actually is (verified)

A **Go → Rust source compiler** with a **Rust-side Go runtime**. Go packages are
loaded with `go/packages` + `go/types`, lowered to SSA with Go's own `go/ssa`
(the Go compiler is *not* forked), and a code generator emits **safe Rust
crates** ("no `unsafe` in anything you write") that link against the `rustygo`
runtime crate, which is where all the `unsafe` lives — "the garbage collector
and the coroutine context switch — the same way Rust's own `std` confines it."

The output is deliberately ugly Rust: "Not a source-to-source beautifier. The
output is Rust that `rustc` compiles, not Rust a human would enjoy reading."
rustc then produces native binaries, or `fullrust` static binaries, `purestd`
libc-free userland, or a `no_std` subset.

Milestone framing: M0/M1 done; M2 (goroutines) and M3 (stdlib) in progress.
README quote: "Go programs compile to Rust and run under a precise mark-sweep
collector, and their output, panics and exit codes are identical to gc's — 75
differential programs check that on every commit, every one of them also under
GC torture, which collects at every allocation."

The standard library is **the Go distribution's own source, compiled** with the
`purego` build tag; only `runtime`, `syscall`, the `os` bottom, `reflect`
internals, and `sync/atomic` are reimplemented on Rust std. Third-party coverage
is tracked in `docs/THIRDPARTY.md` (gorilla/mux, gorilla/websocket, go-chi,
testify, zap, logrus, viper, pflag, lib/pq, go-sql-driver/mysql, sqlx,
yaml.v2/v3, uuid, protobuf/proto, x/net/html, x/text, x/crypto, golang-jwt).

## Architecture (pipeline + runtime design)

Pipeline (README "Shape" diagram):

```
Go packages ──► go/packages + go/types ──► go/ssa
                                             │
                                   rustygo code generator
                                             │
              ┌──────────────────────────────┴─────────────────┐
              ▼                                                ▼
   generated Rust crate(s)                       `rustygo` crate (runtime)
   (safe Rust, no unsafe)                        GC · scheduler · chan · map ·
              │                                  reflect · syscall shims
              └──────────────────────┬───────────────────────────┘
                                     ▼
                                   rustc
                                     │
              native · fullrust · purestd · no_std subset
```

**Transpiler frontend** — `internal/emit/emit.go`: "Package emit turns a built
SSA program into a Rust crate that links against the rustygo runtime crate."
Generated-crate layout: `Cargo.toml` (runtime as path dep), `src/main.rs`,
`src/ty.rs` (one struct + place struct per Go type), `src/<pkg>.rs` per package.
Emission is on-demand from main's `init`/`main` following static calls "so
unreachable code and uninstantiated generic bodies never reach rustc"; a
**two-pass** design (first pass finds live init globals via `deadinit.go` and
call-graph "bands" via `bands.go`; second pass emits with that knowledge).
Out-of-M0-subset constructs "are rejected with a positioned error rather than
miscompiled."

**Goroutines / context switch** — `src/context.rs`: stackful coroutines, not
async: "Every Go function may block, so rustygo does not colour functions
`async`: a goroutine is a real stack, and blocking swaps stacks." Only
callee-saved registers + SP are saved because "the switch *is* a call as far as
the compiler knows." x86-64 `switch_asm` (naked asm):

```
push rbp / push rbx / push r12–r15
mov [rdi], rsp      // save SP into `from` Context
mov rsp, [rsi]      // load `to` Context's SP
pop r15 … pop rbp
ret
```

`Context::prepare(stack_top, entry, arg)` plants the entry function/arg/return
slots at a fresh stack's top. Windows x64 is explicitly unsupported: its ABI
makes `rdi`,`rsi`,`xmm6–15` callee-saved and keeps stack bounds in the TIB, so
"a Windows build compiles and says so rather than corrupting itself quietly."

**Scheduler** — `src/sched.rs` (62 KB, the largest runtime file; inspected via
structure, not full read): `struct G` (one goroutine), `struct M` (one worker
thread), `struct Sched`; goroutines "run on worker threads, as many of them at
once as `GOMAXPROCS` allows. A worker stands on its thread's own stack between
goroutines"; "the worker, not the goroutine, is what puts a yielding goroutine
back on the run queue." Stop-the-world GC at safe points ("every loop
back-edge, and the top of every allocation"). Parking protocol:
`prepare_park` registers as a waiter **while still holding the lock that guards
what it is waiting for**, then `park` — "A wake that arrives in the window
between the two is not lost." One shared run queue under one lock today; work
stealing not yet in.

**GC roots (shadow stack)** — `src/gc.rs`: every generated function that holds
a Go reference links a `Frame<N>` of root slots via `Frame::scope`, chained
per-thread through `rt_global! { static TOP }`; assignment to a pointer-holding
local rewrites its slot. `take_top`/`put_top` hand the chain between goroutine
and thread across switches. `safepoint()` is emitted at every loop back-edge
(`internal/emit/roots.go`).

**Collector / heap** — `src/heap.rs`: "a precise, stop-the-world mark-sweep
collector over one heap". Every object is a table entry (`start`, `size`,
`trace`, `drop`, `align_log2`, `mark`) in a `Vec<Obj>`; **interior pointers**
(`&s.f`, `&a[i]`) resolve to their object "by binary search"; non-heap words
are skipped. Threshold starts at `4 MiB`. **One heap, one lock** — "Every
thread allocates from the same table… whether per-thread caches over size
classes are worth their complexity, is M6's question." GC-torture mode poisons
and quarantines freed objects so "any later use of one is a missing root and
panics by name."

**Channels** — `src/chan.rs`: `ChanObj<T>` is a heap object holding
`Lock<State<T>>` (buffered `VecDeque`, `cap`, `closed`, receiver count). All
decide-and-register happens under the channel's own lock; then "only then —
with the lock released, because a park switches stacks — parks." Waiters are
woken wholesale (`wake_all`) with send/recv park keys one address apart
(`recv_key = addr + 1`) so receiving and sending waiters never wake each other;
"the queues are still to come." `try_recv`/`try_send`/`enter_recv` implement
`select` semantics with random ready-case choice in the emitted select.

**Thread-vs-program state** — `src/tls.rs`: the load-bearing discipline.
`rt_global!` declares per-thread state (shadow stack TOP, panic stack — "the
scheduler swaps it in and out around every context switch"); `rt_shared!`
declares program state behind `Lock<T>` (heap, goroutine table, waiter table,
netpoller, finalizer table — "in a fixed order"). `Lock::with` is closure-based
because "a thread that switches goroutines while holding one of these hands the
next goroutine a lock it cannot take"; debug builds panic on re-entrant take
("a runtime lock was taken twice by the same thread") instead of hanging.

**Stacks** — fixed-size virtual reservations, lazily committed, guard page
below; "Rust frames hold raw addresses into the stack, so Go-style stack
copying is not available" (ROADMAP M2, citing DESIGN §4). Panic never unwinds
across a context switch; it runs defers and becomes a fatal process exit.

## The claims check

| claim | verdict | evidence |
|---|---|---|
| "Compiles Go source to Rust with a Rust-based Go runtime." | **CONFIRMED** | README: "A Go → Rust compiler. Compile Go packages into Rust source, link them with a Rust runtime"; repo layout table: `cmd/rustygo`+`internal/` = Go compiler, `Cargo.toml`+`src/` = Rust runtime crate; pipeline diagram above; frontend is `go/ssa` ("the Go compiler is not forked"). |
| "~125/141 Go tests passing" | **CORRECTED (slightly stale)** | README says "Go's own `test/` directory is at 125 of 141"; the current `docs/GOTEST.md` (regenerated on `go1.26.5-X:nodwarf5`, linux/amd64) says **127 of 141, 90%**, with all 14 failures listed (nilptr*, stackobj*, recover4, peano, inline_literal timeout, gcgort, heapsampling, finprofiled, devirtualization_nil_panics, linkmain_run, winbatch). |
| "goroutines, channels, select, net/http work" | **CONFIRMED (single-threaded)** | README: "Goroutines are real stacks with a context switch written for the purpose, with channels, `select`, `sync`, timers and a netpoller under them" and "`net/http` as a server *and* a client in one process, over TLS as well as plain HTTP and over HTTP/2 as well as HTTP/1.1" (BoBo TLS suite: same 1,318 cases as gc). Verified in code: `src/chan.rs` (buffered + sync channels, close, select primitives), `src/sched.rs`, `src/netpoll.rs` (25 KB, epoll_wait). Caveat: all of it runs with `GOMAXPROCS=1` semantics — see next row. |
| "single-threaded only due to scheduler memory corruption above one thread" | **CONFIRMED, with precise evidence** | README: "`GOMAXPROCS` defaults to one, because above one a `parallel` program stalls or crashes in a way that is memory corruption rather than a mis-saved context, and the roadmap says where the suspects are." ROADMAP M2 status (2026-10-06): "more than one still corrupts a goroutine's saved context". Failure matrix below. |

**The failure matrix** (ROADMAP, `testdata/programs/parallel` — 64 goroutines
on one mutex, 20 runs per setting):

| `GOMAXPROCS` | correct | stalls | segfaults | `pick` says so |
|---|---|---|---|---|
| 1 | 20 | 0 | 0 | 0 |
| 2 | 14 | 6 | 0 | 0 |
| 4 | 0 | 1 | 18 | 1 |

## What Hybrid should extract

1. **Use `go/ssa` as the frontend, never fork the Go compiler.** rustygo's
   whole compiler half is `go/packages → go/types → go/ssa → emitter`, which
   keeps Go's parser/type-checker semantics for free. For Hybrid's "adopt Rust
   incrementally" story this is the cheapest correct path for understanding Go
   code we transpile or type-map.
2. **Emit safe Rust; quarantine the `unsafe` in a runtime crate.** Generated
   code contains zero `unsafe`; the GC and the context switch are the only
   unsafe residents. This is exactly the pitch Hybrid makes to Go teams
   ("Rust-grade memory safety") and it is provably attainable.
3. **The `rt_global!` / `rt_shared!` discipline (`src/tls.rs`).** A single file
   that declares, for every piece of runtime state, whether it belongs to a
   thread or to the program, with a closure-shaped lock API that cannot be held
   across a context switch and a debug re-entrancy check. On our 2-core/4GB
   sandbox this is the *minimum* document needed before any second thread
   exists; adopt it verbatim as a Hybrid runtime invariant.
4. **Shadow-stack GC roots + loop-back-edge safe points (`src/gc.rs`).**
   Cheaper than stack scanning, precise, and testable via **GC torture** (collect
   on every allocation + quarantine poison). Hybrid should ship a torture mode
   for the Go-object graph from day one — it is what makes "no unsafe in user
   code" auditable.
5. **Decide-and-register-under-lock, then park (`prepare_park`/`park`).** The
   lost-wakeup protocol is the single most reusable concurrency pattern here;
   channel ops decide and register in one critical section and park after
   release. Any Hybrid primitive that blocks needs this shape.
6. **Differential testing against gc, not against itself.** 75 differential
   programs every commit, Go's own `test/` corpus (127/141), the stdlib's own
   tests via `rustygo test`, BoBo TLS suite parity. Hybrid should adopt
   "output+exit-code identical to gc" as its acceptance gate for transpiled
   code.
7. **Object table with interior-pointer resolution by binary search
   (`src/heap.rs`).** Needed if Hybrid ever allows Go-style `&s.f` into shared
   GC objects. But note the cost: one heap, one lock — on 2 cores that
   serializes allocation; prefer Rust-ownership objects + a small GC'd graph
   only for Go-side data.
8. **Fixed reserved stacks with guard pages, not copied stacks.** Rust frames
   pin raw stack addresses, so Go-style stack copying is structurally
   unavailable; rustygo's answer (virtual reservation, lazy commit, guard page)
   is the right one for Hybrid's guest goroutines, and 100k parked goroutines
   in a stated memory budget is a good target metric for our 4GB box.
9. **What NOT to copy yet: the M:N multi-worker scheduler.** Our sandbox has 2
   cores; GOMAXPROCS=2 is precisely the zone where rustygo segfaults 18/20.
   Ship single-worker guest runtimes first; expose parallelism through Rust
   threads over disjoint data, and only adopt multi-worker M:N once we can
   reproduce rustygo's fix.

## Failure modes / lessons

**The multi-thread scheduler corruption (primary lesson).** Evidence chain
from `docs/ROADMAP.md` (M2 status, 2026-10-06):

- The M:N machinery all exists — worker threads, `GOMAXPROCS`, `LockOSThread`,
  real atomics, stop-the-world — yet it ships pinned to one worker "because
  more than one still corrupts a goroutine's saved context."
- Symptom: "Above one worker, a goroutine's saved context acquires a stack
  pointer belonging to a worker's own native stack, so resuming it returns
  through that pointer into nowhere." `pick` (the resume path) has a check that
  the context points inside the goroutine's own stack — it fires and names it.
- Allocator angle: under `RUSTYGO_TRACE=sched` the stall becomes a crash in ~1/3
  of runs, once with glibc's `double free or corruption (out)`; "A corrupt
  allocator explains the rest."
- Debuggability: `MALLOC_CHECK_=3` does not catch it; valgrind is useless
  because "memcheck cannot follow a naked-assembly stack switch without
  `VALGRIND_STACK_REGISTER` client requests the runtime does not make."
- Three measurements that "narrow it and then contradict each other": the
  thread-local naming the running goroutine, the scheduler's own record, and
  the goroutine whose stack the thread stands on all agree at failure — so not
  a stale thread-local, not a goroutine handed to two threads; only `leave`
  writes a context and an ownership assertion there never fired. "One of those
  three is lying."
- Named suspects: (1) `src/map.rs` keeps its table in an `UnsafeCell` not a
  `RefCell` because concurrent map *reads* are legal Go — "That removed the one
  dynamic check that would have caught a concurrent map write, and a corrupted
  hash table is exactly what produces a glibc double free"; (2)
  `heap::Global<P>`'s double-checked initialization and the `Lock<T>` guarding
  it in `src/tls.rs`; (3) no owner tag on `Context` and `switch(from, to)`
  taking same-typed pointers so "from and to cannot be transposed" is not
  enforced.
- Root-cause hypothesis (mine, from their evidence): a cross-thread write into
  a per-goroutine `Context`/`G` record during the handoff window between
  `leave` and `pick` — i.e., unsynchronized ownership transfer of scheduler
  metadata — which then manifests as either a bogus saved SP (the `pick` catch)
  or heap metadata corruption (the double free). Their planned fix (owner tag
  set by `Context::prepare` and checked by `switch`, plus distinct `from`/`to`
  types) is type-system-enforced ownership of switch targets; Hybrid should
  build that in from the start rather than retrofit it.
- Pre-existing traps they found once threading landed (all fixed on the branch,
  worth memorizing): `sync/atomic` was compiled to plain Go loads/stores (so
  `sync.Mutex` "unlocked itself the moment two threads existed"); package-level
  Go variables had been `thread_local!` (one copy per thread); thread-vs-program
  state was decided case-by-case across the runtime until `src/tls.rs`
  centralized it. Earlier red herring: finalizers closing fds 0/1/2 made
  programs exit 0 silently and "looked like a scheduling bug and scaled like
  one."
- Other structural limitations: no Windows goroutines (TIB/callee-saved ABI);
  kernel-touching packages are Linux-only; no runtime type construction
  (`reflect.MakeFunc`, `StructOf` say so instead of guessing) because type
  descriptors are Rust statics; "This is a TinyGo-sized project" — honest cost
  section is itself a lesson (budget years, or scope down).

## Licensing

MIT (repo `LICENSE`, Copyright (c) 2026 Karpelès Lab Inc.). Fully compatible
with a dual MIT/Apache-2.0 product: MIT is a permissive subset of the pair; we
can depend on, fork, or vendor rustygo code with attribution and license text
retained. No CLA/cooler caveats visible in the tarball.

## Verdict for Go-Hybrid

**Borrow ideas aggressively; consider a runtime-level fork later; do not build
on top of the compiler yet.**

Rationale: rustygo is the strongest existing proof that (a) Go can compile to
*safe* Rust via `go/ssa`, (b) a Rust-implemented Go runtime (GC, scheduler,
channels, netpoller) can pass 90% of Go's own test corpus and run the real
stdlib including net/http over HTTP/2+TLS — all MIT. That validates Hybrid's
core premise. But it is v0.0.3, pre-1.0, single-worker by necessity, and its
hardest unsolved bug (multi-worker context corruption) is exactly the bug
Hybrid must not inherit. Concretely: take the frontend strategy (`go/ssa`), the
tls.rs state-ownership discipline, the prepare_park/park protocol, the shadow
stack + GC torture test rig, and the differential-testing harness design; watch
their M2 fix for the Context owner-tag pattern before we enable a second guest
worker on our 2-core sandbox.
