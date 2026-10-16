# rustgo (FiloSottile) — research note

## Identity

- Repo: https://github.com/FiloSottile/rustgo — **HTTP 404 as of 2026-10-11**
  (verified live on github.com and raw.githubusercontent.com for both `master`
  and `main`, both title-cased and lowercase user names). The repository has
  been deleted or made private; it is *not* merely archived today.
- Author: Filippo Valsorda (Go/cryptography engineer; then independent, later
  the Go team at Google). Companion demo repo, still live:
  https://github.com/FiloSottile/ed25519-dalek-rustgo ("Wrapper for
  curve25519-dalek using rustgo, a technique to directly call Rust code from Go
  programs with near-zero overhead, meant to replace manually written
  assembly.").
- Canonical write-up: "rustgo: calling Rust from Go with near-zero overhead",
  15 Aug 2017, https://words.filippo.io/rustgo/ (formerly blog.filippo.io/rustgo;
  redirects there). The README lived in the repo and is gone with it — this
  note reconstructs it from the article plus the demo repo's build files, which
  are complete working artifacts of the technique.
- License: the demo repo `LICENSE` is **MIT, Copyright (c) 2017 Filippo
  Valsorda**; the rustgo repo itself was MIT as well (license text not
  retrievable live — repo deleted — mark that detail UNVERIFIED-live, demo-repo
  MIT is verified).
- Status: dead experiment by author's own words — the article carries a
  2024-era note: "this was always a fun technical exploration, not a production
  guide. If you're looking for serious ways to call Rust from Go, know that
  cgo these days is faster and still getting faster. There are also some
  experimental cgo-less alternatives, like purego and wazero."
- Stars/activity: not retrievable live (API rate-limited from this sandbox, repo
  404). Historically low-three-digit stars; treat as UNVERIFIED-live.

## What it actually is (verified)

Not a library and not a toolchain — **a calling technique plus a proof**: write
hot functions in Rust, compile them as a `no_std` `staticlib` with the C ABI,
and call them from Go **through a hand-written Go assembly trampoline**, linked
into the Go binary with the external linker. No cgo, no libffi, no C in between.
The framing is "use Rust exactly where you would use hand-written assembly":
"if we have Rust code that is as constrained as assembly, we should be able to
use it just like assembly, and call straight into it."

The demo shipped real crypto: `edwards25519.ScalarBaseMult` wrapping
curve25519-dalek, "more than 3 times faster than a pure-Go alternative"
(demo README), distributed as pre-built `.a` tarballs per Go version and
`//go:binary-only-package` — which is itself an anti-pattern Hybrid should
learn from (binary-only packages are deprecated in modern Go).

Mechanism summary (all verified from `edwards25519/rustgo.go` + `rustgo.s` +
Makefile in the demo tarball):

1. Rust side: `#![no_std]` crate, `crate-type = ["staticlib"]`, compiled with
   `-Ctarget-cpu=native` (or a Haswell split), producing `libed25519_dalek_rustgo.a`.
2. Symbol binding in Go without cgo:
   ```go
   import _ "unsafe"

   //go:cgo_import_static scalar_base_mult
   //go:cgo_import_dynamic scalar_base_mult
   //go:linkname scalar_base_mult scalar_base_mult
   var scalar_base_mult uintptr
   var _scalar_base_mult = &scalar_base_mult
   ```
3. A Go assembly trampoline (below) adapts the Go ABI (2017: stack-passed
   arguments at `FP` offsets) to the SysV C ABI (argument registers) and calls.
4. `go build -ldflags '-linkmode external -extldflags …'` links the `.a`.

## Architecture (pipeline + runtime design)

The whole trampoline, verbatim — `edwards25519/rustgo.s` (14 lines, the heart
of rustgo):

```asm
TEXT ·ScalarBaseMult(SB), 0, $16384-16
        MOVQ dst+0(FP), DI     // Go stack arg 0 -> SysV rdi
        MOVQ in+8(FP), SI      // Go stack arg 1 -> SysV rsi

        MOVQ SP, BX            // save Go SP
        ADDQ $16384, SP        // jump up 16 KiB: Rust runs on a scratch frame
        ANDQ $~15, SP          // 16-byte alignment for the C ABI

        MOVQ ·_scalar_base_mult(SB), AX
        CALL AX                // call the Rust symbol

        MOVQ BX, SP            // restore Go SP
        RET
```

And the Go-side declaration it fronts — `edwards25519/rustgo.go`:

```go
//go:binary-only-package
package edwards25519

// ScalarBaseMult multiplies the scalar in by the curve basepoint, and writes
// the compressed Edwards representation of the resulting point to dst.
func ScalarBaseMult(dst, in *[32]byte)
```

Design points worth naming:

