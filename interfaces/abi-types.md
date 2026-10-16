# ABI: what may cross the Hybrid↔Rust boundary (DRAFT v0.1 — Phase 0)

**Status:** draft born from Spike 3 (spikes/spike3-memory/RESULTS.md) + the runtime
hazards review (research/runtime-hazards.md). Becomes authoritative at G1.
**Rule zero: anything not listed in this file MAY NOT cross the boundary in safe mode.**

## 1. Crossing mechanics (measured, go1.26.9 / rust 1.99.0 / linux-amd64)

| mechanism | cost (median) | when |
|-----------|--------------:|------|
| Fast path: in-trampoline `g.stackguard0` headroom check + SysV-aligned `CALL` on the caller's own goroutine stack | **2.42 ns** | callee stack budget ≤ 4 KiB (descriptor-declared) and headroom ≥ 4 KiB |
| Deep path: bitmap-pooled 1 MiB guarded mmap stack (exclusive per crossing) | 3.98 ns switch-only / 16.9 ns incl. pool | unbounded or > 4 KiB stack needs (recursion, unknown budgets) |

Discipline the bridge generator emits (see spikes/spike3-memory/work/go/hybridge/call_amd64.s):
1. all Go-frame inputs loaded BEFORE any SP adjustment;
2. old SP saved in a SysV callee-saved register (RBX), restored BEFORE writing results;
3. 16-byte SysV alignment at callee entry (rsp%16==8);
4. NOSPLIT: no Go stack growth inside the trampoline;
5. no callbacks into Go while on a deep stack; panics abort (never unwind across);
6. runtime.g offsets are version-pinned (extractor: `spikes/spike3-memory/work/extract_offsets.py`; canary test guards them).

## 2. Type crossing rules

| Hybrid type | Crossing | Layout | Ownership / lifetime |
|-------------|----------|--------|----------------------|
| u8..u64, i8..i64, f32, f64, bool | **by value** in registers (SysV: RDI, RSI, RDX, RCX, R8, R9 + stack) | C-compatible | trivially copied; no ownership |
| `string` ≤ 16 bytes | **by value** (two words, copied) | ptr+len packed as two u64 | copy made on the Go side before the call |
| `string` > 16 bytes / `[]T` buffers | **pinned borrow**: `runtime.Pinner` pins the backing array for ONE call; (ptr, len) view | ptr+len | pinned ⇒ cannot move or be freed; Unpin + `runtime.KeepAlive` after; **never stored across calls**. Pin costs ~55 ns/call ⇒ pin once per call *loop* where possible, or copy below threshold |
| small structs/arrays (≤ 4 words, no interior Go pointers) | **by value** (copied) | C-compatible layout generated | trivially copied |
| structs with interior Go pointers | **as fields per their own rules** — generator flattens | generated | per field |
| maps, channels, interfaces, closures, goroutine handles, io.Reader/Writer… | **opaque handle** (Go-side table id) | u64 id → Go-owned table slot keeps the object alive | table entry is the root; released explicitly or via `runtime.AddCleanup`; ids are values (no dangling possible) |
| Rust-owned objects (any `rust` crate type) | **opaque handle** (Rust-side table id) | u64 = (generation << 32) \| (index+1) | refcounted; Go wrapper CAS-releases once; cleanup may release late — stale generation reads INVALID, never corrupts |
| `error` values | per Spike 5 (pending) — until then: crossing an error is **forbidden** | — | — |
| function pointers / callbacks | **forbidden in v0** (no re-entrancy across the boundary) | — | — |

**Slices as views:** a `[]T` crossing as a pinned borrow is READ/WRITE for the
duration of one call. The callee may not retain the pointer (generator-enforced
by type rules: the Rust signature sees `&[T]` with no `'static`).

## 3. Lifetime model (Spike 3 decision)

- **Default: owning-side handle tables + refcount** (WIT own/borrow shape).
  The side that owns an object owns its table; the other side only ever sees
  integers. "Freed when both sides release it" = the owning side's refcount
  reaching zero (Go wrapper release + any Rust-side retains/releases).
