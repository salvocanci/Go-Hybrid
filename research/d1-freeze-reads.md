# D1 — freeze-after-send: does it ban READS as well as WRITES? — research note (Task 5-a)

**Date:** 2026-10-12
**Author:** agent 5-a (d1-research), research-only task; this file is the only owned output.
**Decision being researched:** SPEC-LANGUAGE.md §13.2 **D1** — O5.2 (§9.3) freezes every live
alias of a moved/sent value for **reads and writes**; the alternative is a **writes-only**
freeze (the literal wording of spike-6's reading (b): "the sender's subsequent *mutations*
are rejected"). Pinned by corpus programs 05 (write-through-binding), 19 (pure read,
CONTESTED — flagged for G1 human pre-review), 20 (write-through-alias).

**Evidence-quality flags used below:**

- **[V-fetch]** verified by fetching the primary source today (URL given; raw text quoted).
- **[V-snippet]** verified via a search-result snippet of the primary source (URL given,
  snippet quoted verbatim; full page not fetched).
- **[V-local]** verified in a local clone under /home/z/my-project/refs/ (study copies,
  fetched by agents 7-a/5-b earlier).
- **[recalled]** from model knowledge; primary source NOT fetched today — treat as
  directionally reliable but check before quoting externally.
- **[unverified]** could not confirm; flagged so nobody repeats it as fact.

Web-search note: the `web_search` backend returned junk for most technical queries
(dictionary/SEO results); page fetching (page_reader + direct curl) worked well. Where
search was used only to *locate* a primary source that was then fetched, the item is
[V-fetch]. Semantic Scholar API was rate-limited (429) all session — two paper details
stay [recalled].

---

## 0. The question, precisely

```hy
agg := map[string]int{...}
results <- move agg     // [S2] legal owned move (O4 class 3); freeze starts HERE
n := len(agg)           // 19: pure READ through the moved binding — error or not?
agg["total"] = len(agg) // 05: WRITE through the moved binding — error under EVERY reading
```

Over GC memory nothing can dangle — this is purely about the **race-freedom claim**
(§9.2) and ergonomics. The load-bearing fact is Go's own race definition
(**[V-fetch]** go.dev/ref/mem, informal overview):

> "A data race is defined as a write to a memory location happening concurrently with
> another read or write to that same location, unless all the accesses involved are
> atomic data accesses as provided by the sync/atomic package."