- **`$16384-16`**: 16 bytes of Go frame (two pointers) and 16384 bytes of
  scratch — "that $2048 value is the whole stack size Rust is allowed" in the
  toy version; the demo burned 16 KiB. The Rust callee lives *inside* the Go
  stack's unused headroom (SP moved up, i.e., away from the guard page), so no
  second stack is allocated and no stack switch bookkeeping exists.
- **No `g` register save, no `morestack` prologue**: the article concedes "I
  suspect I should be saving g before the jump, the stack size is completely
  arbitrary, and shrinking the trampoline frame like that will probably confuse
  the hell out of debuggers. Also, a panic in Rust might get weird." The toy
  version relied on the assembler's generated stack check ("The first 4 and last
  2 instructions of the function are checking if there is enough space for the
  stack, and if not calling runtime.morestack_noctxt").
- **`no_std` was a side-quest**: to be "like assembly" the staticlib must not
  drag in the Rust runtime — the article lists the arcane requirements of
  2017-era Rust: `#![feature(lang_items, compiler_builtins_lib,
  core_intrinsics)]`, `#[lang = "panic_fmt"] fn panic_fmt() -> ! { unsafe {
  intrinsics::abort() } }` (panics = abort, no unwinding), `eh_personality` stub,
  `compiler_builtins` and `rlibc` (memcpy), and the surprise that a `no_std`
  staticlib "is more like making a no_std executable". Linking still pulled in
  `libresolv` until every dependency was made `no_std` — a lesson: audit the
  staticlib's symbol table (`nm -u`, `ar t`) before shipping.
- **Cross-compilation**: the Makefile maps `GOOS/GOARCH` to Rust target triples
  (`MUSL=1 GOOS=linux make clean install LD=x86_64-linux-musl-ld`), so the
  `.a` can be cross-built; but external link mode is mandatory, which breaks
  internal-linking cross builds — the reason Go stdlib crypto never adopted
  this route wholesale.
- **Pre-Go-1.17 ABI**: arguments at `0(FP)`/`8(FP)` only works because Go
  passed arguments on the stack. Go 1.17+ passes the first arguments in
  registers on amd64, so every trampoline of this shape is now
  version/arch-specific and silently wrong when the ABI shifts.

## The claims check

| claim | verdict | evidence |
|---|---|---|
| "Assembly-level Rust calls from Go, bypassing cgo." | **CONFIRMED** | `rustgo.s` is a Go-assembly `TEXT` that `CALL AX`s a Rust `staticlib` symbol bound via `//go:cgo_import_static` + `//go:linkname` (demo repo, quoted above); article: "We don't have to work at the IR level: the Go compiler converts both code and high-level assembly into machine code before linking"; cgo is criticized for its "whole stack for C to live in" and per-call cost. |
| "~40ns/call" | **CORRECTED — it is ~4.6–5.1ns/call** | Article benchmarks (2.9GHz i5, macOS): `CallOverhead/Inline 1.72ns`, `/Go 4.60ns`, `/rustgo 5.11ns ± 4%`, `/cgo 73.6ns`; Linux without the function-pointer workaround: `rustgo 4.58ns ± 3%` vs Go 4.49ns — "11% slower than a Go function call, and almost 15 times faster than cgo" (cgo 69.4ns). Nothing in the article or demo claims 40ns; ~40ns resembles cgo-era overhead folklore, not rustgo. |
| "archived" (repo metadata) | **CORRECTED — now deleted/404; archived status unverifiable live** | Live check 2026-10-11: `github.com/FiloSottile/rustgo` → 404 (no redirect), raw README → 404 on `master`/`main`. The demo repo still resolves (and is not archived). Whether the repo was archived *before* deletion cannot be verified from this sandbox (GitHub API rate-limited; Wayback timed out). The author's 2024 article addendum effectively retires the technique. |

## What Hybrid should extract

1. **The core proof: cgo is not mandatory.** A Go binary can bind and call
   Rust-compiled symbols with ~5ns overhead — comparable to a plain Go
   function call — via assembly trampolines + `linkname`. Hybrid's "one build
   command, no C in between" pitch has a working precedent at exactly this
   performance point.
2. **Rust-as-constrained-assembly framing.** `no_std` + `staticlib` + C ABI +
   abort-on-panic gives a Rust component with *zero runtime entanglement* —
   no allocator, no unwinder, no std — which is the safest thing to embed
   under a Go (or Hybrid) runtime. Adopt this as the contract for the *guest*
   side of any assembly-bound Rust crate we call.
3. **Explicit, checked stack budgets.** rustgo's arbitrary 16 KiB scratch frame
   is the failure it admits to. Hybrid should compute a per-thunk worst-case
   stack budget (or better, run guest Rust on its own guard-paged stack like
   rustygo does) and refuse to emit a trampoline without one — on our 4GB
   sandbox, an unbounded callee frame is a fork-bomb-grade bug.
