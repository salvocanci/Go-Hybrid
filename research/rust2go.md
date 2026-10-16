# rust2go — research note

## Identity (URL, stars, license, status, activity, metadata)

- URL: https://github.com/ihciah/rust2go
- GitHub description: "Call Between Golang and Rust Asynchronously"
- Owner: ihciah (ByteDance infrastructure engineer; author of monoio; blog: en.ihcblog.com)
- Design blog: https://en.ihcblog.com/rust2go/ (2023-12-08, updated 2024-08-03)
- ASM follow-up blog: https://en.ihcblog.com/rust2go-cgo-asm/
- Refactor retrospective (by 2nd maintainer): https://lirenjie95.github.io/posts/rust2go-refactor.html
- GitHub API metadata (fetched 2026):
  - stars: 429, forks: 32, watchers: 6, open issues+PRs: 3
  - created: 2024-04-07, last push: 2026-10-05, NOT archived
  - default branch: `master`; primary language: Rust
  - repo is a Cargo workspace plus several Go modules (root `go.mod`, `go.work`)
- License: GitHub reports `NOASSERTION` (see Licensing section)
  - files: `LICENSE-APACHE` (verbatim Apache-2.0) + `LICENSE-MIT` (MIT with one extra sentence)
  - `Cargo.toml` declares `license = "MIT/Apache-2.0"`
- Activity: very healthy for its niche
  - a second maintainer (lirenjie95) executed a month-long, ~20-PR refactor in 2026
    (codegen restructure, CI hardening, 97% coverage gate, docs overhaul)
  - CI matrix: linux/macOS/Windows × amd64/arm64; Go 1.18 minimum leg; gofmt/go vet gates;
    codecov project target 97% (ratcheted 2026-09-08)
