# MOONSHOT — the Wildcard Track ledger

**This file is the public home of the Wildcard Track**: the $500-per-cycle
bounty for revolutionary, contrarian, high-risk ideas that a normal feature
bounty would reject (rules and payout split in
[BOUNTY.md](BOUNTY.md) Track 3; triage and ops run by the project's AI
maintainer, with the maintainer keeping the final say and every decision
getting a written reason — same as the ladder).

Its purpose: **breakthroughs, not incremental improvements.** No working
prototype is required — this is purely a place for us to analyze people's
crazy ideas and thoughts. Breaking changes, new paradigms, rewrites, and
"impossible" ideas are explicitly allowed. **Failure is a valid outcome if
it produces knowledge — and every outcome, including every failure, is
published here.** We are hunting for the unique approaches or additions
that make a paradigm shift without breaking everything; where the
cost-to-ROI line sits is our call, and we say so in writing, per entry.

---

## How an idea moves through this file

```
received → triaged (≤48h) → scheduled → in-review → M1 accepted ($250)
        → in-progress → M2 learning published ($250) → paid
        ↘ declined (reason published)   ↘ failed (post-mortem published, M2 paid)
```

- **Intake:** open an issue with the
  [`wildcard` template](https://github.com/limitlessprojects/Go-Hybrid/issues/new?template=wildcard.yml);
  it auto-labels `wildcard` + `💎 Bounty`. Triage within 48 hours: entered
  into the ledger below, or declined with a published reason (a good
  decline is itself a learning — see the wall).
- **Review scheduling:** a public review window opens on the **1st of each
  month** in Discussions; every ledger entry gets a slot. P0-class
  soundness insights that fall out of a proposal bypass the calendar and
  follow the GUARANTEES.md protocol.
- **Milestones:** every entry carries named, dated milestones; the ledger
  is the single source of truth and is updated on every state change.
- **Payouts:** **$250 on acceptance (M1) + $250 when the learning is
  published (M2) — success or failure alike.** One wildcard winner per
  cycle; a learning that publishes in a later cycle rides that cycle's
  budget. Winners are announced in release notes and the Hall of Fame,
  same as the ladder.
- **Solicitation is active, not passive:** the calendar below names the
  assumptions we want attacked *this cycle*. Don't wait for an invitation
  that matches your idea exactly — attack adjacent assumptions too.

---

## Ledger

| ID | Proposal (one line) | Author | Source | Status | Review scheduled | Milestones | Payout | Outcome |
|----|---------------------|--------|--------|--------|------------------|------------|--------|---------|
| W-000 | *Track founded 2026-10-15* — owner decision adding the Wildcard Track ($500/cycle) to the bounty program; ops delegated to the AI maintainer | owner | BOUNTY.md Track 3 | **M1 accepted** | 2026-11-01 window | M1 done · M2 = this file | $250 (logged) | track live |

*(empty beyond the founding row — the next row is reserved for the first
community wildcard; the solicitation prompts below name what we want to
see)*

---

## Published learnings (all outcomes — successes and failures)

Format per entry: **Proposal → Verdict → What we learned → Cost.** Nothing
is redacted for looking bad; a failed moonshot that teaches us where the
wall is is worth exactly as much here as an accepted one.

### L-000 — Founding decision: pay for ideas that fail (2026-10-15)

- **Proposal:** the Wildcard Track itself — pay for ideas the normal
  ladder structurally filters out, splitting the payout so the *published
  learning* earns its half even when the idea dies.
- **Verdict:** adopted by the owner as Track 3 of the bounty program.
- **What we learned (why this shape):** a feature bounty pays for merging,
  so it selects for incremental improvements by construction — anything
  that breaks the thing being improved cannot win it. Paying for the
  analysis instead of the merge inverts that filter: a paradigm-scale idea
  only has to be *falsifiable*, not mergeable, to earn. The repo already
  runs this pattern internally — the spike protocol pre-registers
  hypotheses and commits results *before* knowing them, and several
  "failed" spikes are exactly what de-risked the architecture that shipped.
  The Wildcard Track points that machinery outward.
- **Cost:** $500 per cycle + the review bandwidth to publish honestly.
  Deliberately accepted as the price of not being blind-sided by the idea
  we would have rejected.

---

## Failure wall

| ID | Idea | Why it died | What we learned |
|----|------|-------------|-----------------|
| — | *empty — kept here so it stays that way in public* | — | — |

*(Declined entries appear here with the published reason once the ledger
has them. A decline is not a judgment that the idea is bad — it is a record
of why we are not spending review bandwidth on it now, written so a
contributor can overturn it with one good argument.)*

---

## Active solicitation — what we want attacked this cycle

We actively solicit wildcard proposals; each cycle names the assumptions we
most want contradicted. Current prompts (answered via the wildcard
template):

1. **Kill the `.hy` / `.go` split.** Whole-module checking, or checking
   that attaches to ordinary Go via annotations — what would it take, and
   what guarantee dies with it?
2. **Replace the borrow-checker machinery.** Capability tokens,
   linear-type encodings inside Go's type system, runtime-enforced
   ownership — anything that deletes the alias/loan/freeze analysis rather
   than extending it.
3. **Attack the emit target.** Plain Go source is the current paradigm.
   Propose and analyze: emit to Go *IR*, a hybrid Go+Go-asm target, or
   deleting the Rust staticlib boundary entirely.
4. **"Impossible" guarantees.** Deadlock-freedom, async-cancellation
   safety, heap-freedom proofs for the checked subset — pick a guarantee
   GUARANTEES.md explicitly does not make and argue it is reachable.
5. **Rewrite us.** If the whole compiler should be a Go program
   (self-hosted analysis), a WASM engine, or a library rather than a CLI —
   say why and what it unlocks.

The standing invitation: **if you believe something in SPEC.md or
GUARANTEES.md is wrong, the Wildcard Track is the sanctioned place to say
so loudly.**

---

## Honest limits of this ledger

- Triage within 48 hours and the monthly windows are the AI maintainer's
  commitment; the maintainer keeps the final say on accept/decline/tier,
  every decision gets a written reason, and the owner retains budget
  authority and final appeal — the same governance as the ladder.
- Acceptance (M1) means "worth analyzing in public", not "will ship".
  Shipping decisions stay with the roadmap (PLAN.md) and its review gates.
- Learnings are published as written arguments, not verified measurements,
  unless an entry says a spike/job backed it — measurement-class claims
  still go through the spike protocol (pre-registered, committed results).
