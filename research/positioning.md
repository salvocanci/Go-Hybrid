# Positioning & Market Research — human-supplied strategy input

**Source:** the owner (human), 2026-10-12, delivered with the G0 rulings.
**Status:** adopted as roadmap + README positioning input (PLAN.md Decision
Log, 2026-10-12). This file preserves the substance faithfully; the
competitive-DX repo study lives in `research/competitive-dx-study.md`.

---

## 1. The strategic frame: the Fast-Follower Playbook

The human's framing: this is exactly how TypeScript beat CoffeeScript, Dart,
and every other JS-transpiler. TypeScript didn't invent types — it studied
Java, C#, and Scala, picked what worked, and applied it to JavaScript. It was
a second mover, and it won. Hybrid runs the same play: study GALA, Lisette,
Soppo; copy what works; ship; move on.

**The pitch that follows from it:**

> "Keep Go exactly as it is. Add Rust where you need it."

Not "Go with more features" (that's GALA's pitch, and it appeals to a
subset). The type-safety features are **table stakes — they prevent Hybrid
from losing to GALA. They are not the reason to choose Hybrid.** The reason
to choose Hybrid is invisible interop: "Make the interop invisible — that's
the real product."

Three-part strategy:

1. **Match** GALA/Lisette on type safety (so Hybrid is not worse).
2. **Beat** them on Rust interop (so Hybrid is different).
3. **Never** sacrifice Go's compile speed or simplicity (so Hybrid does not
   lose the base).

## 2. What to copy from each language

### From GALA (github.com/martianoff/gala)

- **Compile-time data-race safety via immutability** — genuinely novel and
  directly relevant to Hybrid's safe mode. GALA proves it's implementable;
  study how.
- **Stable error codes (`GALA-Exxxx`)** — users can search them, look them
  up, file issues against them. Good DX discipline; Hybrid adopts the
  equivalent (hybrid-diagnostic-code registry) — pairs with Q1's
  "diagnostic, not punitive" ruling.
- **Zero-reflection JSON via `StructMeta[T]`** — a performance trick Hybrid
  will need eventually.
- **The playground** — adoption tool; cheap to build, high impact.

### From Soppo (github.com/halcyonnouveau/soppo)

- **The positioning sentence** — "If you know Go, you know most of Soppo."
  Hybrid steals the framing: Go developers should not feel like they are
  learning a new language to *start*.
- **Rust-inspired diagnostics** — good error messages are a moat; study the
  output format.
- **The full DX suite** — LSP, formatter, linter, test runner with doctests.
  Copy the approach, don't build from scratch.
- **`sopmod` (version manager)** — Hybrid needs something similar; don't
  reinvent it.

### From Lisette (github.com/ivov/lisette)

- **500+ diagnostics** — that's coverage; study the categories.
- **Hindley-Milner type inference** — full inference means fewer annotations;
  study whether it conflicts with Go's type system.
- **Pipeline operator and `try` blocks** — ergonomic wins; cheap to add
  (note: `try` semantics already mandated by SPEC §8 error section).
- **Fast incremental compiler** — dev experience; essential for adoption
  (and load-bearing for "never sacrifice compile speed").
- **The explicit honest positioning** — "No ownership, no borrowing, no
  lifetimes." Hybrid should be equally honest about what it DOES add.

## 3. What NOT to copy

- **GALA's full functional approach** — too niche; Go developers don't want
  monads.
- **Lisette's Rust syntax** — Hybrid should feel like Go, not Rust. If users
  wanted Rust syntax, they'd write Rust.
- **Soppo's "Go superset" positioning** — Hybrid is NOT a superset.
  Claiming to be one creates expectations it can't meet.

## 4. r/golang signals (human-synthesized)

### The top wishlist (consistent across threads)

1. **Proper enums with exhaustiveness checking** — the #1 most requested
   feature. "Fully-fledged enums alongside or instead of iota"; the specific
   desire is enums that fail to compile if a `switch` doesn't handle every
   option. ("Go Enums Suck" thread; "a lack of enums continue to bite many
   go devs, especially without being able to enforce exhaustive checks".)
2. **Null safety** — #2 most requested. "I'd love to see the compiler tell
   me reliably if I forgot a null check and keep the same speed. Copying the
   way Dart handles null safety would be a more or less remove an entire
   class of bugs." (Ex-Go-to-C# dev: lack of null safety is "one of Go's
   biggest weaknesses".)
3. **Sum types (tagged unions) and pattern matching** — "I like to write
   parsers and write toy programming languages and the lack of tagged unions
   always makes me feel like I'm using a dirty hack."
4. **Immutability / `const` for more types** — "Be able to mark variables as
   immutable"; "Slices/Maps as const".
5. **Option and Result types** — "If you have Option types, drop nil
   altogether."

### What Go developers actively don't want

- **Rust's borrow checker.** "I don't use things that don't exist. That's
  how I do it." — pragmatic, not aspirational. "The longer I use Go the
  less I feel I really need these tbh."
- **Complexity.** "I think the best thing I love about Go is its simplicity
  and I honestly don't want anything added to it for the sake of 'we want
  it.'" / "Don't try to make Go into a different language."
- **They care more about compile speed than features.** Compile speed and
  tooling are the reasons people stay.

### The tension and the insight

Go developers are deeply split: the loudest voices want features; a large
quiet majority loves Go *because* it doesn't have them ("I've gotten used to
them not being there"). **What Go developers SAY they want (enums, null
safety, pattern matching) is different from what makes them CHOOSE Go
(simplicity, compile speed, easy onboarding).** The features they ask for
are the features they've learned to live without; the things they stay for
are the things Hybrid must not break.