- Published crates: rust2go 0.4.x; workspace pins rust2go-common 0.4.1, rust2go-macro 0.4.1,
  rust2go-gen 0.1.0, mem-ring 0.2.0
  - open asks: tagged releases (#98) and a 1.0 (#118) — release discipline is the community's ask
- Community: bilingual (several Chinese-language issues); bug reports from real cross-platform
  users (iOS simulator, Windows ARM64, musl); fast maintainer response (days)

## What it actually is (verified from README + source)

rust2go is an FFI bridging framework for a single linked binary containing both Rust and Go:

- Primary direction: Rust calls Go — sync AND async (native `Future`).
- Secondary direction: Go calls Rust — sync only, including stateful Rust objects
  (process-wide instance registry added 2026 via issue #65).
- It is NOT IPC/RPC: the author explicitly rejected socket+serialization in the design blog
  because it costs "four memory copies and two memory allocations" per call; chose in-process
  FFI with a C ABI between the two runtimes.
- Defining idea (README, Features): "no new invented IDL except for native Rust".
  - The interface definition is a plain Rust file (`src/user.rs`) with restricted structs
    (`#[derive(rust2go::R2G)]`) and traits (`#[rust2go::r2g]` / `#[rust2go::g2r]`).
  - From that one file the toolchain generates BOTH sides:
    - Go: self-contained `gen.go` with cgo preamble (C structs via cbindgen), `//export`
      cgo wrapper functions, mirrored Go interface, mirrored Go structs, generic converters
    - Rust: trait rewrites (`async fn` → `impl Future`), `{Trait}Impl` struct with
      `extern "C"` callbacks, bindgen-produced declarations of the Go exports
- Performance obsession:
  - flat-layout parameters passed by reference (ptr+len), not copied
  - nested types (`Vec<String>`) flattened into one pre-sized buffer (single allocation)
  - Go→Rust callbacks default to hand-written assembly (`asmcall`) instead of cgo:
    29.19 ns (cgo) → 2.324 ns (asm) → 1.829 ns (asm, no stack switch) per empty call
    on go1.22/amd64 (benchmarks in `asmcall/README.md`)
  - opt-in shared-memory ring transport (`#[mem]`/`#[shm]`) for extreme-frequency calls:
    lock-free SPSC ring + socketpair notification + `ants.MultiPool` on the Go side +
    CALL/REPLY/DROP payload protocol
- Operational caveat (README): programs MUST run with `GODEBUG=invalidptr=0,cgocheck=0`
  because Go's runtime pointer checks see Rust-side pointers (e.g. `NonNull::dangling()`
  of empty `Vec`s) and panic
- Closed type universe (README "Binding File Notes" + `docs/trait-attrs.md`):
  - supported: all primitive ints/floats/bool/char(→rune, no converters), `String`, `Vec<T>`,
    user structs, non-generic type aliases, `Option<T>` (encoded as `Vec<T>`, None = empty)
  - NOT supported: enums, HashMap/map types, `char` in bindings, recursive/cyclic structures,
    generic structs (the derive silently skips them)
- Platform support: Linux/macOS/Windows; ASM callbacks amd64+arm64 only (auto cgo fallback);
  shm transport unix-only; Go >= 1.18 (`--go118` flag for 1.18/1.19), Rust >= 1.75 for async
- Inspired by fcplug (github.com/andeya/fcplug), per README Credit section

## Architecture (pipeline, crates/packages, codegen strategy — file paths as evidence)

Workspace layout (paths relative to repo root):

| Piece | Path | Role |
|---|---|---|
| Runtime crate | `rust2go/src/{lib,future,slot,builder}.rs` | Atomic slot, `ResponseFuture`, build-script `Builder` |
| Proc macros | `rust2go-macro/src/lib.rs` | `#[rust2go::r2g]`, `#[rust2go::g2r]`, `#[derive(R2G)]`, `r2g_struct_tag` |
| IR + emitters | `rust2go-common/src/{r2g,g2r}/{mod,emit_go,emit_rust}.rs` | `R2GTraitRepr`/`G2RTraitRepr` IR + per-direction emitters |
| C emitter | `rust2go-common/src/g2r/emit_c.rs` | weak-symbol C declarations for g2r entries |
| Go templates | `rust2go-common/src/tmpl/*.go.tmpl` | converter helpers + ring bootstrap emitted into `gen.go` |
| Type conversion | `rust2go-convert/src/{convert,primitive}.rs` | `ToRef`/`FromRef` traits + single `PRIMITIVES` table |
| Generation lib | `rust2go-gen/src/lib.rs` | `generate(&GenArgs)` — whole offline pipeline |
| CLI | `rust2go-cli/src/{main,lib}.rs` | thin shell over rust2go-gen (clap) |
| Shared-mem runtime | `rust2go-mem-ffi/src/lib.rs`, `mem-ring/` | `Payload` protocol, queues, SPSC ring (Rust+Go) |
| Go helper pkgs | `asmcall/` (amd64.s, arm64.s, fallback.go), `cgocall/`, `mem-ring/*.go` | ASM cgo replacement, plain cgo, ring Go side |

Offline codegen pipeline (verified in `rust2go-gen/src/lib.rs::generate`):

1. Parse `src/user.rs` with syn into `RawRsFile`; extract struct/trait IR.
2. Rewrite each struct into a `#[repr(C)]` Ref twin — e.g. `User` → `UserRef` with
   `StringRef{ptr,len}` / `ListRef{ptr,len}` fields (see derive in `rust2go-macro/src/lib.rs`);
   write a temporary Rust file to the destination path.
3. Run **cbindgen** over that file to emit the C header; this header becomes the cgo preamble
   in the final Go file (`test/go/gen.go` shows the inline `typedef struct StringRef {...}`).
4. Emit Go source: package header, conditional imports (shm/ants/runtime/asmcall only when
   used), mirrored interface (`type TestCall interface`), `//export C{Trait}_{fn}` wrappers,
   Go structs, generic `new_*_mapper`/`cnt_*_mapper`/`ref_*_mapper` converters,
   optional `ringsInit` bootstrap; then `go fmt` the result.
5. Rust side happens at compile time: the attribute macro rewrites the trait (drops `async`,
   adds `unsafe` or `+ Send + Sync + 'static` bounds per `#[send]`/`#[drop_safe]`) and
   generates `{Trait}Impl` with per-fn `#[no_mangle] unsafe extern "C" fn {fn}_cb` callbacks
   (`rust2go-common/src/r2g/emit_rust.rs`).

Async design (`rust2go/src/future.rs` + `slot.rs`):

- `ResponseFuture` is a three-state machine: Init → Executed → Fused.
- On first poll it allocates an atomic slot:
  `SlotInner{state: AtomicU8, data: MaybeUninit<T>, attachment, waker: Mutex<Option<Waker>>}`
- The raw slot pointer + callback fn pointer cross the FFI boundary; the future parks.
- The Go wrapper (`r2g/emit_go.rs`) runs the user's Go impl in `go func(){...}`, converts the
  response to Ref form, then invokes the Rust callback via `asmcall.CallFuncG0P2` (or cgo).
- The callback reconstructs the `SlotWriter` from the raw pointer, writes the response, wakes.
- The 3-bit atomic state (writer-dropped / reader-dropped / data-written) makes the slot a
  one-shot SPSC cell with safe drop on either side and no double-free.
- `#[drop_safe]` / `#[drop_safe_ret]` encode cancellation safety: if the future may be dropped
  before Go responds, params must be owned (stashed in the slot attachment); otherwise the
  generated fn is `unsafe`.

Shared-memory path (`rust2go-mem-ffi`, `mem-ring`):

- Per-thread `thread_local!` write-queue + slab of `TaskDesc{buf, params_ptr, slot_ptr}`.
- `Payload{ptr, user_data, next_user_data, call_id, flag}` protocol:
  CALL=0b0101, REPLY=0b1110, DROP=0b1000
  - oneway: send CALL, receive DROP ack (frees boxed params)
  - normal: CALL → REPLY (response parked in Go `MultiSlab`) → DROP (frees slab entry)
- Rings: lock-free SPSC, head/tail/working/stuck atomics, two socketpairs for wakeups;
  Go side drains via `RunHandler` and executes on `ants.NewMultiPool(8, -1, RoundRobin)`
  (`tmpl/shm_ring_init.go.tmpl`).
- monoio (default, thread-per-core, `Rc<UnsafeCell>`) vs tokio are mutually exclusive
  features, guarded by `compile_error!` (see `rust2go-mem-ffi/src/lib.rs` line 6).

Go→Rust direction (`g2r`):

- Each trait fn becomes `#[no_mangle] unsafe extern "C" fn c_{Trait}_{fn}(slot, params)`
  where params arrive as an array of pointers and are rebuilt via `FromRef`.
- The return value is boxed with its Ref form and buffer; `[ret_ptr, drop_ptr]` is written
  into the slot; the generated Go wrapper calls a TYPED drop entry `c_{Trait}_{fn}_drop`
  after converting, so memory frees with the correct layout (`g2r/emit_rust.rs` documents
  why a `dyn Any` round-trip would lose the vtable and leak).
- Stateful traits (all `&self` methods): process-wide `OnceLock<Arc<dyn Trait + Send + Sync>>`
  registry + `{Trait}Impl::register()`; calling before registration aborts fail-fast.
- `test/go/g2r_stub.go` uses `__attribute__((weak))` no-op stubs so the Go package builds
  standalone in CI; strong Rust definitions win in real links.

Build integration (`rust2go/src/builder.rs`):

- `build.rs` → `rust2go::Builder::new().with_go_src("./go").build()`:
  1. optionally regenerates `gen.go` from the Rust IDL (`with_regen`)
  2. runs `go build -buildmode=c-archive` (or c-shared for dynamic)
  3. generates `_go_bindings.rs` via bindgen into `OUT_DIR`
  4. emits `cargo:rustc-link-lib=static=go` + link-search
  5. restores the generated header's atime/mtime when content is unchanged, so dependent
     crates are not recompiled (fix for issue #83's rebuild storm)
- Developer story: edit `user.rs`, run `cargo build` — Go compilation happens inside the
  Cargo build; the Go toolchain is required at build time (host-side).

## The claims check (claim | verdict | evidence)

| Claim (from our SPEC) | Verdict | Evidence |
|---|---|---|
| "FFI framework with async support" | CONFIRMED | README features ("Sync and async calls from Rust to Golang"); `rust2go/src/future.rs` implements `Future` with waker-driven completion; design blog has an "Asynchronous Support" section comparing Rust/Go concurrency; `#[send]`/`#[drop_safe]` attributes modulate generated `Send`/`'static` bounds (`rust2go-macro/src/lib.rs`). |
| "Claimed production use at ByteDance" | CONFIRMED, with nuance | Author's design blog: "At ByteDance, to drive cost optimization, I developed from scratch multiple business-critical Rust SDKs… It is a personal hobby project from the beginning, but it is also used in my current company." So: used in production by the author's team at ByteDance, but framed as a personal project, not an official ByteDance product or endorsement. No other production users named in issues. |

Extra verified facts (beyond SPEC claims):

- License is dual MIT/Apache-2.0 BUT the MIT file has one modified sentence (issue #99 thread).
- Runtime requires `GODEBUG=invalidptr=0,cgocheck=0`.
- Platforms: linux/macOS/windows; ASM on amd64/arm64; shm unix-only.
- Toolchains: Go >= 1.18 (`--go118` for 1.18/1.19), Rust >= 1.75 for async.

## What Hybrid should extract (specific techniques for our Go/Rust interop language)

1. **Rust-source-as-IDL**: the most transferable decision — no protobuf/IDL DSL; a restricted
   Rust file IS the contract, parsed by syn into IR, emitted to Go. Hybrid should do the same
   with its own surface syntax: one definition site, two generated sides, plus committed
   generated files + CI freshness diff (`docs/ci.md`: `git diff --exit-code -- '**/gen.go'`).
2. **Ref-struct ABI**: mirror each cross-language struct into a `#[repr(C)]` Ref twin where
   `String`→`StringRef{ptr,len}` and `Vec<T>`→`ListRef{ptr,len}`, primitives inline. This is
   the zero-copy wire format — simple enough to standardize inside Hybrid's compiler.
3. **One-allocation flattening**: the `ToRef::to_size` → `to_ref(&mut Writer)` two-pass scheme
   precomputes the exact buffer size for nested containers and writes intermediate refs into
   one flat buffer — copy `rust2go-convert/src/convert.rs`'s `MemType::{Primitive, Complex}`
   classification wholesale.
4. **Atomic-slot async completion**: the slot (3-bit AtomicU8 + MaybeUninit + waker) is a
   clean per-call design with provable drop-safety on both sides. Note what rust2go could NOT
   solve in the type system: cancellation safety leaks to users as `unsafe` +
   `#[drop_safe]` ownership requirements. Hybrid's language-level async across FFI should OWN
   this problem (always move owned params into the slot, or generate cancellation handlers).
5. **asmcall over cgo for callbacks**: hand-written amd64/arm64 trampolines doing ABI
   conversion + g0 stack switch give ~12x cheaper calls than cgo (29.19→2.324 ns). Keep it,
   but keep the `#[cgo_callback]` escape hatch — the ASM path is where platform bugs live
   (macOS/arm64 SPWRITE traceback #49; an arm64 LR-clobber bug invisible on amd64 CI).
6. **mem-ring as opt-in fast lane**: SPSC shared ring + socketpair wakeup + per-side slabs +
   CALL/REPLY/DROP protocol is a complete blueprint for a channel-based transport mode
   ("Hybrid channels") for high-frequency streams, with `ants.MultiPool` on the Go side.
   The "intentionally leak handlers for process lifetime" tradeoff in `init_mem_ffi` is an
   honest pattern for singleton runtimes.
7. **Stateful object registry**: `OnceLock<Arc<dyn Trait + Send + Sync>>` + `register()` is
   direct prior art for "Rust objects callable from Go", including the fail-fast abort when
   startup ordering is wrong.
8. **Builder-in-build.rs one-command story**: `cargo build` triggering `go build` + bindgen +
   link, with the header-mtime restoration trick and `with_regen` freshness. Hybrid's "one
   build command" goal is exactly this shape — but see Failure modes for cross-compile caveats.
9. **Single source-of-truth type table**: `rust2go-convert/src/primitive.rs`'s `PRIMITIVES`
   macro-table drives both emitters and convert impls ("cannot drift apart"). Hybrid should
   have one such table (Rust type | C ABI type | Go type | converter policy) at its heart.
10. **Engineering hygiene worth stealing**: spanned `syn::Error` diagnostics instead of
    panics; `compile_error!` for mutually exclusive features; weak-symbol stubs for standalone
    per-language CI builds; per-ISA test legs; conditional imports in generated Go.

## Failure modes / lessons (cross-compilation and cgo pain)

- **Cross-compilation is the #1 pain**: `build.rs` shells out to the HOST `go build` and to
  bindgen (needs libclang), while cgo needs a matching C cross-toolchain. Concrete issues:
  - #151: aarch64-apple-ios-sim fails with current bindgen (2026-03)
  - #73: Windows 11 ARM64 cross-build from macOS host (2025-04)
  - #59: plain Windows 11 compile failures (2025-01)
  - #108: musl unsupported ("is there a plan to support it?", 2025-08)
  - No in-repo cross-compilation docs — the story is effectively "build on the target OS".
  Hybrid must generate both sides from one IR (never host-run bindgen on a foreign header)
  and treat target-triple-aware Go+C toolchain orchestration as first-class from day one.
- **Runtime checks must be disabled**: `GODEBUG=invalidptr=0,cgocheck=0` is mandatory
  (#92: empty `Vec`'s `NonNull::dangling()` trips Go's invalid-pointer check; #109 asks when
  it's needed). This weakens Go's safety net process-wide — a real cost of sharing raw
  pointers. Designing the ABI to never hand Go a dangling pointer (null for empty) fixes it.
- **Type-system ceiling**: no enums (#43), no maps (#96), no cyclic structures (#71),
  `Option<T>` encoded as empty list (lossy), generic structs silently skipped. Users hit
  these walls with no story. Hybrid needs a closed but COMPLETE algebraic data model.
- **Hand-written assembly is a maintenance magnet**: per-ISA, per-OS, per-Go-version
  trampolines; shipped arm64 bug invisible on amd64; macOS traceback complaints (#49).
  If we adopt ASM calls we need rust2go's fallback+per-ISA CI discipline, or stay on cgo.
- **Async cancellation-safety surfaced as `unsafe`**: plain async calls default to `unsafe`
  because a dropped future can invalidate reference params; safety is opt-in via attributes
  constraining ownership. A language-level design should make the safe mode the DEFAULT.
- **Memory-safety footguns still reach users**: #119 (Chinese, macOS M4): "Rust calls a Go
  method, the data memory is already freed before execution finishes" — reference params
  plus goroutine lifetime is genuinely hard to hold correctly in user code.
- **License footgun**: one added sentence in LICENSE-MIT → GitHub NOASSERTION, user doubt
  about (A)GPL compatibility, and a maintainer clarification thread (#99). Keep license
  files verbatim; put statements in README.
- **Bus factor / release discipline**: one primary author + one refactor contributor;
  tags/1.0 requests (#98, #118) still open. Adoption is capped by the architecture itself:
  linking Go into a Rust binary requires the Go toolchain inside a Cargo build, which is
  hostile to `cargo install` of downstream crates.

## Licensing (license, compatibility with dual MIT/Apache-2.0)

- Declared: dual `MIT/Apache-2.0` (`Cargo.toml`).
- `LICENSE-APACHE`: verbatim Apache-2.0. Clean.
- `LICENSE-MIT`: MIT **plus one extra sentence** — "People who habitually steal code are
  prohibited from using it." Hence GitHub's `NOASSERTION` license detection.
- Maintainer's position (issue #99, 2025-07-26): "merely a reminder to comply with the terms
  of the open-source license and does not alter the license itself," added after repeated
  license-notice-stripping plagiarism by one individual; the reporter stayed unconvinced the
  file remains valid MIT without legal review; closed 2026-08-23 as "answered".
- Compatibility with our dual MIT/Apache-2.0:
  - borrowing IDEAS/algorithms: unambiguously fine
  - copying CODE verbatim would import the modified MIT text; the dual licensing means the
    Apache-2.0 grant is independently available and its terms are clean — prefer that route
    (or rewrite) if we lift e.g. slot or convert logic
  - our repo keeps verbatim dual MIT/Apache-2.0; no conflict as long as we do not propagate
    their modified MIT file or present it as standard MIT

## Verdict for Go-Hybrid (one paragraph)

**Borrow ideas aggressively; do not fork or depend on it as a component.** rust2go is the strongest prior art for the *mechanics* of Go↔Rust interop — its Ref-struct ABI, one-allocation flattening, atomic-slot futures, asmcall trampolines, shared-memory ring, build.rs-driven one-command build, and Rust-as-IDL philosophy map almost one-to-one onto Hybrid's needs, and its issue tracker is a curated list of exactly the landmines (cross-compilation, GODEBUG, dangling pointers, cancellation safety, type-system ceiling) that our language must design away rather than document. But it is a library-shaped FFI framework with an `unsafe`-heavy surface, a closed 14-primitive type universe, a modified-MIT license oddity, and a Go-toolchain-inside-Cargo architecture that our compiler-front-end approach supersedes; forking it would also inherit its cgo/bindgen/cross-compile debt wholesale. Hybrid should study `rust2go-convert`, `slot.rs`, `mem-ring`, and the emitter layering as blueprints, reimplement the chosen mechanisms inside our compiler with safe-by-default semantics, and credit ihciah's design blog in our docs.