4. **Save the runtime context registers.** "I should be saving g before the
   jump" — on modern Go the trampoline must save/restore the `g` register (and
   on other arches, their thread/register state) or any preemption, GC scan, or
   stack-growth check that fires inside the callee corrupts the scheduler.
   Treat this as a hard requirement in Hybrid's thunk generator.
5. **The benchmark gate.** Adopt the exact ladder (inline / Go call / Hybrid
   call / cgo) as a CI performance gate with published numbers, including the
   "2% vs 11% depending on indirection" honesty — call-through-function-pointer
   cost is real and must be a stated number, not hidden.
6. **Symbol hygiene.** `nm -u`/`ar t` on the produced staticlib should be a
   build step: a `no_std` guest that accidentally links `std`/`libc`/
   `libresolv` breaks cross-compilation and static linking. Make "no unexpected
   dynamic symbols" part of the one build command.
7. **What not to copy: the distribution model.** Pre-built `.a` tarballs +
   `//go:binary-only-package` (deprecated) is the opposite of "one build
   command". Hybrid must always build from source; rustgo's release engineering
   is a cautionary tale, not a template.

## Failure modes / lessons

- **Panics cannot cross.** The `no_std` guest aborts on panic
  (`intrinsics::abort()`); the article: "a panic in Rust might get weird."
  Hybrid needs an explicit panic contract at the boundary (map Rust panic to a
  Go-side error/panic at the trampoline, or abort the process) — never leave it
  undefined like rustgo did.
- **Stack model is unprincipled.** The callee runs on borrowed headroom of the
  caller's stack with a magic constant, no guard page of its own, and no
  overflow story; deep Rust recursion or a big local array silently trashes the
  Go stack below. (rustygo's independently-designed guard-paged reserved stacks
  are the fix.)
- **Debuggability degrades.** "Shrinking the trampoline frame like that will
  probably confuse the hell out of debuggers" — unwinders and profilers see a
  frame that jumps SP by 16 KiB and shares no unwind info with the callee.
  Hybrid must emit unwind info (`.eh_frame`/`CFI`) for every generated
  trampoline, or pprof/Delve on our own runtime will be blind at exactly the
  interop boundary.
- **The ABI is a moving floor.** Written against Go's pre-1.17 stack ABI; Go
  1.17's register ABI and later linkname tightening (`//go:linkname` requires
   `import _ "unsafe"` and is increasingly restricted) break such trampolines
   per release. Hand-written per-arch asm is a permanent maintenance tax;
  generate it, version it against the exact Go runtime, and test on every Go
  minor bump.
- **External linking requirement.** `-linkmode external` (and `-extldflags`)
  was mandatory, which killed internal-linking cross-builds and pulled system
  libraries (`libresolv`, `libc`, `m`) into the link. Hybrid's one-command
  build should keep internal linking where possible or own the external link
  entirely.
- **Why it stopped (author's own account, 2024 note):** cgo got faster; the
  real use case (crypto assembly) moved to formally verified generated Go;
  purego/wazero cover the cgo-less niches; and the author's follow-up use of
  the technique in the Go stdlib (macOS X.509 verifier invocation) shows the
  idea was sound but the maintenance burden wasn't worth a community project.
  Lesson for Hybrid: a technique must ship as *tooling* (generated, tested,
  versioned) to survive — a repo of hand-rolled asm does not.

## Licensing

MIT (verified on the demo repo, Copyright (c) 2017 Filippo Valsorda; the main
repo's license is no longer retrievable but was MIT). MIT is fully compatible
with Hybrid's dual MIT/Apache-2.0 licensing; the code is tiny and effectively
public-domain-grade for reuse. Since the main repo is deleted, nothing here
should be *vendored* from it anyway — the demo repo files are the canonical
surviving artifact and are trivially reimplementable (14 lines of asm).

## Verdict for Go-Hybrid

**Borrow ideas; do not depend on or fork. Skip the code, keep the lessons.**

Rationale: the repo no longer exists to fork; the technique is 2017-era and
ABI-rotted (pre-1.17 stack ABI assumptions); and its own author retired it in
favor of cgo/purego/wazero. But it is the founding benchmark for "FFI-free"
Go↔Rust calls — ~4.6ns/call, 15x cheaper than cgo — and the single best
catalogue of the traps (g register, stack budget, panics, debuggers, linking)
that Hybrid's generated thunks must solve where rustgo's hand-written ones
hand-waved. Use it as the requirements list for our thunk generator and as the
historical justification that sub-10ns Go→Rust calls are achievable without cgo.