So a concurrent unsynchronized **read** (sender) + **write** (receiver) **is** a data
race in Go's model. The channel send happens-before the receive *completes*, but the
sender's read-after-send is unordered with respect to the receiver's write-after-receive —
program 19's shape (`n := len(agg)` in main vs `m["fox"]++` in sink) is a genuine race
under DRF-SC, and `go test -race` would flag it. A writes-only freeze accepts exactly
that program; §9.2's sentence "Hybrid's compiler guarantees freedom from data races only
for Hybrid-checked sites in the checked subset" would then be **false** — and §9.2 is
normative (Q1 addition 6: the claim is the product; alternatives get recorded, claims
don't get quietly narrowed).

## 1. Rust — reads after move are errors; the sound relaxations never landed

**E0382, the exact shape [V-fetch]** (doc.rust-lang.org/error_codes/E0382.html, fetched
today; the erroneous example itself contains a *read*):

> "Error code E0382: A variable was used after its contents have been moved elsewhere."

```rust
struct MyStruct { s: u32 }
fn main() {
    let mut x = MyStruct{ s: 5u32 };
    let y = x;
    x.s = 6;                    // write after move
    println!("{}", x.s);        // READ after move — part of the SAME E0382 error
}
```

> "Since MyStruct is a type that is not marked Copy, the data gets moved out of x when
> we set y. This is fundamental to Rust's ownership system: outside of workarounds
> like Rc, a value cannot be owned by more than one variable."

The Book's semantics **[V-fetch]** (doc.rust-lang.org/book/ch04-01-what-is-ownership.html):
"because Rust also invalidates the first variable, instead of being called a shallow
copy, it's known as a move… With only s2 valid…" — moved-from = *invalidated*, not
"readable but unspecified". The suggested fixes are exactly the ones VERDICTS.md
pre-registers for 19/05: borrow (`&`) instead of moving, `.clone()` first, `Copy`.

**Any sound "read after move" proposal?** No — only adjacent ideas, none landed:

- **`&move` / move references** **[V-snippet]**: internals.rust-lang.org "A sketch for
  `&move` semantics" (Apr 2023): "`&move T` is a theoretical third reference type which
  conveys ownership of and responsibility for dropping the T, but not its backing
  memory." Also users.rust-lang.org "Aside – some ramblings about `&move` references"
  (Jul 2021). These transfer ownership through a reference; they do **not** make the
  moved-from source readable. Never accepted.
- **`moveit`** **[V-fetch]** (crates.io API: "A library for safe, in-place construction
  of Rust (and C++!) objects", last updated 2023-06-15, ~1.26M downloads; README:
  "safe, in-place construction… This is not an officially supported Google product."):
  C++-style move *constructors* for pinned interop — it makes moves *stronger*
  (in-place, address-preserving), not moved-from sources readable.
- **`Freeze` auto trait** **[V-fetch]** (library/core/src/marker.rs, unstable,
  `issue = "121675"`): "Used to determine whether a type contains any UnsafeCell
  internally… This can be used to declare that a constant with a generic type will not
  contain interior mutability, and subsequently allow placing the constant behind
  references." — Rust's real "reads are safe" mechanism is **no-interior-mutability**,
  and it is a *type* property used for statics/promotion, not a post-move amnesty.
- **`frozen-collections`** **[V-fetch]** (crates.io: "Fast partially-immutable
  collections", v0.9.3, updated 2026-09-08, ~99.7k downloads): immutable-after-build
  collections — the *freeze-to-immutable* direction, i.e. Pony `val` in library form,
  not read-after-move.
- The old "`unique`" freeze ideas from pre-1.0 Rust: **[unverified]** — I could not
  fetch a primary source; do not cite. (An "`ice` crate" mentioned in the task brief
  is a CTF tool on crates.io today, unrelated — **[V-fetch]** crates.io API.)

**Net:** Rust errors on the read (its own error-index example does the read), and every
serious relaxation proposal relocates the safety to *immutability of the type*, not
*permissiveness after transfer*.

## 2. Swift — the transfer model is literally "the sender stops using the data"

**SE-0302 (`Sendable` and `@Sendable` closures), Implemented Swift 5.7 [V-fetch]**
(raw.githubusercontent.com/apple/swift-evolution/main/proposals/0302-concurrent-value-and-concurrent-closures.md),
section "‘Transferring' Objects Between Concurrency Domains":

> "A fairly common pattern in concurrent systems is for one concurrency domain to build
> up a data structure containing unsynchronized mutable state, then ‘hand it off' to a
> different concurrency domain to use by transferring the raw pointer. This is correct
> without synchronization **if (and only if) the sender stops using the data** that it
> built up — the result is that only the sender or receiver dynamically accesses the
> mutable state at a time."

*Using* — not mutating. That sentence is the strongest single piece of prior art for
O5.2's reads-too reading: the safety argument for transfer requires sender abstinence,
full stop.

**SE-0414 (Region-Based Isolation), Implemented Swift 6.0 [V-fetch]**
(proposals/0414-region-based-isolation.md). SE-0414 *relaxes* the blanket ban — but by
proving **disjointness**, never by allowing reads of the transferred value:

```swift
func openNewAccount(name: String, initialBalance: Double) async {
  let client = Client(name: name, initialBalance: initialBalance)
  await ClientStore.shared.addClient(client)
  client.logToAuditStream() // Error! Already transferred into clientStore's
                            // isolation domain... this could race!
}
```

The proposal's own words: it "enables transferring non-Sendable values across isolation
boundaries and **emits errors at use sites of non-Sendable values that have already
been transferred** to a different isolation domain." After a transfer, "any other
non-Sendable value that is statically proven to be impossible to reference from
`client` can still be used safely" — via **isolation regions** (values are co-regional
iff one may alias or reach the other). The sender may keep using *other* values; any
use — read or call — of the transferred value itself is the error. This is the
principled version of Hybrid's alias-scoped freeze: Hybrid's "every live alias of the
moved value" is a coarse alias-set region; SE-0414 is the same idea with a reachability
formalism (§"Isolation Regions": two values are in one region if one "may alias" the
other or is "referenceable… via chained access").

**SE-0337** = "Incremental migration to concurrency checking" **[V-fetch]**
(evolution index: "Incremental migration to concurrency checking", Doug Gregor &
Becca Royal-Gordon, Implemented Swift 5.6) — the `StrictConcurrency` levels
(minimal/targeted/complete). Not a semantics change; cited for completeness: even
Swift's *migration* story never offered "reads allowed after transfer" as a level.

**SE-0390 (Noncopyable structs and enums) [V-fetch]** — Swift's move-only types.
"We use the term **consume** to refer to an operation that **invalidates the value**
that it operates on… and invalidates the value the operation was performed on after it
is completed." Also `consuming` parameters. Swift's spelling of use-after-move is
invalidation, matching Rust; the ergonomics relief valve is the explicit
copy/destructuring before the consume.

## 3. Pony — `iso` is "read and write unique"; the sender gives up reading

**[V-fetch]** tutorial.ponylang.io sources
(raw.githubusercontent.com/ponylang/pony-tutorial/main/docs/reference-capabilities/…):

- *Consume and Destructive Read*: "When you `consume` a variable you take the value out
  of it, effectively leaving the variable empty. **No code can read from that variable
  again until a new value is written to it.**"
- *Passing and Sharing References*: "This is exactly what `iso` does. It is **read and
  write unique**, there can only be one reference at a time that can be used for
  reading or writing. **If you send an `iso` object to another actor, you will be
  giving up the ability to read from or write to that object.**"
- The legal way to keep reading what you sent: **`val`** — "globally immutable… you can
  freely send `val` objects to other actors, **without needing to give up the ability
  to read from that object**." And `trn` exists to "make it *globally immutable* later"
  — an explicit freeze-to-share transition.
- Pony's ergonomic answer to "I still want the value" is *destructive read*: assignment
  returns the OLD value of the LHS, so moving into a field hands you back the previous
  contents — a compiler-blessed snapshot idiom ("when we do a destructive read, we
  assign to the field so it always has a value").

Pony is the closest published system to Hybrid's exact design point (GC-free but
actor-isolated, data-race-free **by proof** — the tutorial's own claim, with its linked
proof at ponylang.org/media/papers/opsla237-clebsch.pdf: "the type system ensures *at
compile time* that your concurrent program can never have data races"). Its verdict is
unambiguous: sender
reads die with the send; reads survive only through immutability (`val`).

## 4. C++ — THE counterexample, and why its reasoning does not transfer

**[V-fetch]** en.cppreference.com/w/cpp/utility/move:

> "Unless otherwise specified, all standard library objects that have been moved from
> are placed in a **‘valid but unspecified state'**, meaning the object's class
> invariants hold (so functions without preconditions, such as the assignment operator,
> can be safely used on the object after it was moved from)"

```cpp
std::vector<std::string> v;
std::string str = "example";
v.push_back(std::move(str)); // str is now valid but unspecified
str.back();                  // undefined behavior if size() == 0: back() has a precondition !empty()
if (!str.empty())
  str.back();                // OK, empty() has no precondition and back() precondition is met
str.clear();                 // OK, clear() has no preconditions
```

So C++ **does** allow reads of the moved-from object — conditionally (only
precondition-free operations), and with the same page warning: "the standard library
functions called with xvalue arguments **may assume the argument is the only reference
to the object**; if it was constructed from an lvalue with std::move, no aliasing
checks are made."

**Why this works there and would not work here:**

1. **No data-race claim to falsify.** C++ has no DRF-SC promise, no `Send`/`Sync`, and
   no compile-time race checker; the moved-from rules exist so single-threaded plumbing
   (`swap`, sink parameters, containers) stays usable. The convention is
   single-threaded: `std::move` between two locals in one thread. Nobody is mutating
   concurrently — the receiver and sender are the *same thread*, sequenced.
   Hybrid's `move` send crosses a task boundary **by definition** — the receiver runs
   concurrently. Importing C++'s caveat imports it *without* C++'s justification.
2. **"Valid but unspecified" is per-type standardese.** It is defined clause by clause
   for standard-library types; user types get whatever their move constructor leaves.
   A Hybrid writes-only freeze would need an equivalent story for every GC composite —
   and over a shared GC heap with a live receiver the state is worse than
   "unspecified": it is **torn** (the receiver may be mid-mutation; invariants can be
   observed broken). C++ never blesses reading an object *while someone else writes
   it* — `std::move` never hands the object to another thread.
3. **The idiom's whole point is handoff-with-disengagement**: `std::move(str)` into a
   container means "I'm done with it"; reading the husk is a rare, deliberate trick
   (e.g., `moved-from == sentinel` checks), not an idiom to port. The ergonomics C++
   buys are the ergonomics of *not actually transferring to a concurrent reader*.

**Net:** C++ is not evidence that a writes-only freeze is safe; it is evidence that a
writes-only freeze is only defensible when nobody else has the object. Hybrid's 19 has
someone else holding the object.

## 5. Verona / Hylo / Val — the mutable-value-semantics and region families

- **Verona** **[V-fetch]** (github.com/microsoft/verona, master README + docs/faq.md +
  docs/publications.md): "a research programming language to explore the concept of
  **concurrent ownership**"; research question #1: "If we design a language **without
  concurrent mutation**, can we build scalable memory management?" Publications:
  *Reference Capabilities for Flexible Memory Management* (Arvidsson, Castegren,
  Clebsch, Drossopoulou, Parkinson, **Noble**, Wrigstad — OOPSLA 2024); *Dynamic Region
  Ownership for Concurrency Safety* (PLDI 2025); *When Concurrency Matters:
  Behaviour-Oriented Concurrency* (OOPSLA 2024). In the cown model, both reads and
  writes of a cown's state go through mutually-exclusive behaviors, so "sender access
  after transfer" is not expressible at all — the sender's next access is itself a
  scheduled behavior that happens-after the transfer **[recalled — from the BOC paper's
  model; fetch the OOPSLA 2024 paper before citing externally]**. Verona's own Python
  note (docs/pyrona.md) **[V-fetch]**: "**Deep Immutability is a key part of any
  ownership model** as we need concurrent threads to be able to share type information
  without risking it being mutated under foot."
- **Hylo (ex-Val)** — already surveyed live in research/ownership-models.md
  (**[V-local]**, fetched 2026-10-11): mutable value semantics, "variables can never
  share mutable state"; concurrency `spawn`s receive **disjoint projections** of a
  split container; "Hylo's foundation of mutable value semantics ensures that ordinary
  code is memory safe, typesafe, and data-race-free." Post-move sender access: the
  moved-from variable holds nothing to read (sink access mode consumed it) — and the
  design has no shared heap for a sender alias to survive into. Model too alien for
  Hybrid's Go heap, as 5-b concluded.
- **Vale (archived) / Valen** **[V-local]** (ownership-models.md): thread-isolated
  memory + message passing; each thread's memory isolated; cross-thread sends are
  copies. No post-transfer sender access exists to permit.

## 6. Academic literature (names; detail level as fetched)

- **Clarke & Wrigstad, "External Uniqueness Is Unique Enough," ECOOP 2003, pp. 176–200**
  **[V-snippet]** (KU Leuven Lirias + Springer + ScienceOpen entries retrieved today;
  "Cited by 238"; the Springer snippet from the paper itself: "…a better approach is
  to **pass the unique references between threads**"). This is the theoretical
  foundation of Hybrid's O5: a single *external* unique reference is enough to
  transfer ownership soundly even when *internal* aliases exist inside the object —
  exactly our "move the binding; freeze every alias" shape. External uniqueness gives
  **no** sender read permission: the unique reference IS the permission, and it left.
- **Boyapati, Lee & Rinard, "Ownership Types for Safe Programming: Preventing Data
  Races and Deadlocks," OOPSLA 2002 (the SafeJava line)** **[recalled — Semantic
  Scholar API rate-limited (429) all session; ACM page is Cloudflare-walled]**. Key
  mechanism for D1: objects can be **frozen** (via a `freezable` owner/annotation) at
  a chosen point, after which they are **read-only and safely shareable across
  threads** — freeze-permits-concurrent-READS. Direction matters: Boyapati's freeze is
  **freeze-to-share**, the *opposite* handoff direction from a move transfer — the
  object becomes immutable for EVERYONE, so concurrent readers (including the old
  owner) are race-free. It is evidence for the Tier-1 "immutable handoff" escape
  valve (§9 below), NOT for a writes-only move freeze. Verify via the PDF before
  quoting externally.
- **Noble, Vitek et al. on flexible alias protection / immutable read-only dominators**
  ("Flexible Alias Protection" OOPSLA 1998; the `L`/immutable-alias protection modes)
  **[recalled]** — same family: read permission is tied to *immutability of the
  object*, never to "the previous owner kept a copy."
- **RustBelt (Jung, Jourdan, Krebbers, Dreyer — "RustBelt: Securing the Foundations of
  the Rust Programming Language," JACM 2018, incl. the Aeneas/iris "typestates for
  Copy/move" `own` model)** **[recalled]** — the formal semantics of moved-from
  values: moving out makes the place's ownership proposition false; any later access
  is the error the proof rules out. The verified model has no read-after-move state.
- **Polonius / NLL (Matsakis, "An alias-based formulation of the borrow checker," 2018)**
  — already covered in ownership-models.md **[V-local]**; loans are reads-or-writes and
  conflict rules key on the *access kind*, not "writes only": a live shared-borrow loan
  conflicts with a mutating loan even though the borrower only *reads*. Rust's own
  checker therefore treats a read as a first-class conflict participant — the same
  asymmetry O5.2 encodes at task granularity.

## 7. Go's own direction — repeatedly declined immutability; `unique` is interning

- **`unique` package, Go 1.23** **[V-fetch]** (go.dev/blog/unique): value interning
  with `unique.Make[T]` returning `Handle[T]` — "two Handle[T] values are equal if and
  only if the values used to create them are equal… the comparison… comes down to a
  pointer comparison." It is identity/interning, **not** ownership or immutability of
  arbitrary values. It cannot carry D1 either way.
- **Read-only / immutable type proposals — all declined or stalled** **[V-fetch]**
  (GitHub issue search over golang/go, titles fetched today):
  - #22048 "proposal: frozen slices / arrays / maps and derivatives (immutable
    subscript-able…)" — **closed**;
  - #27975 "proposal: spec: immutable type qualifier" — **closed**;
  - #29192 "proposal: Go2: read-only and immutability" — **closed**;
  - #31464 "proposal: Go 2: support read-only and immutable values in Go" — **closed**;
  - #37303 "proposal: spec: immutable data" — **open**, no traction;
  - #32245 "proposal: spec: support read-only and practical immutable values in Go" —
    **open**, no traction.
  Go's answer to shared mutable state remains DRF-SC + `-race` (ownership-models.md's
  verified go.dev/ref/mem quotes). So Hybrid cannot lean on a Go-side immutability
  mechanism to justify a permissive reading — and if one ever landed (#22048-flavored
  frozen composites), it would justify the *immutable handoff* valve, not
  read-after-move.
- **Sibling languages in refs/** **[V-local]**:
  - **GALA** (docs/CONCURRENCY_SAFETY.MD): "Only deeply-immutable values may cross" a
    goroutine boundary — `Shareable` is a pure deep predicate; a `var` capture is
    rejected outright; enforcement is field-access-sensitive (immutable-field paths of
    an unshareable whole are accepted). GALA has **no move semantics at all** — its
    sendable set is Hybrid's class 4 + a stricter class 5. Its capture rule is stricter
    than Hybrid's D1 question (it bans even *the closure capturing* a mutable value,
    regardless of later use). GALA's field-access sensitivity is the best Tier-1
    amendment idea for reads: a frozen alias's *immutable-field projections* could be
    readable because nobody — sender or receiver — can write them.
  - **Lisette** (site/src/content/docs/intro/coming-from-rust.md): "Rust moves `s1`
    into `s2`. Lisette has no moves, so `s1` stays usable." — and `let mut b = a`
    makes `b` inherit `a`'s read-only permission (a write through the alias is
    "error: `b` is read-only"). Lisette is the (a)/Go-compatible world: usable-after-
    move, alias-permission policing, and **no race-freedom claim anywhere in the doc**.
    That is precisely the "worse Go" outcome Q1 addition 1 rejects.

## 8. Ergonomics — how expensive is the reads ban, really?

1. **Frequency.** The shape appears in **0/10** spike-6 programs and **1/20** corpus
   programs (19 itself — a deliberately constructed contested pin, not an observed
   idiom). The other freeze rejects (05, 20) are write-forms rejected under every
   reading, so D1's relaxation would change exactly one program's verdict.
2. **Tripwire math.** Relaxation buys **nothing** on the corpus's own friction metric:
   19 is not in the as-written-managed set (01/03/04 — the redesign-level cases); its
   fix is a one-line reorder. The 15.0% as-written number is unchanged whether D1
   relaxes or not. The >~25% tripwire therefore gives zero support for (ii).
3. **The fix is the cheapest diagnostic in the whole corpus.** VERDICTS.md's
   pre-registered fix-it for 19: "snapshot what you need before the send: `n :=
   len(agg)` goes ABOVE `results <- move agg`" — a line move, zero runtime cost, zero
   redesign, no `managed`, no annotations. Compare 04 (mutex pool) where the fix is a
   real restructure. A rule whose worst case is "hoist one line" is not where ergonomics
   budget should be spent.
4. **What real Go code does.** Idiomatic Go *discipline* already treats channel-sent
   composites as handed off (the "share memory by communicating" culture); reading a
   map after sending it is either (a) reading data nobody will ever mutate — which
   Hybrid expresses today as class 4 / `const` / string / fresh-literal sends, legal
   without `move`, sender keeps reading — or (b) a latent `-race` hit. There is no
   third shape. The benign cases are already legal through the immutable classes; D1
   only governs the racy shape. **[recalled — no corpus-mining study exists; treat as
   argument from design intent, not measurement. This is exactly the evidence gap a
   flip would require (§10).]**
5. **What a writes-only freeze would teach.** The compiler would reject
   `agg["total"] = …` while blessing `len(agg)` one line later — telling users reads
   are safe precisely when the receiver is free to mutate. That inverts the lesson
   Go's own memory model teaches and makes HYB-E3003's message incoherent ("the value
   is unsynchronized — except when you only look at it").
6. **Cross-system pattern.** Every system with a race-freedom claim (Rust, Swift,
   Pony, Verona, Hylo, GALA) denies sender reads after transfer; every system that
   permits them (C++, Lisette, Go) has no race-freedom claim. There is no published
   system with a race-freedom claim AND post-transfer sender reads. For a language
   whose positioning is "a guarantee Go cannot give" (research/positioning.md), being
   the first to try is a research project, not an MVP decision.

## 9. RECOMMENDATION

**(i) — keep O5.2 exactly as written: the freeze bans reads and writes, binding and
every live alias. Do NOT relax to writes-only for the MVP. Record (iii)'s two
principled relaxations as the Tier-1 amendment path, adopted only as a logged
amendment with the §9.2 claims paragraph re-scoped in the same edit.**

Reasoning, in priority order:

1. **Soundness dominates.** Under writes-only, program 19 is accepted and is a real
   data race under Go's own definition ([V-fetch] go.dev/ref/mem). §9.2's checked-
   subset sentence becomes false; Q1 addition 1 ("the claim is the product") and
   addition 6 (claims never silently narrowed) make that cost disqualifying by
   construction. The relaxation's benefit (one line of ergonomics in one corpus
   program) is not in the same weight class as its cost (the product's headline
   guarantee).
2. **The precedent is unanimous where it matters.** Rust E0382's own example errors on
   the read; Swift SE-0302's transfer safety is "if and only if the sender stops using
   the data"; SE-0414's relaxation relaxes *what else* the sender may use (regions),
   never the transferred value; Pony calls `iso` "read and write unique" and says the
   sender gives up "the ability to read from or write to" it. C++ permits moved-from
   reads only because its move idiom is single-threaded and it makes no race claim —
   its standard even says callees may assume the xvalue is the only reference.
3. **Ergonomics cost is minimal and measurable.** 0/10 + 1/20 frequency; a one-line
   snapshot fix; zero effect on the as-written tripwire number; the benign variants
   (immutable data) are already legal via class 4/O5.3 today. The strict rule's real
   cost is a teaching moment, and the diagnostic (pre-registered in VERDICTS.md for
   19) already carries the snapshot fix-it and discloses the D1 controversy in the
   message itself.
4. **The long-term direction also argues against (ii).** The principled future is not
   "reads of moved mutable values" but "reads of provably immutable values" — Pony's
   `val`/`trn`, Swift's `Sendable`+regions, Boyapati's FROZEN, Go's frozen-composites
   idea, GALA's Shareable, and Hybrid's own class 4 + O5.3 already being that seed.
   Adopting (ii) now would move Hybrid toward C++'s "unspecified state" semantics and
   make the later immutable-handoff valve *harder* to explain, not easier.

**What would change this (falsifiers, not preferences):** see §10.

## 10. Long-term plan — what would flip it, and what Tier-1 "immutable handoff" looks like

**Evidence that would justify flipping 19's verdict later (all currently absent):**

1. **A measured idiom study**: mining real Go repositories for read-after-send of the
   same reference, split by "receiver provably never writes" — if that shape is common
   AND receivers are typically read-only, a logged amendment to VERDICTS.md (19 REJECT
   → ACCEPT) plus a re-scoped §9.2 becomes defensible. Nobody has this data; the
   corpus's tripwire (§9.7) should add a dedicated counter for HYB-E3003 read-form
   rejections so the checker era produces it for free.
2. **A type-level immutability mechanism landing first** (OQ5 const composites pinned,
   then a `val`-like qualifier) — if it lands, the relaxation question becomes moot:
   senders keep reading *immutable* values legally with no claim change, which is the
   sound version of what (ii) is reaching for.
3. **Swift-style region analysis** proving at the send site that the receiving task
   never mutates — requires cross-task whole-program reasoning Tier-0 deliberately
   lacks (loans are function-local by design); if ever built, it subsumes (ii) safely.

**Tier-1 "immutable handoff" (the escape valve to design toward, NOT MVP):**

- **Shape:** an explicit freeze-to-immutable transition at the send site — e.g.
  `results <- freeze agg` (or `move const agg`): ownership transfers AND the value
  becomes deeply immutable for everyone. The sender's aliases become read-only views
  (reads legal, writes still HYB-E3003); the receiver owns an immutable value it
  cannot mutate. Pony `trn`→`val` and Boyapati FROZEN are the precedents; Go #22048
  is the would-be Go-native analogue.
- **Why it must be Tier-1:** it requires read-only *view types* (deep immutability as
  a type property, GALA's Shareable predicate over the curated Go surface) — a real
  type-system feature Tier-0 consciously excludes. It also needs OQ5 (const
  composites) settled first, since it is the same mechanism generalized from `const`
  literals to runtime-frozen values.
- **What it buys:** the common benign read-after-send cases (log-a-stat, dashboards,
  config handoff) become legal **without** weakening §9.2 — the claim stays true
  because nobody can write. That is the honest resolution of the ergonomics pressure
  D1 is proxying for.
- **GALA-style refinement worth recording alongside:** field-access-sensitive reads
  through frozen aliases (immutable-field projections are readable because those
  fields are unwritable by anyone) — a strictly-smaller version of the same idea that
  reuses the class-4 machinery per-field instead of per-value.

**Ordering:** pin OQ5 (const composites, already in VERDICTS.md open questions) at
MVP-0 → treat `freeze`/immutable-views as a Tier-1 amendment candidate next to OQ2's
lock-mediated sharing → revisit D1 only with checker-era HYB-E3003-read-form
tripwire data in hand.

## 11. Proposed SPEC-LANGUAGE.md D1 paragraph (for the lead to adapt)

> **D1 — freeze-after-send covers reads (O5.2): DECIDED for the MVP; relaxation
> recorded as a Tier-1 path, not adopted.** After an owned `move` send, every live
> alias in the sending task is frozen: any access — read **or** write — is
> `HYB-E3003`. Reads are banned because Go's memory model defines a concurrent
> unsynchronized read/write pair as a data race (go.dev/ref/mem), so a writes-only
> freeze would admit programs (corpus 19) that violate the §9.2 claims paragraph;
> per the Q1 ruling, the claim is the product and is never silently narrowed. This
> matches every comparable race-free system: Rust E0382 errors on the moved-from
> read; Swift SE-0302's transfer safety holds "if and only if the sender stops using
> the data"; Pony's `iso` is "read and write unique." C++'s permissive moved-from
> reads ("valid but unspecified state") are explicitly rejected as a model: C++'s
> move idiom is single-threaded and C++ makes no race-freedom claim — neither
> premise holds for a task-boundary send. The ergonomic cost is bounded: the
> pre-registered fix for the read form is a snapshot (hoist the read above the send),
> the benign variants are already legal through immutable-by-type sends (O4 class 4,
> O5.3), and the tripwire metric is unchanged by either reading. A future Tier-1
> **immutable handoff** (`freeze`-to-immutable at send; Pony `val`/Boyapati-FROZEN
> direction) may restore sender reads *soundly* — by making the value unwritable by
> everyone — as a logged amendment that re-scopes §9.2 in the same edit. Flipping
> 19's verdict before that requires: measured evidence that read-after-send of a
> mutable value is idiomatic Go **and** receivers are provably read-only, or a
> region-based analysis proving receiver non-mutation (Swift SE-0414's shape); none
> exists today.

---

## Verification log (what was actually fetched, 2026-10-12)

Fetched live via page_reader/curl and quoted above: doc.rust-lang.org E0382 + Book
ch04-01; library/core/src/marker.rs (Freeze trait); crates.io API (moveit, ice,
frozen-collections); apple/swift-evolution raw proposals 0302, 0414, 0390 (+ evolution
index for 0337's title/state); pony-tutorial repo (docs/reference-capabilities/index,
consume-and-destructive-read, passing-and-sharing, guarantees, aliasing — via
raw.githubusercontent after the JS-rendered site failed); en.cppreference.com/w/cpp/utility/move;
microsoft/verona README + docs/faq.md + docs/publications.md + docs/pyrona.md;
go.dev/blog/unique; go.dev/ref/mem; golang/go issue search results (titles/states for
#22048, #27975, #29192, #31464, #37303, #32245 — GitHub API core limit exhausted
before issue bodies could be fetched). Search snippets only: Clarke & Wrigstad ECOOP
2003 (three independent index pages); IRLO "`&move` sketch" (2023) and users.rust-lang
"ramblings about `&move`" (2021). Local clones ([V-local]): refs/gala
(CONCURRENCY_SAFETY.MD), refs/lisette (coming-from-rust.md). Not fetched (flagged
[recalled]/[unverified] inline): Boyapati OOPSLA 2002 details (Semantic Scholar 429,
ACM Cloudflare-walled), RustBelt details, Noble flexible-alias-protection details,
Verona cown behavior-exclusivity mechanics, pre-1.0 Rust `unique` (no primary source
found — do not cite), any GitHub issue bodies, real-world Go idiom frequency (no
study exists).
