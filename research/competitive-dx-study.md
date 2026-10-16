# Competitive DX Study — GALA / Soppo / Lisette

**Date:** 2026-10-13
**Agent:** 7-a (research-dx-study)
**Serves:** `research/positioning.md` (the human's fast-follower strategy), PLAN.md
Decision Log 2026-10-12 competitive-strategy entry, SPEC §3/§4/§7/§8, and the
Q1 human ruling (diagnostic-not-punitive, fix-it suggestions, adversarial
corpus as spec).

## Method and honesty

All three repos were shallow-cloned (`git clone --depth 1`) into
`/home/z/my-project/refs/` (study-only workspace copies, never committed):

| Repo | Clone size | HEAD commit date | Version studied | Scale (my counts) |
|---|---|---|---|---|
| `martianoff/gala` | 27 MB | 2026-10-11 | ~0.84.x (playground Dockerfile pins `GALA_VERSION=0.84.1`) | 2,249 files; ~176k lines of Go (compiler, excl. generated parser) + ~56k lines of `.gala` (stdlib+tests); 73 error codes; 95 Bazel files |
| `halcyonnouveau/soppo` | 5.8 MB | 2026-08-15 (≈2 months staler than the other two) | 0.11.1 (Cargo.toml) | 468 files; ~6.5k lines Rust compiler + ~1.8k lines LSP; 30 diagnostic codes; 137 insta snapshots; 163 `.sop` files |
| `ivov/lisette` | 63 MB | 2026-10-11 | v0.12.4 (release commit) | 6,809 files; ~167k lines Rust (non-test); **544 unique diagnostic codes**; 5,376 snapshot tests; 398 `.lis` files; 189 `.d.lis` Go-stdlib typedefs |

Plus one auxiliary clone: `martianoff/gala-playground` → `/tmp/gp`
(282-line server written in GALA itself), because GALA's playground lives in a
separate repo.

Licenses (all permissive — no barrier to copying design patterns):
GALA Apache-2.0 (README badge + LICENSE), Soppo BSD-3-Clause
(README + Cargo.toml), Lisette MIT (README badge + LICENSE), gala-playground
Apache-2.0. Code is *studied*, not vendored; patterns are re-implemented.

**Unverifiable / honestly flagged:**

- GitHub star/fork counts: API rate-limited from this sandbox (shared IP) —
  **unverified**. Activity is evidenced by HEAD commit dates instead (above).
- Lisette's "500+ diagnostics" README claim: **verified as ≥544 unique codes**
  by extracting `with_{parse,resolve,infer,lint,attribute,emit}_code("…")`
  string literals (544 unique; a handful of additional dynamic lint names from
  `IssueKind::lint_name()` push it slightly higher). See §Lisette (a).
- None of the three repos is a stub. The human's descriptions were, if
  anything, *under*-ambitious: all three are real, working compilers with
  shipped tooling. GALA and Lisette are large, actively-pushed projects.

---

## 1. GALA (github.com/martianoff/gala) — "Go, the functional way"

A statically-typed **functional-first transpiler to Go** written in Go
(~176k lines), inspired by Scala. Key files for this study:
`docs/CONCURRENCY_SAFETY.MD`, `galaerr/errors.go`, `galaerr/render.go`,
`galaerr/json.go`, `docs/errors/` (73 pages), `internal/doccheck/`,
`internal/transpiler/concurrency/`, `internal/transpiler/transformer/codec.go`,
`std/meta.gala`, `website/llms.txt`, `AGENTS.md`.

### (a) Compile-time data-race safety via immutability — HOW

The best-documented mechanism of the three (`docs/CONCURRENCY_SAFETY.MD`, 449
lines). Architecture:

1. **Rule:** only *deeply immutable* values may cross a goroutine boundary.
   GALA's immutability-by-default (`val`, immutable collections, no `nil`)
   makes the check "silent in the common case" — it fires only on
   `collection_mutable` values, `var` fields, raw Go slices/maps/pointers, and
   opaque Go-interop types.
2. **`Shareable(T)` predicate** — a pure, deep, transitive type walk that
   terminates on recursive types via a visited set
   (`internal/transpiler/concurrency/shareable.go`, 409 lines; `IsShareable`
   → `isShareable(t, visited)` with `unaliasOnce` cycle handling). **Fail
   closed:** every "I don't know" (unresolved name, opaque Go type, unbounded
   generic `T`, `any`) resolves to not-shareable. Immutable vs mutable
   collections are told apart **by package qualifier** —
   `collection_immutable.Array` vs `collection_mutable.Array` share a type
   name.
3. **Capture analysis** — closures have no type-only answer, so a separate
   syntactic pass computes free variables with lexical-scope shadowing
   (`concurrency/capture.go`, 155 lines; `Capture{Name, Pos, Paths, Whole}`).
   It records *how* each capture is used: pure `.field` read chains become
   `Paths`; anything else (bare ref, method call, index, match subject) marks
   it `Whole`. String interpolation (`s"$x"`) is a single lexer token, so the
   walk **re-parses embedded expressions** to avoid a false negative.
4. **`Sendable[F]` boundary marker** — a *transparent* type: compiles to
   exactly `F` in generated Go, zero runtime cost; its only job is to mark a
   parameter position as a goroutine boundary. The checker keys off the marker
   type, never function names — any library can declare its own boundary
   (`func runAsync[T any](body Sendable[func() T]) Future[T]`). For forwarded
   function values, `Sendable` acts like Rust's `Send` bound: a
   caller-vouches contract that **propagates up wrapper signatures and
   terminates at the closure literal** where captures are actually checked.
5. **One code for a family:** everything above rejects with **GALA-E0037**
   (`internal/transpiler/transformer/concurrency_check.go`,
   `unshareableVarCaptureError` / `unshareableValCaptureError` /
   `unshareableFieldPathCaptureError`), with per-shape messages and hints.
6. **Escape hatch:** `go_interop.Spawn` is the *unchecked* zone — parameters
   not `Sendable`, user takes responsibility (mutexes/channels/atomics).

**The field-access-sensitivity is the gem:** `Future(() =>
project(model.team, model.statuses))` is accepted when `model` has a `var
attempts` field but the closure reads only immutable fields — no snapshot
`val` needed. This is exactly the refinement Hybrid's Tier-0 checker
(A1–A8, `spikes/spike6-ownership/RESULTS.md`) will want: it keeps the strict
(c)+(b) ruling while avoiding punitive false positives on idiomatic
read-only projections. Q1's "diagnostic-not-punitive" ruling points at this
design.

### (b) Stable error codes `GALA-Exxxx` — the registry

- **Format:** `GALA-E%04d` (`galaerr/errors.go:126` onward) — 4-digit
  zero-padded, **append-only, never renumber**. 73 constants
  (`CodeNonExhaustiveMatch ErrorCode = "GALA-E0002"` …), each with a
  one-line comment. **E0016 is a retired hole** (docs dir jumps E0015→E0017)
  — append-only discipline held in practice; deletion ≠ renumbering.
- **Codes classify families, not messages:** 73 codes cover a whole compiler;
  E0037 alone covers 4 distinct rejection shapes, each with its own message
  and hint (`docs/errors/GALA-E0037.md` documents all four with *real CLI
  output captured verbatim*).
- **Every code gets a reference page:** `docs/errors/GALA-E0xxx.md` — same
  count on both sides (73 constants, 73 pages), and a CI guard asserts the
  embedded set matches what the compiler can emit
  (`docs/errors/errdocs_test.go: "the guard that asserts the embedded set
  matches what the compiler can actually emit"`).
- **Pages are embedded in the binary** via `//go:embed GALA-E*.md`
  (`docs/errors/errdocs.go:19`) — so `gala explain GALA-E0044` works
  **offline**; `gala explain --list` enumerates; `Normalize` accepts
  `GALA-E0044`, `E0044`, or `44`. The Go file lives *inside* docs/errors/
  because go:embed only reaches its own package dir — "one copy, no drift"
  (errdocs.go package comment).
- **Doc pages are TESTED:** `internal/doccheck/` compiles every code block in
  the docs in CI. Markers: `<!-- doc-check: fragment -->` (must compile) and
  `<!-- doc-check: error GALA-Exxxx -->` (must *fail with that exact code*).
  (`internal/doccheck/doc_snippets_test.go:44-48`.)
- **Two output forms, one source of truth:** terse single-line
  `SemanticError.Error()` for LSP + tests; `RenderRich` (galaerr/render.go)
  layers the framed human rendering on top — "It is intentionally CLI-only …
  hand-written ANSI, no third-party dependency". `gala build --json` emits a
  `{"diagnostics":[…]}` **envelope object, not a bare array** ("so the schema
  has somewhere to grow") with 1-based positions, `endColumn`, `hint`, and
  `docsUrl` per diagnostic (`galaerr/json.go`).

### (c) Zero-reflection JSON via `StructMeta[T]`

- `StructMeta[T]()` is **the only codec-related compiler intrinsic**
  (`internal/transpiler/transformer/codec.go:87`
  `transformStructMetaConstruction`). Call-site detection → auto-injection of
  a generated `StructMeta_X` value.
- The generated value implements a **format-neutral** interface
  (`std/meta.gala:94`): `EncodeFields(w FieldEncoder, t T, nameFn, omitFn,
  naming)` / `DecodeFields(r FieldDecoder, lookup, naming) T`. JSON and YAML
  codecs live **in the stdlib** (`std/json/codec.gala`, `yaml/`), not in the
  transpiler — "The transpiler carries no format-specific knowledge"
  (codec.go header comment).
- Placement rules are deliberate: library packages emit one exported
  `StructMeta_X` next to the struct declaration (so unexported fields can be
  encoded cross-package by the declaring package only); `main` emits
  per-file-suffixed `_StructMeta_X` on demand.
- It "doubles as a pattern-match extractor" (README) — one metadata shape,
  two uses.

### (d) The playground — architecture

Separate repo `martianoff/gala-playground` (verified by clone, `/tmp/gp`):

- **Server written in GALA itself** — `main.gala` (282 lines) using the
  `gala-server` library; the playground is compiled by GALA (dogfooding, and
  a demo of the language doing real work).
- **Runs user code on its own server**: `gala build` + `os/exec` in a fixed
  workspace dir (`/tmp/gala-playground-ws`), non-root user in the Docker
  image, deployed on Fly.io (`fly.toml`). Docker pre-warms the analysis + Go
  build caches by building all 21 built-in examples at image build time.
- 21 built-in examples; share = clipboard copy (no URL sharing).
- **Security posture is the weak point:** a fixed workspace + non-root user
  is not a sandbox for arbitrary user code. Contrast §2(d)/§3(d): Soppo and
  Lisette never run user code themselves.

### (e) Language shape — how functional is it really; what a Go developer would hate

Very functional, and deliberately un-Go in specific, documented ways
(`website/llms.txt`, "Differences that most often produce wrong code"):

- **No `defer`, no bare `go`** → `use` / `go_interop.Spawn` (GALA-E0036).
- **No slice/map literals** → `ArrayOf(1,2,3)` / `HashMapOf(("a",1))`
  (GALA-E0007/E0008).
- **No bare `len`, `append`, `make`, `panic`, `recover`** → `.Size()` /
  `.ByteSize()` (GALA-E0035).
- **Methods are capitalized** (`.Map`, `.Filter`) — `map` is a reserved word.
- **Postfix `match`** (`value match { … }`), Scala-style; monadic
  `bind`/`also` do-notation over any `FlatMap` type (docs/BIND_NOTATION.MD).
- Immutable by default (`val`); parameters/receivers immutable (reassigning a
  parameter is an error); `sealed type` ADTs with exhaustive matching
  (GALA-E0002) including nested patterns, guards, generic extractors;
  `Option`/`Either`/`Try`/`Future`/`IO` monad stack; `Immutable[T]` /
  `ConstPtr[T]`.
- Sealed-type default case = its zero value (HEAD commit
  `4754ce01`, 2026-10-11).

A Go developer gets the wishlist features (enums+exhaustiveness, no nil,
immutability) but pays in *everyday* syntax: no `defer`, no `go`, no
literals, capitalized methods, monads. This validates positioning.md's
avoid-ruling precisely: the features are separable from the functional
lifestyle. GALA's `llms.txt` is honest that these are hard errors, not lints.

**Other GALA facts relevant to Hybrid:** runtime panics report `.gala`
positions via a `//line`-directive rewrite pass
(`internal/transpiler/transpiler.go:1021` — exactly Hybrid's Spike 2
technique, including a guard that markers never leak as identifiers,
GALA-E0017); Go interop infers return types "directly from the Go SDK, no
declaration files" (README) with `(T, error)` → `Try[T]` auto-wrapping;
LSP server (`gala lsp`) + IntelliJ plugin + a Claude Code plugin
(`ide/claude-code/`); build system is **Bazel-only** (95 BUILD files,
MODULE.bazel, Bazelisk required to build from source — high contributor
friction); `gala.mod`/`gala mod tidy` reimplement module management for GALA
deps (go-git backed, `internal/depman/fetch/git.go`); AGENTS.md codifies
agent discipline ("NEVER weaken a check to get green", "no internal ticket
IDs" CI-enforced, generated-parser CI guard, "no special treatment for std"
— stdlib imports resolve through the same mechanism as user code).

---

## 2. Soppo (github.com/halcyonnouveau/soppo)

A Go-syntax-preserving transpiler to Go, written in Rust (~6.5k lines) with
`match` replacing `switch`, nil-safety, `?` propagation. Cargo.toml
self-describes as "a Go superset with enums, pattern matching, and nil
safety". Key files: `README.md`, `docs/guide.md` (445 lines), `src/error.rs`,
`src/doctest.rs`, `lsp/src/lib.rs`, `Dockerfile.playground`,
`www/playground/src/routes/api/compile/+server.ts`, `CHANGELOG.md`,
`release-plz.toml`.

### (a) "If you know Go, you know most of Soppo" — what syntax actually shares

README line 5, verbatim. The share is real and broad (docs/guide.md
"Principles": "Reuse Go syntax where it exists"):

- Same package/import system (Go import paths, aliases, dot imports,
  grouped imports); **`go.mod` is still required**; `sop.mod` is only a
  config file (include/exclude globs, output dir).
- Same declarations: `func`, `type … struct`, `var`/`:=`/`const`, methods
  with receivers, generics with `[T any]`, interfaces satisfied structurally.
- Enum syntax is Go-shaped: `type Colour enum { Red; Green; Blue }` with
  unit/data/struct/generic variants; **variant destructuring via type
  assertion**: `shape.(Shape.Circle)` and comma-ok `if c, ok :=
  shape.(Shape.Circle); ok` — a genuinely Go-native pattern-match idiom (the
  compiler tracks known variants and allows direct assertion without comma-ok).
- Added-but-Go-flavored: `match` (keeps `case`/`default`, adds
  destructuring), `?` postfix operator (note: **space before `?`**, "not like
  Rust"), `?*T` nilable annotations, runtime `const`, named arguments,
  `{name}` interpolation with Go fmt verbs (`{num:08d}` — compiler-checked),
  attributes `[Attr{…}]` (type-checked structs usable as metadata, discoverable
  via a `runtime` package).

### (b) Rust-inspired diagnostics — format and code

- Built on **miette** (`Cargo.toml: miette 7.6 "fancy"`) + thiserror.
  `src/error.rs` (409 lines) defines the full diagnostic enum with
  `#[diagnostic(code(soppo::…), help("…"))]` and `#[label("…")]` spans, plus
  `url(...)` links into the tour for some codes (e.g.
  `soppo::unsupported_switch` → tour.soppolang.dev/match).
- **30 diagnostic codes total** (my count of `code(soppo::…)` literals) —
  namespaced snake_case (`soppo::nil_pointer`,
  `soppo::non_exhaustive`, `soppo::try_no_error_return`…), NOT numbered.
- Messages are suggestion-bearing ("check for nil first, or use `.(!nil)` to
  assert non-nil"; "Use `:=` to declare a new variable") — the
  Rust-style-diagnostic claim is honest at the message level, but the code
  registry is an order of magnitude smaller than GALA's 73 or Lisette's 544,
  and there is no per-code reference page or offline explain.

### (c) The DX suite — what exists, how structured

Everything ships in the main repo (workspace members: `.`, `lsp`):

- **LSP** (`lsp/`, `sopls`, 1,797 lines, tower-lsp + tokio): initialize,
  did_open/change/close + watched-file rebuild, **hover, goto_definition,
  document_symbol, completion, signature_help, references, formatting,
  rename (with prepare_rename), diagnostics** — workspace-wide, cross-module.
  Diagnostics consume the same miette errors as the CLI.
- **Formatter** (`src/fmt.rs`, 2,433 lines): AST-based pretty-printer with
  idempotence guarantees; wired to both `sop fmt` and the LSP formatting
  handler.
- **Linter** (`src/sniff/`): runs after type-checking with full type info;
  rules registry with per-line `//sniff:ignore [rule]` and `sop.mod`
  `[sniff] ignore = […]`; rules observed in tree: `try_operator` (flags
  `if err != nil { return err }` that should be `?`), `shadow`, `unreachable`
  (+ mod.rs registry). Rule count is small (single digits).
- **Test runner** (`src/test.rs`): discovers project, transpiles `_test.sop`
  files, **shells out to `go test`** with `-run`/`-v`/passthrough flags
  (`sop test -- -cover`). Zero homegrown test infrastructure.
- **Doctests** (`src/doctest.rs`, 490 lines): extracts ```` ```sop ```` /
  ```` ```soppo ```` fences from doc comments, **emits them as Go `Example`
  functions** (the `// Output:` convention), with Rust-style attributes
  (`ignore`, `should_panic`, `no_run`, `compile_fail`) — again executed by
  `go test`.
- **Go interop** (`src/go/`): parses Go source with **tree-sitter-go**
  (extract.rs:187) to pull function/type/field shapes; `go list` for package
  resolution; global stdlib cache + per-project cache (`go/cache.rs`).
  Generated Go carries `//soppo:nilable`, `//soppo:const` markers
  (`src/codegen/mod.rs:387-422`) which are read back by extract.rs —
  **cross-project nil-safety is preserved through the generated Go**, since
  you import a Soppo library's *generated Go*, never its `.sop` source.
- Release engineering: **release-plz** (auto changelog — visible as "feat;"
  entries in CHANGELOG.md), musl static binary for the playground Docker,
  criterion benches, proptest + a `fuzz/` crate, 137 insta snapshots, CRLF
  handling fix in 0.10.1.

### (d) `sopmod` version manager — design

Separate repo (verified live via `git ls-remote` + README fetch):
`halcyonnouveau/sopmod`, **"SOPMOD II … rewritten from Rust to Soppo, hence
the 'II'"** — i.e. dogfooded. Design (from its README):

- Installs/updates/switches `sop` versions; **also manages the Go
  installation Soppo uses for compilation**, and auto-installs `sopls`
  alongside every `sop` version.
- Install via `curl … | sh`; shims in `~/.sopmod/bin`.
- **Per-project pinning:** `sop = "0.4"` in `sop.mod`; flexible semver
  matching ("0.4" matches any 0.4.x installed); the `sop` shim auto-selects
  the pinned version when run inside the project.
- `sop` itself enforces the pin: `check_version_requirements()` at CLI entry
  (`src/main.rs:117`) — the *compiler* refuses to run when the environment's
  version doesn't satisfy `sop.mod`.

### (e) Is it actually a "Go superset"? What breaks Go compatibility

**No — the claim fails on three verified points**, which is exactly why
positioning.md pre-ruled against superset positioning for Hybrid:

1. **`switch` is a hard error** — `src/syntax/parser/stmt.rs:895`:
   `Some(Token::Switch) => Err(SoppoError::UnsupportedSwitch { span })`.
   "Use `match` instead of `switch`". Legal Go does not compile.
2. **Nilability changes `var` semantics** — `var user *User` (uninitialized)
   is an *error* ("non-nilable - must be initialised"); `var user *User =
   nil` is an error. In Go both are legal. Nil-safety by default is a
   semantic divergence, not an extension.
3. **Import names cannot be shadowed by local variables** (guide.md) —
   stricter than Go.

Everything else (structs, funcs, goroutines, `select`, channels, slices,
maps, interfaces, generics) is genuinely Go syntax. So: "Go-shaped, mostly
source-compatible, not a superset." The honest framing Hybrid should keep
(from positioning.md): Go developers shouldn't feel they're learning a new
language *to start* — without claiming compile-compatibility.

---

## 3. Lisette (github.com/ivov/lisette) — "Little language inspired by Rust that compiles to Go"

Rust-syntax language compiling to readable Go, ~167k lines of Rust across 10
crates (`syntax`, `semantics`, `passes`, `emit`, `diagnostics`, `format`,
`lsp`, `cli`, `deps`, `stdlib`), with a Go-module prelude
(`prelude/*.go`), tree-sitter grammar + 5 editor integrations, Astro
docs site, WASM playground, cargo-dist releases.

### (a) The 500+ diagnostics — count and CATEGORY taxonomy (the gold)

Codes are strings shaped `phase.name`, attached via constructors in
`crates/diagnostics/src/diagnostic.rs:301-336`:

```
with_parse_code → "parse.<name>"      with_resolve_code → "resolve.<name>"
with_infer_code → "infer.<name>"      with_lint_code → "lint.<name>"
with_attribute_code → "attribute.<name>"   with_emit_code → "emit.<name>"
```

**My count: 544 unique code strings** (unique `with_*_code("literal")`
arguments across all crates; plus dynamic `IssueKind::lint_name()` values not
in that count). By phase:

| Category | Unique codes | What lives there (samples from my dump) |
|---|---|---|
| `parse` | 45 | lexer/grammar |
| `resolve` | 56 | imports/modules/deps: `import_cycle`, `duplicate_import`, `nil_not_supported`, `go_toolchain_missing`, `corrupt_go_typedef`, `bindgen_failed` |
| `infer` | 267 | the type system's full surface: `type_mismatch`, `non_exhaustive`, `index_out_of_bounds`, `try_block_*` (9 codes), `recover_block_*` (6), `select_match_*` (8: exhaustiveness of channel-receive matches), `or_pattern_*`, `missing_bound_on_param`, `comma_ok_abi_mismatch` |
| `lint` | 141 | warnings: `collapsible_if`, `almost_swapped`, `double_comparison`, `deprecated`, `enum_variant_names`, `excess_parens_on_condition`… |
| `attribute` | 31 | `#[json]`-style annotation validation |
| `emit` | 4 | Go-name collisions, reserved prefixes/qualifiers in generated code |

Two structural disciplines worth copying verbatim:

- **Severity is enforced by constructor:** `with_lint_code` carries a
  `debug_assert!(matches!(severity, Warning | Advice))` — "use a
  phase-specific code constructor for errors". Lints can never silently
  become errors (diagnostic.rs:316-324).
- **Machine-applicable fix-its are first-class:** `Fix { message, edits }`
  with `Edit { span, content }` (`crates/diagnostics/src/fix.rs`), a
  one-fix-cannot-edit-multiple-files assertion, span remapping support, and
  `apply_fixes` — **65 `.with_fix(` sites** across the codebase, exposed as
  `lis check --fix` (`crates/cli/src/command.rs` `CheckAction::Fix`).
  Rendering (safety.md shows real output): rustc-style
  `╭─[file:line:col]` frames, `─┬─` pointer spans, `help:` line ending in
  `· code: [resolve.nil_not_supported]`.

### (b) Hindley-Milner type inference — structure, and does it fight Go's type system?

Bidirectional inference with unification lives in
`crates/semantics/src/checker/infer/` (`unify.rs` with `UnifyError`
including `InfiniteType` = occurs check; `context.rs` with
`Expectation`/`ExpectationRole`; per-expression modules under
`expressions/`). `Type` (`crates/syntax/src/types.rs:425+`) is a hybrid
zoo: `Simple | Compound{writable} | Nominal | ImportNamespace | Function |
Var{TypeVarId} | Forall | Tuple | Array{length} | Never` — **HM unification
vars coexist with Go nominal types, Go interfaces, and package namespaces**.
It does not fight the Go side; it *absorbs* it:

- Go interfaces are structural method sets; interface values "do not carry
  their concrete type", narrowed with `assert_type<{}>(value)` (unify.rs:924).
- The friction points they had to design around are informative for Hybrid's
  SPEC-LANGUAGE: Go's `(value, ok)` comma-ok pairs vs `Option` unify
  differently (`infer.comma_ok_abi_mismatch`), typed-nil interfaces become
  `None` at the boundary (safety.md "Nil Go interfaces"), `cmp.Ordered ⊂
  Comparable` bound lattice is hand-encoded (`BuiltinBound::satisfies`,
  unify.rs:41-52).

So: full HM + Go-nominal is proven to coexist. But the reading experience is
Rust (`fn f(a: int) -> int` with inferred locals), and inference depth is why
`infer.*` has 267 codes — inference is where their diagnostic cost
concentrates. For Hybrid this is an existence proof for *local* inference +
Go-declared parameter types, not an argument for full HM.

### (c) Pipeline operator + `try` blocks — exact semantics

- **Pipeline `|>`** is a `BinaryOperator::Pipeline` rendered `"|>"` in the
  lexer (`crates/syntax/src/ast.rs:2440,2487`) — left-associative function
  application: `"  Hello World  " |> strings.TrimSpace |> strings.ToLower |>
  strings.ReplaceAll(" ", "-")` (README). Partial application in the last
  position (`strings.ReplaceAll(" ", "-")` binds the fixed args first).
- **`try` blocks** are `Expression::TryBlock { items, ty }` (ast.rs:1370)
  plus a sibling `RecoverBlock`. Exact lowering
  (`crates/emit/src/control_flow/fallible_blocks.rs:56`):
  **`try { … }` → `result := func() T { … }()`** — an immediately-invoked
  Go function literal; `?` inside becomes early `return` of the error; the
  pair-planning specializes CommaOk/Result ABIs. The 9 `infer.try_block_*`
  codes constrain semantics (no `?` inside = `try_block_no_question_mark`;
  no break/continue/defer/return escapes; carriers can't mix). This is the
  proven idiomatic-Go lowering for Hybrid's SPEC §8 mandate (a postfix
  `try`-style propagation operator) — and `recover` blocks get the same IIFE
  treatment with Go's `recover()`.
- `?` on a call = `Propagate` expression (ast.rs:1365), works on
  `Result<T, error>` and `Option<T>` carriers.

### (d) Fast incremental compiler — caching design

`crates/semantics/src/cache/` (+ `package_graph/`, `analysis/`):

- **Deterministic FNV-1a hashing everywhere** — they wrote their own
  `FnvHasher` because "unlike `DefaultHasher`, this produces deterministic
  hashes across Rust versions" (cache/mod.rs:55-57). Cache keys must not
  depend on Rust's unstable hasher.
- **Three-tier invalidation** (`cache/mod.rs:27-42`):
  `CACHE_FORMAT_VERSION` (bump on format changes) + `COMPILER_VERSION_HASH`
  (const FNV of `CARGO_PKG_VERSION`) + content hashes of the **prelude**,
  **test prelude**, and **Go stdlib typedefs** — a stdlib change invalidates
  all user package caches, automatically.
- **Per-package source hashing with transitive chaining:**
  `compute_package_hash(production_hash, dep_hashes)` — a dependency's hash
  feeds its dependents (cache/mod.rs:214), so edits invalidate exactly the
  affected subgraph.
- **Go-stdlib typedef cache** keyed per compile `Target`
  (`cache/go_stdlib.rs`: `stdlib_defs_<target>.bin`, validated against all
  three hashes, deleted on mismatch).
- **Atomic writes:** temp file + `fs::rename`; corrupt cache = delete and
  rebuild (cache/disk.rs:29-58).
- **Parallelism:** rayon with `PARALLEL_THRESHOLD = 4` — small jobs stay
  single-threaded (package_graph/mod.rs:529-539) — a directly relevant
  discipline for Hybrid's 2-core sandbox + 4-core worker.
- Whole-pipeline reuse for the playground/WASM: `MemoryLoader` +
  `AnalyzeInput`/`AnalysisScope` (`Script | Directory | Project`) let the
  compiler run in-process over in-memory files.

### (e) "No ownership, no borrowing, no lifetimes" — how honest?

**Honest.** The README bullet list doesn't carry the exact phrase, but
`site/src/content/docs/intro/coming-from-rust.md` says it in so many words:
"Rust moves `s1` into `s2`. **Lisette has no moves**"; "`String` and `&str`
collapse into one `string`. **No owned versus borrowed distinction**";
"a closure captures by reference, and the garbage collector **keeps what it
captured alive. No borrow rules, and no `move` keyword**". The type system
bears this out — `writable` flags on Compound/Nominal types are mutability
permissions, `Type::Var` has no region/lifetime parameter anywhere, and
there is no borrow checker crate. What they *do* have is
immutability-by-default (`let` vs `let mut`, `Ref<T>` read-only references)
and an `addressability.rs` analysis — which is permission tracking, not
borrowing. Their safety page is equally explicit about what they DON'T
prevent (data races are not in Lisette's prevented-list; Go's channels/gc
model is kept). This is the honesty bar positioning.md wants Hybrid to
match: state the race-freedom claim ONLY for the checked subset + `managed`
boundary in the same paragraph (already a Q1 binding addition).

**Other Lisette facts relevant to Hybrid:**

- **Prelude is a Go module** (`prelude/go.mod`, option.go/result.go/
  channel.go/map.go/…) — Option/Result/Channel runtime support written in
  Go, imported by generated code, with its own tests + `testkit`. This is
  exactly the support-package shape Hybrid's Go-source emission wants for
  Option/Result.
- **189 `.d.lis` typedef files** for the Go stdlib, generated by `bindgen/`
  (a Go program) with Go doc comments preserved; bundled + content-hashed by
  `crates/stdlib/build.rs`; `lis bindgen --stdlib <version>` regenerates;
  lefthook's `check-stdlib-drift` fails CI if committed typedefs drift from
  a fresh bindgen run. Third-party Go modules get typedefs too
  (`go_modules.tsv`, `bindgen.external.json`, `lis add`).
- Go toolchain pinned by two root files `go-language` ("1.25") and
  `go-toolchain` ("1.26.7"), kept in sync across 9 files by
  `scripts/check-go-versions.sh` in pre-commit (lefthook).
- **CLI surface** (command.rs): `new build emit run format(--check) check
  (--filter/--fix/--deny-warnings/JSON) test add sync lsp bindgen doc
  doc-search learn completions upgrade`. **`lis learn`** scaffolds a real
  task-manager project embedded in the binary with a feature→file map
  (handlers/learn/README.md). **Scripts mode:** single-file `.lis` with
  shebang `#!/usr/bin/env -S lis run`, dependencies in a
  `// [dependencies.go]` comment block managed by `lis add --script`.
- LSP: 9,483 lines across 28 files — hover/definition/completion/rename/
  code actions (the fix-its surface here)/semantic tokens/watched files.
- Editors: tree-sitter-lisette grammar + vscode/nvim/zed/helix/intellij.
- Release engineering: **cargo-dist** (dist-workspace.toml: 7 targets
  incl. musl + Windows, shell+powershell installers, GitHub attestations),
  git-cliff (cliff.toml), release-plz, lefthook conventional-commits +
  72-char subjects, deny.toml, cliff/clippy configs, `fuzz/` with seed
  corpus + `lisette.dict`, 5,376 snapshot tests, e2e test suite incl.
  `e2e_learn.rs` (the learn project is itself CI-tested).
- **Playground (playground/): fully static** — the compiler is compiled to
  WASM (`playground/wasm/`, wasm-bindgen, `opt-level="z"`, wasm-opt -Oz,
  panic=abort), diagnostics serialized as JSON to the TS layer; execution is
  **delegated to play.golang.org/compile** (executor.ts:8-9, also uses
  play.golang.org/fmt to gofmt the shown Go). **Zero server, zero
  user-code execution.**

---

## 4. THE COPY TABLE — what Hybrid copies, from where, where it lands

Nothing here promotes work above the SPEC §7 MVP line; this table orders the
post-MVP queue and enriches SPEC-LANGUAGE.md priorities.

| # | What to copy | Source + evidence | Lands in | Notes |
|---|---|---|---|---|
| 1 | **Sendability checker refinements**: (i) fail-closed deep `Shareable`-style type predicate with visited-set termination; (ii) capture analysis recording *how* a capture is used (pure field-read paths vs whole-use) so read-only projections of unshareable values pass; (iii) transparent `Sendable`-style bound that propagates up wrapper signatures and terminates at the closure literal | GALA `docs/CONCURRENCY_SAFETY.MD`; `concurrency/shareable.go`; `concurrency/capture.go` (`Capture{Paths, Whole}`); `transformer/concurrency_check.go` | **MVP** (safe-mode checking is an MVP item; this is the A1/A2 enrichment of the already-planned Tier-0 checker) | Direct input to SPEC-LANGUAGE Tier-0 chapter + the adversarial corpus's verdict expectations. The (c)+(b) strict ruling stands; GALA shows how to keep it non-punitive |
| 2 | **Diagnostic-code registry v1**: `HYB-Exxxx` codes, append-only, family-per-code, one reference page per code embedded in the binary, `hybrid explain` + `--list`, offline | GALA `galaerr/errors.go` (73 constants, "append (never renumber)"), `docs/errors/errdocs.go` (go:embed + Normalize), `cmd/gala/commands/explain.go` | **MVP-0/MVP boundary**: JSON envelope + first codes at MVP-0 (the walking skeleton's error paths); registry + explain by MVP | Registry format proposal in §6 |
| 3 | **JSON diagnostics envelope** `{"diagnostics":[…]}` (object, not array), 1-based positions, `endColumn`, `hint`, `docsUrl`, severity field from day one | GALA `galaerr/json.go:26-58` ("somewhere to grow without breaking consumers") | **MVP-0** | ~100 lines; unlocks every later tool (LSP, playground, CI tooling) |
| 4 | **Fix-it data model**: `Fix { message, edits: [Edit { span, content }] }`, one-fix-one-file assertion, `check --fix` application, LSP code-action surface | Lisette `crates/diagnostics/src/fix.rs`; 65 `.with_fix(` sites; `CheckAction::Fix` | **MVP** (Q1 binding addition: Tier-0 diagnostics must carry fix-its; the data model must exist when those diagnostics are first written) | Q1 says "diagnostic-not-punitive with fix-it suggestions (time budgeted)" — this is the budget's data structure |
| 5 | **Docs-as-tests for the registry**: doc code blocks compiled in CI; `doc-check: error HYB-Exxxx` blocks must fail with exactly that code | GALA `internal/doccheck/doc_snippets_test.go:44-48` | **MVP** (starts as soon as there are doc pages; trivial to add to `make check`) | Also the natural home for the adversarial corpus's documented examples |
| 6 | **`//line` source-position emission** for runtime panics | GALA `internal/transpiler/transpiler.go:1021` (+ marker-leak guard → their E0017) | **Already MVP** — Hybrid Spike 2 validated 14/14; keep + add the leak-guard | Independent re-validation from a second transpiler project |
| 7 | **Test runner = delegate to `go test`; doctests emitted as Go `Example` functions** with `ignore/should_panic/no_run/compile_fail` attributes | Soppo `src/test.rs` (shells to go test), `src/doctest.rs:1-60` | **MVP** for the runner (nothing to build — Hybrid emits Go), **post-MVP** for doctest extraction | Hybrid's differential testing already runs via Go; this extends the same rail |
| 8 | **Option/Result prelude as an emitted-Go support package** (committed, versioned, tested with its own Go tests) | Lisette `prelude/` (Go module: option.go, result.go, channel.go, map.go, testkit) | **MVP** (target program 9 = Go program importing Hybrid — the Go-side support package is part of that story) | Matches Spike 2's committed-source+artifact zero-install decision |
| 9 | **Go-package type-info strategy: bindgen-generated declaration files with preserved doc comments + drift-check CI** (preferred over tree-sitter parsing at scale; tree-sitter as the cheap bootstrap) | Lisette `crates/stdlib/typedefs/` (189 files), `bindgen/`, lefthook `check-stdlib-drift`; Soppo `src/go/extract.rs:187` (tree-sitter-go) | **MVP** (calling Go packages from Hybrid is an MVP item — Phase 2 design input; typedefs start with the ~10 stdlib packages the ten target programs need) | Lisette's typedef cache invalidation (content hash of typedefs) folds into #10 |
| 10 | **Incremental cache design**: deterministic FNV-1a keys, 3-tier invalidation (format version + compiler version + prelude/stdlib content hashes), per-package dep-hash chaining, atomic temp+rename writes, rayon with a small-job threshold | Lisette `crates/semantics/src/cache/mod.rs:27-57,214`, `cache/disk.rs:29-58`, `package_graph/mod.rs:529` | **post-MVP implementation** (SPEC §7 stretch: incremental compilation targets) but **MVP-time design hooks**: make package-source hashing part of the Phase-1/2 pipeline shape so the cache bolts on later | "Never sacrifice compile speed" is a strategic pillar; Lisette's is the reference design |
| 11 | **Playground, Lisette shape**: compiler-to-WASM, client-side compile, delegate execution to play.golang.org — no server, no user-code execution | Lisette `playground/wasm/Cargo.toml`, `playground/src/runner/executor.ts:8-9`; Soppo's server-side variant `www/playground/src/routes/api/compile/+server.ts:81` | **post-MVP** (SPEC §7 stretch: editor/LSP + this) | Caveat: the Go playground cannot run Hybrid's Rust-bridge calls — playground demos cover the Go-side language only; label it as such |
| 12 | **Formatter (Hybrid-source)**: AST-based, idempotent, wired to both CLI and LSP | Soppo `src/fmt.rs` (2,433 lines) as scope evidence; Lisette `crates/format/` | **post-MVP** (queue AFTER playground/LSP; 2.4k–9k lines in competitors) | Cheap stopgap: gofmt the *emitted* Go (already a Spike 2 gate) |
| 13 | **LSP** on top of the JSON diagnostics + tree-sitter grammar, editor configs as data | Soppo `lsp/src/lib.rs` (1,797 lines, tower-lsp); Lisette `crates/lsp` (9,483 lines); Lisette `editors/` (tree-sitter + 5 editors) | **post-MVP** (SPEC §7 stretch: editor/LSP support) | Scope anchor: Soppo's 1.8k-line LSP covers hover/definition/completion/references/rename/formatting — a realistic first target |
| 14 | **Version manager, sopmod shape**: manages Hybrid + pinned Go + Rust toolchains together, per-project pin in manifest with flexible semver match, shim auto-selects, compiler itself enforces the pin | sopmod README (verified via fetch); `soppo/src/main.rs:117 check_version_requirements()` | **post-MVP** | Cheap now: the pin-enforcement half (compiler refuses on manifest/version mismatch) is ~30 lines and belongs in MVP-0's `hybrid build` |
| 15 | **`learn` scaffold + scripts mode + llms.txt** (adoption surface) | Lisette `crates/cli/src/handlers/learn/` (embedded project + feature→file map), `site/src/content/docs/scripts.md` (shebang + `// [dependencies.go]`), GALA `website/llms.txt` + `website/for-ai.md` | **post-MVP** (docs/website batch) | llms.txt is nearly free for Hybrid since the compiler is agent-built; write it when the README stabilizes |
| 16 | **Zero-reflection JSON via compiler-intrinsic metadata** (format-neutral field encoder/decoder interfaces; format knowledge lives in stdlib, not the compiler) | GALA `internal/transpiler/transformer/codec.go`, `std/meta.gala:94` | **post-MVP** (target program 5 needs JSON — via a Rust crate for MVP; StructMeta-style Go-side metadata is the post-MVP native path) | The "transpiler carries no format-specific knowledge" separation is the architectural lesson |
| 17 | **Structural severity discipline**: lints can never be errors (debug_assert in the lint-code constructor); errors/warnings/advice 3-level | Lisette `crates/diagnostics/src/diagnostic.rs:316-324` | **MVP** (one line of discipline in the diagnostics crate) | Guards the "diagnostic-not-punitive" culture in code, not just docs |

## 5. THE AVOID TABLE — what not to copy, and why

Pre-rulings verified against actual code, plus new findings:

| Ruling | Verdict vs code | Evidence | Why avoid (for Hybrid) |
|---|---|---|---|
| **GALA's monads / functional purity** (pre-ruled) | **CONFIRMED as the cost driver** | GALA forbids `defer` and bare `go` (GALA-E0036), slice/map literals (E0007/E0008), bare `len`/`append`/`make` (E0035); capitalized methods; postfix `match`; `bind`/`also` do-notation; immutable-by-default params (`website/llms.txt`) | Hybrid keeps Go's statements, `defer`, `go`, literals, lowercase methods. Take the *type-safety* features (enums, exhaustiveness, Option/Result, immutability where cheap) — leave the lifestyle. r/golang signal: "Don't try to make Go into a different language" |
| **Lisette's Rust syntax** (pre-ruled) | **CONFIRMED** | `fn`/`let mut`/`match x { A => … }`/`\|a, b\|` closures/`for i in 0..10`/`loop`/`impl`/f-strings/`assert_type<{}>` throughout README + coming-from-go.md | Hybrid feels like Go (Soppo proves Go-syntax enums/match/`?` are expressible without Rust spelling). "If users wanted Rust syntax, they'd write Rust" |
| **Soppo's "Go superset" positioning** (pre-ruled) | **CONFIRMED — it is factually not a superset** | `switch` is a hard parse error (`src/syntax/parser/stmt.rs:895`); `var p *T` uninitialized is an error (nil-safety changes `var` semantics); import shadowing forbidden | Claiming superset creates unmeetable expectations (any legal-Go program must compile). Hybrid's honest frame: same-shape sibling with Go interop, "you're not learning a new language to start" |
| **NEW: GALA's Bazel-only build** | verified | 95 BUILD.bazel files, MODULE.bazel, Bazelisk required to build from source (README "Or build from source") | Contributor friction + resource cost on Hybrid's 2-core box. Hybrid's Makefile+cargo decision stands |
| **NEW: running user code on your own playground server** | verified as GALA's weak spot | gala-playground executes user code via `gala build` + `os/exec` in a fixed workspace, non-root user, no per-request sandbox (Dockerfile + main.gala) | Security liability for a small project. Use the Soppo/Lisette delegation pattern (play.golang.org) — never execute untrusted code yourself |
| **NEW: full Hindley-Milner inference** | verified as viable but costly | Lisette: 267 `infer.*` codes; `assert_type` narrowing; comma-ok ABI friction (`infer.comma_ok_abi_mismatch`) | Full inference changes the reading experience Go devs expect and concentrates diagnostic cost. Hybrid: local inference + declared signatures (cite Lisette as the existence proof that unification coexists with Go nominal types when the checker is written) |
| **NEW: reimplementing module management** | verified | GALA `gala.mod`/`gala mod tidy` + go-git dep fetching (`internal/depman/`); vs Soppo/Lisette who ride `go.mod` (sop.mod/lisette.toml are configs only) | Hybrid's decision (Go modules carry dependencies) is validated by 2 of 3 competitors; skip the depman |
| **NEW: miette-style unnumbered codes as the *user-facing* identifier** | verified | Soppo: 30 `soppo::snake_case` codes, no per-code docs, no explain; Lisette: 544 `phase.name` strings, no per-code page found (unverified whether site has one) | Great for *internal* classification, weak for search density and issue-filing ("code: [infer.try_block_no_question_mark]" vs "GALA-E0037"). Hybrid: numbered user-facing code + machine name field (§6) |

---

## 6. Diagnostic-code proposal for Hybrid

### Format: **`HYB-Exxxx`** (recommended over `HY-xxxx` and over bare names)

Evidence-based reasoning:

- GALA's `GALA-E%04d` shape is **proven user-facing**: 73 codes, each with a
  greppable, search-dense, docs-linked page; users can file issues against a
  code; `gala explain` normalizes `E0044`/`44` spellings. The dash-E shape
  also matches what the ecosystem already knows (rustc's `E0xxx`, GALA's
  `GALA-Exxxx`).
- `HY-xxxx` saves one character and nothing else; `HYB-` reads as the
  language's actual name (3-letter form of Hybrid) and keeps the `X-E####`
  scan pattern shared with GALA/rustc.
- Lisette's `phase.name` strings are superior as *machine* identifiers
  (self-describing, groupable) but poor as *human search keys* (long, rename
  silently breaks links). **So carry both:** the user-facing code is
  `HYB-Exxxx`; every diagnostic ALSO exposes a stable machine name
  (`category.name`, Lisette-style) in the JSON output and LSP.

### Code allocation: category-digit ranges (append-only within ranges)

`HYB-E{c}{nnn}` where `c` is the category digit — HTTP-status-class style,
so the number itself signals the area, while staying a plain 4-digit code:

| Range | Category (machine prefix) | Contents | MVP floor |
|---|---|---|---|
| `HYB-E0nnn` | `parse` | lexer/grammar errors | needed at MVP-0 (skeleton's parse errors) |
| `HYB-E1nnn` | `resolve` | imports/modules/symbols/version pins | needed by MVP (Go + Rust imports) |
| `HYB-E2nnn` | `type` | mismatch/inference/generics/interfaces/conversions | MVP |
| `HYB-E3nnn` | `own` | **Tier-0 ownership/sendability/borrow/handle-loans** — every code MUST carry a fix-it (Q1 binding) | MVP (safe-mode checking); the category Hybrid alone can own against all three competitors |
| `HYB-E4nnn` | `nil` | nil-safety/Option semantics | MVP (post-MVP-0 priority #2 per r/golang wishlist) |
| `HYB-E5nnn` | `match` | enums/exhaustiveness/patterns (incl. `select`-receive exhaustiveness à la Lisette `infer.select_match_*`) | MVP (priority #1 per wishlist) |
| `HYB-E6nnn` | `bounds` | integer overflow/index bounds/numeric conversions | MVP (SPEC §8 mandates the decisions) |
| `HYB-E7nnn` | `boundary` | ABI/descriptor/codegen/Rust-bridge contract errors | MVP (bridge is the differentiator) |
| `HYB-E8nnn` | `lint` | **warnings only** — enforce via Lisette's constructor debug_assert | post-MVP (start with 5–10 rules; Lisette's 141 is the long-term benchmark) |
| `HYB-E9nnn` | `tool` | build/deps/toolchain/version-manager errors | MVP-0 (`hybrid build` itself) |

Registry mechanics (all GALA-proven):

1. **Single in-repo registry file** (TOML or Rust consts — GALA uses Go
   consts with one-line comments; keep it diff-friendly) mapping code →
   {machine name, severity class, one-line summary}.
2. **Append-only, never renumber; retire = mark deprecated, leave the hole**
   (GALA's E0016 gap is the precedent — the discipline held for 73 codes).
3. **One reference page per code, embedded in the binary**
   (`docs/errors/HYB-Exxxx.md` + `go:embed`-equivalent / `include_str!`),
   `hybrid explain HYB-E3001` + `--list`, offline. Page template (GALA's):
   when it fires → minimal repro → real compiler output → fix (plural) →
   rationale → escape hatch.
4. **Codes classify families, not messages** (GALA: 4 capture shapes, one
   code E0037). Keeps the registry small and pages deep.
5. **CI guards:** every emitted code exists in the registry; every registry
   code has a page; doc code blocks compile (`doc-check: fragment`) or fail
   with exactly that code (`doc-check: error HYB-Exxxx`).
6. **Every diagnostic carries:** severity (error/warning/advice — Lisette's
   3-level), code, machine name, message, span (start+end), **hint**, and
   **optional machine-applicable Fix** (Lisette's `Fix/Edit` model). The Q1
   ruling makes hint+fix-it *mandatory* for `own.*` errors specifically —
   GALA's E0037 page is the quality bar (its 4 shapes each name the exact
   offending capture, the reason, and 2–5 concrete fixes including the
   "propagate the bound upward" pattern).

JSON envelope (MVP-0, ~100 lines):

```json
{ "diagnostics": [ {
    "severity": "error", "code": "HYB-E3001", "name": "own.unshareable_capture",
    "message": "…", "hint": "…", "file": "main.hy", "line": 7, "column": 23,
    "endColumn": 30, "docsUrl": "https://…/errors/HYB-E3001",
    "fix": { "message": "…", "edits": [{"span": "7:23-7:30", "content": "…"}] }
} ] }
```

(Envelope object not a bare array — GALA's growability rule; `fix` omitted
when absent; terse single-line form for LSP/tests kept separate from the
framed human renderer, also GALA's split.)

---

## 7. DX-suite phasing (LSP / formatter / linter / playground / version-manager)

Grounded in what actually exists in these repos and what each cost them:

**MVP-0 (walking skeleton — add now, nearly free):**

- JSON diagnostics envelope + first ~10 codes with hints (parse/resolve/tool
  categories hit immediately by the skeleton itself).
- Compiler-side version-pin enforcement (sopmod's
  `check_version_requirements` pattern, ~30 lines): `hybrid build` refuses
  when the environment's Go/Rust doesn't match the pinned versions.
- `//line` emission (already proven in Spike 2 — keep as a named gate).

**MVP (language + checker work carries the DX with it):**

- Full registry discipline (§6): append-only codes, embedded pages,
  `hybrid explain`, doc-check CI leg.
- Fix-it data model in the diagnostics crate from the first `own.*` error
  written (Q1 mandate; Lisette's `Fix/Edit` shape).
- Test runner = `go test` delegation (Soppo pattern — nothing to build).
- Option/Result prelude as a committed Go support package (Lisette prelude
  shape).
- Severity discipline: lints-never-errors assert (one line).
- Rust + Go version drift-check script (Lisette's `check-go-versions.sh`
  pattern: one script, ~40 lines, asserts go1.26.9/Rust 1.99.0 consistency
  across tools/env.sh, README, quickstart when it exists).

**post-MVP queue (ordered — cheap-and-leveraged first):**

1. **llms.txt + errors index on the site** (docs-only; GALA's
   for-AI/llms.txt is the template; Hybrid is agent-built — this is brand
   coherence).
2. **Playground, Lisette shape** (WASM compile client-side + play.golang.org
   execution; zero server, zero user-code execution; label the
   "Go-side features only, no Rust bridge" caveat honestly). Soppo's
   server-side variant is the fallback if WASM size hurts.
3. **LSP, Soppo-scoped first** (hover/definition/completion/references/
   formatting/diagnostics ≈ 1.8k lines on tower-lsp; Lisette's 9.5k-line
   server is the full maturity picture). Build on the JSON envelope +
   tree-sitter grammar.
4. **Formatter** (Hybrid-source AST printer; 2.4k lines in Soppo — budget
   accordingly; until then gofmt-of-emitted-Go is the story).
5. **Linter v0** (5–10 rules in `lint.*` codes; `try_operator`-style
   "modernize" hints are the highest-value category — Soppo's best rule
   flags `if err != nil { return err }` → `?`).
6. **Doctests** (Soppo mechanism: doc fences → Go `Example` functions; rides
   go test).
7. **Version manager** (sopmod shape: Hybrid + Go + Rust toolchains, per-
   project pin, shim; only after ≥2 released versions exist to manage).
8. **`learn` scaffold + scripts mode** (Lisette: embedded project +
   feature→file map; shebang single-file `.hy` with a dependencies comment
   block).

**Never:** running user code on our own infrastructure (GALA's playground
posture); Bazel; a homegrown test runner; a homegrown dependency manager.

---

## 8. Roadmap influence — concrete items for the lead to fold in

**For PLAN.md:**

- [plan] Add to Phase 1 task list: "Diagnostic registry v1 + JSON envelope +
  `hybrid explain` (GALA pattern; §6 of competitive-dx-study.md)" — done =
  registry file, envelope type, ≥10 codes with pages, doc-check CI leg.
- [plan] Add to Phase 1: "Fix-it data model mandatory for `own.*`
  diagnostics" — the Q1 binding addition, made concrete as Lisette's
  `Fix{message, edits}` with span remapping.
- [plan] Record in Decision Log: diagnostic code format = `HYB-Exxxx` with
  category-digit ranges + machine names (this doc §6) — reverse: rename
  prefix before public docs exist (cheap now, expensive later).
- [plan] Add to Phase 2 (Go interop) design input: Go type-info strategy =
  Lisette-style bindgen typedef files (start with the ~10 stdlib packages
  the ten target programs need) with drift-check CI; tree-sitter-go as the
  bootstrap parser (Soppo pattern) until typedefs cover the surface.
- [plan] Add to post-MVP queue (ordered): llms.txt → playground (Lisette
  shape) → LSP (Soppo-scoped) → formatter → linter v0 → doctests → version
  manager → learn/scripts (this doc §7).
- [plan] Add "version-pin enforcement + drift-check script" to MVP-0/MVP
  chores (~70 lines total).
- [plan] Risk register note: competitor diagnostic coverage floor to track —
  GALA 73 coded+documented, Lisette 544 coded (65 with fix-its), Soppo 30;
  Hybrid MVP target ≥ 40 coded+paged (parse/resolve/type/own/nil/match/
  bounds/boundary/tool), each own.* with fix-it.
- [plan] Note in the competitive-strategy Decision Log entry: Soppo's repo
  last push 2026-08-15 vs GALA/Lisette 2026-10-11 (single data point,
  unverified significance).

**For SPEC-LANGUAGE.md:**

- [spec] Tier-0 chapter (A1/A2 enrichment): adopt GALA's field-access-
  sensitive capture analysis — a `val` captured only through immutable
  field-read paths to shareable leaves is legal at a spawn/send boundary;
  whole-use requires full shareability of the type; `var` capture always
  rejected. Keeps strict (c)+(b) while matching Q1's
  diagnostic-not-punitive bar. Cite GALA CONCURRENCY_SAFETY.MD as prior
  art.
- [spec] Tier-0 chapter: adopt the transparent-boundary-marker idea in
  descriptor form — Hybrid's spawn/channel-send sites are compiler-known
  boundaries (no user-visible `Sendable` type needed); if Hybrid ever grows
  user-defined concurrency wrappers, GALA's caller-vouches propagation is
  the model.
- [spec] Error chapter: `try`-block lowering = IIFE
  (`result := func() T { … }()`) with early-return `?` — proven idiomatic-Go
  emission (Lisette fallible_blocks.rs); their 9 `try_block_*` constraint
  codes (no break/continue/defer/return escape, carriers can't mix) are a
  ready-made semantic checklist.
- [spec] Concurrency chapter: `select`-receive match exhaustiveness
  (Lisette `infer.select_match_missing_some_arm` / `…_none_arm`) —
  exhaustiveness checking extended to channel receive + close (Some/None
  arms); natural fit for Hybrid's channel model, wishlist-aligned.
- [spec] Type chapter: cite Lisette as existence proof that unification
  (local inference) coexists with Go nominal types + structural interfaces;
  record the known friction points to design around early: comma-ok pairs
  vs Option, typed-nil interfaces → None at the boundary, bound lattices
  (Ordered ⊂ Comparable).
- [spec] Stdlib chapter: prelude = committed Go support package (Lisette
  `prelude/` shape) — Option/Result/etc. live as Go code the emitted source
  imports; versioned with the compiler; own Go tests.
- [spec] Diagnostics chapter: registry mechanics per §6 (append-only,
  family-per-code, page-per-code, doc-check, severity discipline, fix-it
  model).

---

## 9. R&D nuggets (not pre-identified by the human)

1. **GALA doccheck — docs are compiled tests.** `<!-- doc-check: fragment -->`
   blocks must compile; `<!-- doc-check: error GALA-Exxxx -->` blocks must
   *fail with that exact code* (internal/doccheck/). Anti-drift between
   docs, diagnostics, and compiler — directly reusable for Hybrid's registry
   pages AND for the adversarial corpus documentation.
2. **GALA llms.txt / for-ai.md — "the compiler is the agent's feedback
   loop."** llms.txt lists the *specific mistakes models make* with the
   error each produces; for-ai.md pitches a strict compiler as the ideal
   agent generate→check→fix signal. Hybrid is being *built by agents* —
   writing its llms.txt early is free brand coherence and a real adoption
   lever for the AI-tooling audience.
3. **GALA errdocs.go placement trick** — the Go file lives inside
   `docs/errors/` because `go:embed` only reaches its own package dir; one
   copy of every page, served identically by CLI (embedded) and website
   (published). Equivalent Rust move: `include_str!` in a module placed
   next to the pages.
4. **GALA E0016 — the retired hole.** Append-only held across 73 codes and
   months of releases; deletion without renumbering is the registry's
   deprecation mechanism. Precedent for Hybrid's registry lifecycle.
5. **GALA AGENTS.md discipline overlaps Hybrid's §9 anti-gaming rules** —
   "NEVER weaken a check to get green", "NEVER work around a transpiler bug
   … fix the transpiler", "no internal ticket IDs (CI-enforced)",
   "generated parser is CI-guarded, never hand-written", "no special
   treatment for std". Independent convergence from another agent-built
   compiler project; worth cross-reading when Hybrid's AGENTS.md grows up.
6. **Lisette deterministic FNV-1a cache hashing** — they wrote a custom
   hasher because Rust's `DefaultHasher` is *not stable across Rust
   versions*; any persistent cache key must avoid it. Cheap lesson, easy to
   get wrong, silently corrupts caches on toolchain bumps.
7. **Lisette lefthook + scripts hygiene** — conventional-commit + 72-char
   subject enforcement; `check-stdlib-drift` (committed typedefs must match
   a fresh bindgen); `check-go-versions.sh` (9 files kept in sync with the
   pinned Go); `classify-changes.sh`/`loc-metrics.sh`. ~an afternoon of
   setup, permanent payoff; fits Hybrid's `make check` culture.
8. **Lisette `lis learn`** — an entire real project embedded in the binary
   (`include_str!` per file) with a feature→file table and CI e2e
   (`e2e_learn.rs`). The best onboarding device I saw in any of the three.
9. **Lisette scripts mode** — shebang-executable single-file programs,
   dependencies in a `// [dependencies.go]` comment block managed by
   `lis add --script`. Zero-manifest zero-to-running; post-MVP idea that
   compounds with the playground.
10. **Soppo doctest→Go-Example bridge** — doc fences become `Example`
    functions; `should_panic`/`compile_fail`/`no_run`/`ignore` attributes
    supported; executed entirely by `go test`. Hybrid gets doctests almost
    free given Go-source emission.
11. **Soppo playground trick (and Lisette's extension)** — transpile
    locally, execute via play.golang.org/compile: never run untrusted code
    yourself. Lisette goes further: WASM compile client-side → the
    "playground" is a static site. The cheapest credible playground
    architecture available; tailor-made for Hybrid's Go-source emission
    (with the no-Rust-bridge caveat).
12. **Lisette severity constructor assert** — `with_lint_code` debug-asserts
    Warning/Advice severity, encoding "lints never hard-error" as a type-
    level invariant rather than convention.
13. **Lisette `try`-block IIFE lowering** — `func() T { … }()` is the exact
    idiomatic-Go encoding of expression-level error-scoped blocks; Hybrid's
    SPEC §8 can cite it as the proven emission.
14. **Soppo's generated-Go markers round-trip** — `//soppo:nilable` /
    `//soppo:const` comments written by codegen, read back by the interop
    extractor: cross-project type-safety survives the Go boundary at zero
    runtime cost. Relevant to Hybrid's descriptor schema if Go-side
    consumers ever need sendability metadata in emitted source (verify
    need first — Hybrid's descriptors are compiler-internal today).
15. **GALA `gala build --json` + terse/rich renderer split** — one
    diagnostics type, two presentations (LSP/tests match the terse form;
    humans get the framed form). Keeps LSP + snapshot tests stable while
    human UX iterates.
16. **Lisette prelude-as-Go-module with testkit** — a transpiled language's
    runtime support shipped as an ordinary, separately-tested Go package:
    the cleanest answer to "what does the generated Go import?".
17. **GALA `gala doc <symbol>` and `doc_opaque`/`doc_prose` tests** —
    terminal API listing with CI tests for both opaque and prose cases;
    cheap stdlib-documentation DX.

---

## 10. Cross-cutting synthesis for the lead (one screen)

- **The competitive set is real and strong.** GALA (functional, huge,
  best-in-class diagnostics discipline) and Lisette (Rust-syntax, 544
  diagnostics, fix-its, cache design) are actively pushed as of 2026-10-11.
  Hybrid's differentiator (invisible Rust interop) is untouched by all
  three — none of them links Rust at all. The type-safety features are
  table stakes exactly as positioning.md framed them; the DX layer is where
  the fight actually is.
- **The single highest-leverage copy is GALA's diagnostic *system*** (codes
  + pages + explain + doc-check + JSON envelope), fused with Lisette's
  *taxonomy* (phase categories, severity constructor, Fix/Edit model). It is
  cheap, starts at MVP-0, compounds forever, and is the explicit Q1 mandate.
- **The single most important language-design copy is GALA's
  field-access-sensitive capture check** — it is the difference between the
  strict sendability ruling feeling like a precision instrument vs a
  borrow-checker cosplay, which is the exact r/golang fear.
- **The cheapest big-ticket DX items are delegation tricks**: tests →
  `go test`; execution → play.golang.org; compile → WASM. None require
  building infrastructure.
- **Compile-speed discipline has a reference design** (Lisette's cache) and
  a reference hazard (unstable hasher) — bake the package-hash hooks in at
  Phase 1/2, implement post-MVP.