- **Opt-in: scoped arena** for burst temporaries (enter → allocations → exit
  frees all; LIFO-verified; dead slots read INVALID). ~134 ns for a 4-op cycle;
  use where allocation churn dominates.
- **Go finalizers/cleanups are safe release sites**: release must be
  idempotent, run-any-thread, and generation-protected (a late cleanup on a
  reused slot reads INVALID — verified by TestUseAfterReleaseSentinel).
- **No raw cross-language pointers in safe mode** — P7 (freed-then-reused heap
  read back as churn poison) and P8 (captured stack slot overwritten) both
  demonstrated in the spike; `managed`/`unsafe` escape hatches are the only
  exception, linted.

## 4. Hazard rules inherited from research/runtime-hazards.md (enforced here)

1. **Allocators:** Go frees Go memory, Rust frees Rust memory — never across;
   objects cross only as ids or pinned call-scoped views.
2. **Signals:** Go owns all handlers (SIGURG preemption reserved); guest crates
   must not install handlers or alter masks.
3. **Threads/TLS:** bridge state is Send+Sync; `!Send` Rust types are rejected
   at descriptor validation; goroutine migration is safe because no Go
   pointer survives a call.
4. **Foreign pools (rayon/tokio):** thread budget = `GOMAXPROCS(0)` read at
   bridge init and re-read on update; pools start on first explicit use only.
5. **Stacks:** Rust runs either on the caller goroutine stack (guard-checked,
   ≤4 KiB budget) or a pooled guarded mmap stack (1 MiB); never on an
   unchecked goroutine stack; deep recursion is descriptor-forced to the deep path.
6. **Linking:** ONE Rust staticlib per binary; `panic=abort` at the boundary;
   external link mode; cgo used only as the address broker (no per-call cgo).
7. **Process state:** no `fork`; env vars via `os`; all Rust init runs from
   generated Go `init()` (no `#[ctor]`).
8. **cgo pointer rules:** the null-not-dangling ABI + generator-emitted
   Pinner/KeepAlive means `GODEBUG=invalidptr=0,cgocheck=0` is NEVER required
   (the rust2go disease is designed out).
9. **Finalizers:** see §3.

## 5. Descriptor schema fields this implies (for the bridge generator)

- per exported fn: `stack_budget` (fast path eligibility), `args` (each typed
  by the table above), `ret`, `send_bound` (Send/Sync requirements),
  `blocking` (Spike 4's pool classification), `error_mapping` (Spike 5).
- per type: `crossing_kind` ∈ {value, copy, pinned_borrow, go_handle,
  rust_handle, forbidden}.
- versioned + hashed; runtime handshake aborts on mismatch.

## 6. Open items

- Spike 5: error representation (`(T, error)` ↔ `Result<T, E>`, allocation
  budget, panic conversion contract).
- Spike 4: blocking-call classification (does a `blocking` fn enter a
  Go-syscall-like state to release the P? measured next).
- Pin-amortization protocol for loops (pin once, many calls) needs a spelled-out
  generator pattern + test.
- arm64: PORTED (PLAN row 16, 2026-10-14). call_arm64.s mirrors the amd64
  discipline with three arch-specific simplifications (g is R28 — no TLS
  dance; BL pushes no return address — no SP surgery on the fast path; the
  deep path stashes the old SP in a scratch slot on the pooled stack — no
  callee-saved register borrowed). The amd64 LR-clobber concern does not
  apply: the assembler's own prologue/epilogue (declared frame > 0) saves and
  restores R30 around the BL. Offsets: g.stackguard0 = 16 extracted from an
  arm64-built binary (tools/extract_offsets.py) and cross-checked against the
  toolchain's own arm64 stacksplit (2*PtrSize). Fleet regression: the full
  5-package Go suite runs under qemu in the release-matrix arm64 leg, and the
  tarball smoke now includes a serde_json bridge crossing.
