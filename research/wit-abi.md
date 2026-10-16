# WASM Component Model / WIT — research note (Task 4-c)

## Identity / project matrix

| repo | role | license | activity (2026-10-11) | status |
|---|---|---|---|---|
| [WebAssembly/component-model](https://github.com/WebAssembly/component-model) | Design + spec repo for the Component Model and WIT (`design/mvp/WIT.md`, `CanonicalABI.md`, `Binary.md`, `Linking.md`, `Concurrency.md` + WAST test suite) | Apache-2.0 (repo `LICENSE`: "all files are licensed under Apache 2.0" unless a subdir says otherwise) | 1,380 stars; pushed 2026-10-07 | Active; W3C WebAssembly CG; WASI Developer Preview 0.2.0 / 0.3.0 / 0.3.1 milestones |
| [bytecodealliance/wasmtime](https://github.com/bytecodealliance/wasmtime) | Production runtime implementing the Component Model (host side) | Apache-2.0 (API); repo license is Apache-2.0 with LLVM exception | 18,712 stars; pushed 2026-10-11 | Active, very mature |
| [bytecodealliance/wit-bindgen](https://github.com/bytecodealliance/wit-bindgen) | Guest-language bindings generator for WIT (Rust, C, C++, C#, Go + others) | **MIT OR Apache-2.0-with-LLVM-exception** (`LICENSE-MIT`, `LICENSE-APACHE`, `LICENSE-Apache-2.0_WITH_LLVM-exception`) | 1,469 stars; pushed 2026-10-08 | Active |
| (supporting) [bytecodealliance/wasm-tools](https://github.com/bytecodealliance/wasm-tools) | `wit-parser`, `wit-component` libraries — the reusable WIT front end Hybrid would consume | MIT OR Apache-2.0 w/ LLVM exception (API reports Apache-2.0) | 1,800 stars; pushed 2026-10-09 | Active |

Not cloned: wasmtime (165 MB) — directory listing of
`crates/wasmtime/src/runtime/component/` fetched via the GitHub contents API
instead (see below). component-model and wit-bindgen were shallow-cloned to
`/tmp` and removed after study.

## What it actually is (verified)

The Component Model (CM) is a standardization effort to let
independently-compiled "components" interoperate with *typed*, structured
interfaces instead of raw linear-memory + integer-only core WASM imports.
WIT (Wasm Interface Type language) is its interface-definition language;
the Canonical ABI defines exactly how WIT-typed values lower to core wasm
values and memory. The repo README frames it: "high-level goals, use cases,
design choices and FAQ docs; low-level WIT, text format, binary format,
linking, concurrency and ABI docs; a growing WAST test suite", developed
under the W3C WebAssembly Community Group. Milestones: 0.2.0 brought
"shared-nothing and shared-everything linking, a variety of high-level value
types, `resource` types with handles, and WIT"; 0.3.0 added native
concurrency (`async` functions, `stream`s, `future`s); 0.3.1 added
`map<K,V>` and `implements`/`external-id` annotations.

`wit-bindgen` is "a suite of bindings generators for languages that are
compiled to WebAssembly and use the component model. Bindings are described
with `*.wit` files which specify imports, exports, and facilitate reuse
between bindings definitions" (README). It is guest-focused (Rust, C, C++,
C#, Go in-tree; more external), and its README has an explicit **"WIT as an
IDL"** section — the framing our task asks about. The Go generator
(`crates/go/`) emits `//go:export` entrypoints plus typed packages, and
leans on `go.bytecodealliance.org/pkg/wit` for runtime support; its README
recommends `componentize-go` (which builds on TinyGo) as the easy path, and
notes async "currently requires a patched version of" the toolchain.

Wasmtime is the existence proof that the model runs in production: the
contents API lists `crates/wasmtime/src/runtime/component/` with
`resource_table.rs`, `resources.rs`, `values.rs`, `types.rs`, `func/`,
`concurrent/` — i.e. the Canonical ABI (lifting/lowering, resource tables,
type checking) is implemented as ordinary Rust, not magic.

## Architecture / design (with file-path evidence)

**The WIT type universe** — `design/mvp/WIT.md` lines ~1883–1910 give the
EBNF:

```ebnf
ty ::= 'u8'|'u16'|'u32'|'u64' | 's8'|'s16'|'s32'|'s64'
     | 'f32' | 'f64' | 'char' | 'bool' | 'string'
     | tuple | list | option | result | map | handle | future | stream | id
```

plus named `record` (structs), `variant` (tagged unions), `enum`, `flags`
(bitflags), `type` aliases, `interface`s and `world`s. Deliberately absent:
user generics, function pointers (modeled as resources instead), untagged
unions, inheritance, recursion. `option<T>` and `result<T,E>` are builtin,
not library types.

**`borrow` vs `own`** — `design/mvp/WIT.md` ("Handles", ~line 1976):
"There are two types of handles in Wit: 'owned' handles and 'borrowed'
handles. **Owned handles represent the passing of unique ownership of a
resource between two components. When the owner of an owned handle drops
that handle, the resource is destroyed.** In contrast, **a borrowed handle
represents a temporary loan of a handle from the caller to the callee for
the duration of the call.**" The default spelling of a resource type
(`blob`) is the owned handle; `borrow<blob>` is the loan. Methods desugar
to a `self: borrow<…>` first parameter and constructors return an owned
handle (documented with the full desugaring table around line 1800–1855).
The `%method]foo.read` naming scheme exists specifically "so that bindings
generators can generate idiomatic syntax for the target language or (for
languages like C) fall back to an appropriately-prefixed free function
name."

**Canonical ABI lowering** — `design/mvp/CanonicalABI.md` (executable
Python): `MAX_FLAT_PARAMS = 16`, `MAX_FLAT_RESULTS = 1`; beyond that,
values pass through memory via a single pointer. `flatten_type` maps:
bool/ints≤32/char → `i32`; 64-bit ints → `i64`; floats → `f32/f64`;
`string` → `(ptr, len)`; `OwnType() | BorrowType()` → **a single `i32`**
(a table index); variants flatten to a discriminant + the `join` of payload
types; `option<T>` is the 2-case variant `variant { none, some(T) }`.
Handles live in a per-instance table: `class ResourceHandle: rt: ResourceType;
rep: int; own: bool; borrow_scope; num_lends` — i.e. an indexable,
refcount-ish registry that tracks lends per call scope. Host-side
equivalent: wasmtime's `resource_table.rs`.

**Tooling split**: `wit-bindgen` generates *guest* code from
`wit_bindgen_core::abi` instructions + `wit-parser` (pinned `wit-parser =
"0.261.0"` in `Cargo.toml`) — the same parser libraries that live in
wasm-tools, so **parsing WIT is a solved, reusable, permissively-licensed
library problem** (`wit_parser::{Resolve, Interface, World, Type…}` are
imported directly by `crates/go/src/lib.rs`).

## The claims check

| claim (SPEC.md:191) | verdict | evidence |
|---|---|---|
| "WASM component model / WIT: language-neutral interface definitions" | **CONFIRMED** | WIT is explicitly an IDL: wit-bindgen README section "WIT as an IDL" ("All imports into a WebAssembly binary and all exports must be described with WIT"); in-tree generators for Rust, C, C++, C#, Go; external ones for more languages; TinyGo's own WASI P2 stdlib is generated from WIT (`src/internal/wasi/.../random.wasm.go`: "Code generated by wit-bindgen-go. DO NOT EDIT."). |
| "Whether it can serve as the shared ABI/type description layer" | **CONFIRMED as a type/IDL model; CORRECTED as a literal ABI** | The *type system + handle semantics + world/import-export structure* are runtime-independent and directly reusable. The *Canonical ABI*, however, is defined against core-WASM primitives — linear memory, `(ptr,len)` string pairs, i32 handle tables, MAX_FLAT_* register conventions — none of which exist in a native Go↔Rust link. A native Hybrid must re-lower WIT-shaped types onto the C ABI (SysV) itself; WIT gives the semantics, not the machine convention. |

## What Hybrid should extract (concrete techniques)

1. **Adopt the WIT type universe as the boundary type grammar.** It is
   small, total, and every case has defined lowering semantics: integers,
   floats, `char` (Unicode scalar), `bool`, `string`, `tuple`, `list`,
   `option`, `result`, `map`, `record`, `variant`, `enum`, `flags`, plus
   opaque resources. This is precisely the closed universe CXX keeps and
   Crubit documents — but WIT's version is already written down as EBNF
   with lowering rules, and `wit-parser` will parse it for us (Apache-2.0
   w/ exception / MIT).
2. **Adopt `own` vs `borrow` as the *only* ownership vocabulary at the
   boundary.** Own = transfer + destructor-on-drop; borrow = scoped loan
   valid for the duration of one call. This maps cleanly onto Go→Rust
   (`*T` handoff vs `&[u8]` argument) and, more importantly, onto Rust's
   move semantics — and it is teachable in one paragraph, unlike Rust's
   full lifetime system.
3. **Adopt `world` = imports + exports as the unit of checking.** A Hybrid
   "world" (one module's foreign contract) lets the build verify both sides
   agree before link time — same role as CXX's paired generators, but with a
   standardized shape.
4. **Keep a handle table for resources, exactly like the Canonical ABI.**
   `ResourceHandle { rt, rep, own, borrow_scope, num_lends }` + i32 index
   is a concrete, implemented design for owning opaque objects across a
   boundary *without* sharing layout — and wasmtime's `resource_table.rs`
   shows the host-side bookkeeping. Hybrid's Go side can use exactly this
   to hand Go objects to Rust (and vice versa) as indices, not pointers.
5. **Copy the flattening discipline, not the flattening targets.**
   MAX_FLAT_PARAMS=16 / MAX_FLAT_RESULTS=1 with a memory fallback, the
   variant discriminant + payload-join rule, and string-as-(ptr,len) are
   sound engineering; re-target them at the C ABI (first aggregate by
   value → pointer to caller-allocated out-space, etc.).
6. **Reuse the tooling chain, not the runtime.** `wit-parser` (parse),
   wit-bindgen's `abi::Instruction` design (a *lowering program* the
   generator walks) — see `crates/go/src/lib.rs` imports — and the
   generated-code file layout (`<name>/wit_bindings.go` +
   `export_<name>/…`) are all directly borrowable for Hybrid's generators.

## Failure modes / lessons

- **The Canonical ABI assumes linear memory.** Naively "implementing WIT"
  for native code doesn't exist; the spec's lowering rules
  (realloc/`opts.memory`, string re-encoding between UTF-8/UTF-16) are all
  memory-copy shaped. Hybrid must define its own native lowering and own
  the compatibility risk of that choice.
- **Borrow discipline is a convention + runtime bookkeeping, not a proof.**
  WIT borrows are enforced by table `num_lends` counters and scoping in the
  runtime, not by a checker — a misbehaving callee can still misuse a
  borrowed handle. Hybrid should pair the same convention with generated
  debug-mode assertions (lend-count checks on the Go side) rather than
  trust it.
- **Spec churn is real**: features are literally emoji-gated in the docs
  (📡 getters/setters, 🔀 async, 🗺️ map, 🧵 threads) and the README labels
  everything "WASI Developer Preview". Hybrid should pin one milestone
  (0.2.x subset is the stablest: no async, no map) and ignore the rest.
- **Async ties you to WASM semantics**: 0.3.0's streams/futures/backpressure
  model assumes a cooperative wasm runtime; wit-bindgen's Go async support
  "requires a patched version of" the Go toolchain (crates/go README) —
  a warning against importing the concurrency story into a native ABI.
- **Two-tool ecosystem fragmentation**: wit-bindgen vs wasm-tools vs
  per-language forks (wit-bindgen-go moved around historically). Depending
  on *libraries* (`wit-parser`) rather than *CLIs* insulates Hybrid.

## Licensing (compat with dual MIT/Apache-2.0)

- **component-model: Apache-2.0** — docs/spec text is Apache-2.0; compatible
  (we'd be re-implementing ideas, and facts/ideas aren't copyrightable
  anyway; quoting spec tables with attribution is fine).
- **wasmtime: Apache-2.0 (with LLVM exception)** — compatible with our dual
  license.
- **wit-bindgen and wasm-tools: MIT OR Apache-2.0 with LLVM exception** —
  functionally equivalent to our dual MIT/Apache-2.0 stack; we may vendor,
  fork, and relicense `wit-parser` under either license. No copyleft
  anywhere in the chain.

## Verdict for Go-Hybrid

WIT is the strongest available answer to "what is Hybrid's shared
ABI/type-description layer?" — not because we should run WebAssembly, but
because the Component Model already did the hard intellectual work we were
about to redo: a closed cross-language type universe, an own/borrow
ownership vocabulary that both GC and non-GC languages can honor, a
world-level import/export contract, and a proven split between *parse*
(wit-parser), *describe* (WIT), and *generate* (wit-bindgen) that matches
our descriptor-schema architecture one-to-one. What we must not adopt is
the literal Canonical ABI (linear-memory lowering) and the 0.3.x async
machinery. **Recommendation**: use WIT *files* (or a JSON descriptor
isomorphic to `wit-parser`'s resolved AST) as Hybrid's interface language,
pin the 0.2.x feature subset, embed `wit-parser` as the parsing library,
and write our own "native canonical ABI" layer that lowers WIT types onto
the C calling convention with an explicit resource/handle table modeled on
`ResourceHandle` — with a WASM lowering kept as a future compile target,
exactly as TinyGo does on its Go side.