**Consequence for Hybrid:** shipping the wishlist prevents losing; it does
not win. Winning = invisible interop. The remaining technical question the
human flagged: whether the compiler can emit Go fast enough to preserve the
thing Go developers actually value (compile speed).

## 5. r/rust signals (human-synthesized)

### Core consensus: different tools, different jobs

"Go is for shipping, Rust is for correctness." Go optimizes time-to-working-
software; Rust optimizes absence-of-bugs in the working software. r/rust
defers to Go on productivity/hiring almost universally ("Rust may take 3
hours to code for a task in, Go may only take 1"; a Rust subreddit telling
people to use Go — pragmatism, not insecurity). On correctness, the
emotional core: **"When I write Go, I move faster but get left with anxiety.
Fear of nil-pointer, forgotten struct fields."** Anxiety versus confidence —
Go devs ship faster but worry more; Rust devs ship slower but sleep better.

### The interop reality (directly relevant to Hybrid)

Rust developers who've tried Go↔Rust FFI describe it as the hard part:

- Go's runtime is hostile to foreign calls (scheduler + GC expect to control
  everything; same cgo overhead from the Rust side, worse because Rust's own
  C FFI story is so clean by comparison).
- Goroutine stacks are incompatible with Rust stacks; goroutines migrate
  between OS threads while Rust's `!Send` types and thread-locals assume a
  call stays on one thread — real bugs, not theoretical.
- Neither language's ABI is stable across versions; there's no clean
  `extern "C"`-equivalent boundary by default.
- Thread title that says it all: "Why your Go-Rust FFI always core dumps
  under high concurrency."

### The rewrite trend

Rust developers see Go codebases as migration targets (TypeScript-compiler-
port discussions; Turborepo/Oxc/Bun moving to Rust). Their takeaway: Go wins
when a large mixed-seniority team maintains the codebase and the perf delta
doesn't justify Rust's costs. But they see Go codebases as *temporary* —
replaced when perf/correctness costs bite.

### What it means for Hybrid

- Rust devs already accept the trade-off Hybrid is eliminating — they've
  felt the pain of choosing. "Don't choose, get both incrementally" is
  exactly the pitch that resonates with someone who has already paid the
  cost. **More favorable starting position than the Go side.**
- But they're the hardest audience to convince — skeptical of abstraction
  that hides costs; they chose Rust *because* they wanted to see the costs.
  Hybrid must never HIDE a cost, only remove it (or price it in the open —
  the descriptor `blocking` flag and the honest ledger are already this
  discipline).
- **The real insight: the interop pain is the SHARED pain.** Go devs
  complain about cgo overhead; Rust devs complain about Go's runtime being
  hostile to foreign calls. Both sides agree the boundary is the problem.
  Hybrid's entire thesis is that the boundary shouldn't exist — that's the
  pitch that works on both sides, if Hybrid can deliver it. (The 2.42 ns
  crossing + two-tier scheduling from Phase 0 is the evidence it can.)

### Summary table (as supplied)

| What Rust developers say | What it means for Hybrid |
|---|---|
| Go is for shipping, Rust is for correctness | Hybrid's pitch — "get both" — is the right pitch for this audience |
| Go is easier to hire for, faster to write | Hybrid's Go-compatible output is a distribution advantage, not a technical one |
| Interop is painful because of runtime mismatches | Hybrid's 2.42 ns crossing directly addresses this |
| Go's simplicity prevents evolution | Hybrid's type-safety features (copied from GALA/Lisette) address this |
| Rewrites are the current solution | Hybrid's incremental adoption is the better answer — if it works |

## 6. Required language features implied (roadmap consequence)

Hybrid still needs **enums, pattern matching, Option/Result, nil safety**
— without them it's not competitive. But those features are how Hybrid
*avoids losing*, not how it *wins*. GALA and Lisette have already built
them; Hybrid copies what works, ships it, and moves on. Priority order in
the language spec follows the r/golang wishlist (enums+exhaustiveness first,
null safety second) — all inside the SPEC §7 cut order and the MVP-0
discipline; nothing here promotes a feature above the MVP line, it orders
the post-MVP queue and the SPEC-LANGUAGE.md type-system chapter.
