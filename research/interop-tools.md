# C/C++ interop generation tools — research note (Task 4-c)

## Identity / project matrix

| repo | role | license | activity (2026-10-11) | status |
|---|---|---|---|---|
| [dtolnay/cxx](https://github.com/dtolnay/cxx) | Safe Rust↔C++ FFI: `#[cxx::bridge]` IDL + paired code generators | **MIT OR Apache-2.0** (repo carries `LICENSE-MIT` + `LICENSE-APACHE`; README dual-license notice) | 6,843 stars; pushed 2026-10-11; 196 open issues | Very active; 1.0+ on crates.io; requires rustc 1.88+ |
| [google/crubit](https://github.com/google/crubit) | Bidirectional C++↔Rust bindings generator (Clang + rustc front ends) | **Apache-2.0 WITH LLVM exception** (`LICENSE` header: "The Crubit project is under the Apache License v2.0 with LLVM Exceptions") | 1,128 stars; pushed 2026-10-11; 218 open issues | Active (Google team); still pre-1.0, Bazel/monorepo-centric, mid-pivot to an IDL core |
| [immunant/c2rust](https://github.com/immunant/c2rust) | C→Rust *transpiler* (migrate whole C programs to unsafe Rust, then refactor) | **BSD-3-Clause** (`LICENSE`, © Galois/Immunant 2017–2019) | 4,817 stars; pushed 2026-10-10; 404 open issues | Active; requires LLVM 15+ and a pinned nightly rustc (README badge) |
| [jameysharp/corrode](https://github.com/jameysharp/corrode) | C→Rust AST-level translator (Haskell) | **GPL-2.0** (`LICENSE`) | 2,188 stars; **not archived per API today**, but last commit 2017-04-12, last push 2019-03-10 | Dormant ~8 years; often described as archived; effectively dead |

## What it actually is (verified)

**CXX** — "a **safe** mechanism for calling C++ code from Rust and Rust code
from C++" (README). The user writes one `#[cxx::bridge] mod ffi { … }` in
Rust containing the *entire* picture of the boundary: shared structs, opaque
types (`type BlobstoreClient;`), and functions in `extern "Rust"` /
`unsafe extern "C++"` blocks. From that single definition a Rust procedural
macro generates the Rust side, and `cxx-build` (or a CLI for
Bazel/Buck) generates the matching C++ header/source with static assertions.
The safety story is explicit: "auditing just the C++ side would be sufficient
… the Rust side can be 100% safe", and the mechanism is *owning both sides
of the boundary* — "Ordinarily in Rust writing your own `extern "C"` blocks
is unsafe because the Rust compiler has no way to know whether the
signatures you've written actually match … With CXX … we know what's on the
other side." The bridge is zero-overhead ("no copying, no serialization, no
memory allocation, no runtime checks").

**Crubit** — Google's "bidirectional bindings generator for C++ and Rust,
with the goal of integrating the C++ and Rust ecosystems" (README). Two
tools: `rs_bindings_from_cc/` (a **Clang AST consumer** —
`rs_bindings_from_cc/ast_consumer.cc` — that generates Rust bindings from
C++ headers) and `cc_bindings_from_rs/` (uses the **rustc** front end to
generate C++ headers from Rust). Its own status page rates what is ABI-
compatible vs layout-compatible vs bridged per type, and — crucially for us —
its 2026 direction section says: "we are building Crubit up to be a tool
shaped like OSS users expect: **an IDL-based FFI tool with Cargo
integration** … An IDL-based core, with optional compiler integration at the
front-end" and "rs_bindings_from_idl and idl_from_cc exist, and Crubit can be
used with IDL inputs" (`docs/overview/status.md`, "Usage outside of Google").

**c2rust** — a *migration* tool, not a bindings tool. "The transpiler …
produces unsafe Rust code that closely mirrors the input C code. The primary
goal of the transpiler is to preserve functionality" (README). The README's
own diagram shows the pipeline: `c2rust transpile` → `c2rust refactor` →
`c2rust postprocess` (LLM-powered, validated) → human/agentic step → "Safe,
idiomatic Rust". It also ships `c2rust-analyze` (adds borrow-region safety
annotations via rustc dataflow + Polonius; "currently at a prototype stage …
only apply to a small subset of unsafe Rust") and `cross-checks/` (dynamic
instrumentation verifying translated code against the original).

**Corrode** — "This program reads a C source file and prints an equivalent
module in Rust syntax … This tool does not fully automate the job because
**its output is only as safe as the input was**" (README). A literate-Haskell
codebase (`Main.lhs`, `src/Language/Rust/Corrode/C.lhs`) that maps the
`language-c` AST onto its own Rust AST and pretty-prints. No semantic
ownership/aliasing analysis — pointers become raw pointers, everything sits
in `unsafe`.

## Architecture / design (with file-path evidence)

- **CXX**: interface definition lives in Rust syntax and is parsed by the
  proc macro in `macro/` + `syntax/`; the "builtin types" contract is the
  `include/cxx.h` header (the `rust::` C++ namespace) plus `src/` (runtime
  types like `UniquePtr`, `CxxString`). Restriction table is in the README
  ("Builtin types"): `CxxString` "cannot be passed by value";
  `&[T]` "cannot hold opaque C++ type"; `Result<T>` "throw/catch — allowed
  as return type only"; raw pointers force the function to be `unsafe`;
  shared enums "only C-like … unit variants are currently supported"
  (`book/src/shared.md`). Notably the same table lists **`Option<T>` under
  "intended to be supported 'soon' … but just not implemented yet"** —
  the row is literally `Option<T> | tbd`.
- **Crubit**: `rs_bindings_from_cc/ast_consumer.cc` + `ast_convert.cc`
  (Clang front end) and `cc_bindings_from_rs/` (rustc front end) generate
  against `common/` libraries. Key docs: `docs/overview/status.md`
  (type-compat matrix), `docs/overview/limits.md` ("many years away from
  feature-completeness"), `docs/overview/panics_and_exceptions.md`
  ("Crubit currently requires `-fno-exceptions`, and converts unwinding
  panics into aborts"), `docs/overview/reference_safety.md` (Rust-reference
  UB rules restated for C++: "C++ mutating values referenced by Rust is
  UB … lifetime annotations of C++ APIs are not verified by the C++
  compiler"), `docs/types/non_rust_movable/` (C++ types whose bits can't be
  relocated are exposed via a `Ctor<Output=T>` in-place-construction trait —
  a pinned/lazy-init pattern).
- **c2rust**: `c2rust-ast-exporter/src/AstExporter.cpp` (C++/Clang) exports
  the C AST as **CBOR** (`src/clang_ast.rs`, `serde_cbor`; `docs/
  source_walkthrough.md`: "The exporter exports the AST using CBOR");
  `c2rust-transpile/src/c_ast/` rebuilds a `TypedAstContext`;
  `c2rust-transpile/src/translator/` emits Rust via `c2rust-ast-builder`.
  So the pipeline is: *front end → serialized descriptor → generator*, with
  the descriptor in a language-neutral binary format.
- **Corrode**: `src/Language/Rust/Corrode/C.lhs` — "For both C and Rust
  source we use an abstract representation rather than the raw source text.
  The C representation comes from the `language-c` package, and the Rust
  representation is in Corrode's `Language.Rust.AST` module." Pure AST→AST
  mapping, single translation unit at a time (`CrateMap.hs` for multi-file).

## The claims check

| claim (SPEC.md:190) | verdict | evidence |
|---|---|---|
| "CXX … limits on representing `Option`" | **CONFIRMED** | CXX README "Builtin types" table: `Option<T>` appears only in the "intended to be supported 'soon'" list — row reads `Option<T> | tbd`. Workaround culture: users pass `*mut T`/len pairs or model presence with `Vec`/`Result`. |
| "Crubit … limits on representing `Option`, ownership" | **CORRECTED (refined)** | Crubit *does* represent Option: `docs/overview/status.md` type matrix maps `std::optional<T>` ↔ `Option<T>` as **"Bridged"** with a TODO that `cpp_std::optional<T>` is not yet layout-compatible, and Rust `Option<T>` → `rs_std::Option<T>` in C++ as **layout compatible**. The real Crubit limits are elsewhere: `-fno-exceptions` + panics→abort; unverified C++ lifetime annotations; non-Rust-movable types needing `Ctor`; generic/template functions not automated (`docs/overview/limits.md`). |
| "… ownership" limits across the boundary | **CONFIRMED (both tools, differently)** | CXX encodes ownership via *builtin smart-pointer pairings only* (`Box↔rust::Box`, `UniquePtr↔std::unique_ptr`, `SharedPtr↔std::shared_ptr`) each with "cannot hold opaque X type" restrictions (README table); Crubit encodes it via reference-safety rules that are *conventions* the C++ compiler cannot check (`docs/overview/reference_safety.md`). |
| "Corrode/c2rust on why syntax-level translation yields unsafe output" | **CONFIRMED** | c2rust README: output is "unsafe and unidiomatic; it is merely the first step in a longer migration process"; Corrode README: "its output is only as safe as the input was". Root cause verified: C carries no aliasing/ownership/lifetime information, so a semantics-preserving translator must emit raw pointers and `unsafe` blocks; recovering safety requires *additional analysis* (c2rust-analyze + Polonius, "prototype stage") or human/LLM refactoring. |

## What Hybrid should extract (concrete techniques)

1. **One bridge definition, two paired generators, both sides owned**
   (CXX). This is the single most transferable idea: Hybrid's
   `interfaces/` descriptors should be the *only* place the boundary is
   described, and the Go and Rust generators must both consume it, emit
   matching symbols, **and embed static assertions** (CXX: "static
   assertions for later in the build process to verify correctness") so
   drift fails the build, not the user.
2. **Compile-time rejection of unsupported types** (CXX). CXX's proc macro
   errors on anything outside the builtin table instead of guessing. Hybrid's
   descriptor validator should do the same: a closed type universe with
   per-type restrictions, checked before codegen.
3. **A three-level compatibility taxonomy** (Crubit): *ABI-compatible*
   (identical machine-level calling convention), *layout-compatible* (same
   field layout, different call treatment), *bridged* (requires conversion
   code). Hybrid's descriptor schema should tag every boundary type with one
   of these; it forces honest codegen decisions (e.g. Go `string` vs Rust
   `String` vs `&str` are *bridged*, not layout-compatible, once NUL
   termination or interior-pointer rules differ).
4. **A serialized, language-neutral descriptor format** (c2rust): front end
   → CBOR/JSON descriptor → generator. c2rust proves a Clang front end can
   hand off to a Rust generator through a serialized AST; Hybrid should
   place `rustdoc`-JSON (or `rmeta`-derived) descriptions into an equivalent
   descriptor so the Go-side generator never invokes cargo/rustc during
   codegen.
5. **Error taxonomy as documentation** (Crubit `docs/errors/*.md`: one page
   per boundary failure class — `unsupported_type`, `nested_type`,
   `bridge_compound_type`…). Cheap to copy, enormous UX payoff for a new
   language.
6. **Exceptions/panics policy decided up front** (both): CXX maps
   `Result<T>` (return-position only) to throw/catch; Crubit forbids
   exceptions and aborts on unwind. Hybrid must pick one story *before*
   writing the ABI — our analog is Go panic ↔ Rust panic/result at the
   boundary, and both projects show "abort at the boundary" is the only
   zero-cost sound default.
7. **The bindgen#778 lesson** (CXX README): two structs with identical
   layout can still have a different *ABI* when passed by value (a
   longstanding bindgen bug causing "segfaults in absolutely
   correct-looking code"). CXX fixes it "by owning both sides of the
   boundary". Hybrid should pass boundary structs by reference (or via an
   out-param + status) rather than by value, wherever possible.

## Failure modes / lessons

- **`Option<T>` is genuinely hard at an FFI seam**: the safe Rust
  `Option<&T>` niche optimization, C++ `std::optional`'s separately-stored
  engaged flag, and Go's nil pointers have three different layouts. CXX
  punted ("tbd"); Crubit spent years bridging it. Hybrid should treat
  optional/result as *bridged* types with explicit, generated conversion —
  never as a layout assumption.
- **Semantic translation ≠ safety** (c2rust, Corrode): both projects'
  histories show that preserving C semantics yields unsafe Rust, and that
  the expensive part is the *after* analysis (Polonius can take "several
  minutes … on very large functions" — `c2rust-analyze/README.md`). Hybrid's
  promise ("Rust-grade safety incrementally") must come from a *designed*
   boundary, not from translating legacy code.
- **Front-end coupling kills portability** (Crubit): depending on exact
   Clang/rustc internals tied users to Google's monorepo; the fix — an IDL
   core decoupled from compilers — is exactly the direction Hybrid's
   descriptor schema should take from day one.
- **Dormancy risk** (Corrode): GPL-2.0, single maintainer, dead since 2017.
  Hybrid should only *depend* on tools with institutional backing (CXX
  → dtolnay + 1.0 stability; c2rust → Immunant) or vendor the design ideas.

## Licensing (compat with dual MIT/Apache-2.0)

- **CXX: MIT OR Apache-2.0** — identical to our dual license; we may vendor
  or copy code with attribution.
- **Crubit: Apache-2.0 with LLVM exception** — the exception only *adds*
  rights (notably for static linking); compatible with our Apache-2.0 side
  and effectively with MIT relicensing of derived code under the dual
  scheme. No copyleft.
- **c2rust: BSD-3-Clause** — permissive, compatible; retain notices.
- **Corrode: GPL-2.0** — **incompatible** with MIT/Apache-2.0 code reuse.
  Corrode is reference-only for us: read the design, never copy code. (Its
  ideas — AST→AST mapping — are not copyrightable, but lines of Haskell
  would be.)

## Verdict for Go-Hybrid

The four projects triangulate one conclusion: **successful C/C++↔Rust
interop is generated from a single, closed, validated interface description
by paired generators that own both sides — and anything short of that
(translate-and-hope, or hand-written extern blocks) is either unsafe or
unmaintainable.** CXX contributes the bridge-DSL + static-assertion
philosophy and the honest builtin-restriction table; Crubit contributes the
ABI/layout/bridged taxonomy, the reference-safety rulebook, and — via its
own IDL pivot — external validation that Hybrid's descriptor-schema
architecture is where the industry is heading; c2rust contributes the
serialized-descriptor pipeline shape and the sobering economics of
post-hoc safety analysis; Corrode contributes the cautionary tale (and a
GPL-2.0 fence we must not cross). **Recommendation**: model Hybrid's
boundary layer on CXX's structure (one descriptor, two generators, build-
failing assertions), adopt Crubit's three-level compat tags in our
descriptor schema, treat `Option`/`Result`/`String` as bridged types with
generated conversions, and codify "panics abort at the boundary" now.
