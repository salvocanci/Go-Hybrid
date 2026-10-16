# QUESTIONS.md — escalations to the human

Protocol (SPEC.md §9): for credentials/destructive actions/weeks-costly-wrong/legal/budget items only.
Each entry: context, options, our recommendation, and what we do in the meantime.
Design choices are decided autonomously per the decision rules and logged in PLAN.md.

**Escalation bar (tightened 2026-10-12, per human process note):** a question
lands here only if it is *expensive to reverse* (language-level promises,
legal, credentials, destructive, budget). A design choice reversible in an
afternoon is a PLAN.md Decision Log entry, not an escalation. Fewer, sharper
escalations get faster, better answers. Retroactively applied: Q2 below was
reclassified as a design decision by the human and lives in PLAN.md.

## Open questions

(none — Q1 and Q2 were both resolved on 2026-10-12; see below)

## Resolved questions

### Q1 — Tier-0 sendability reading — **RESOLVED 2026-10-12 by the human (owner)**

**Ruling: (c)+(b), the strictest reading.** Kept as a properly-qualified
escalation (a language-level promise is expensive to reverse). The human's
additions, all binding on SPEC-LANGUAGE.md:

1. **The claim is the product.** Go-compatible (a) would make Hybrid "a
   worse Go"; the only reason to adopt a new language over Go is a guarantee
   Go cannot give. Strict is the only reading that earns a market position.
2. **Spike 6 is weaker evidence than it looks** — the ten programs were
   chosen by us, so selection bias is built in. The adversarial corpus is
   what actually tests the decision. **The adversarial programs are written
   BEFORE the checker lands and are treated as the spec.** If a strict rule
   rejects code real Go programmers write daily (shared map across tasks, a
   worker pool mutating a shared struct), we must know before shipping.
3. **Friction must be diagnostic, not punitive.** "Not sendable" is hostile;
   "this map is shared across tasks; wrap it in `managed`, or send ownership
   with `move`" is a teaching moment. Real time is budgeted for fix-it
   suggestions in checker diagnostics. People forgive strictness when the
   compiler says exactly what to do.
4. **Name the escape hatch honestly.** `managed` is greppable, auditable,
   and countable per project (`--report-managed`) — turning the escape
   hatch into a visible trust metric instead of a hidden hole.
5. **Tripwire armed.** Reopen G0 if more than ~25% of the adversarial corpus
   needs `managed`, OR if reviewers consistently hit the same rejection on
   idiomatic patterns. Without a tripwire, "provisional" becomes permanent
   by inertia. (The ~25% figure is the lead's concretization of "more than
   ~X%" — the human left the number open; recorded as tunable.)
6. **No overclaiming.** SPEC-LANGUAGE.md states the race-freedom claim ONLY
   for the checked subset, with the `managed` boundary in the same paragraph.
   Overclaiming safety is the fastest way to lose credibility with exactly
   the audience that cares.

**Provisional marking requirement:** the decision is recorded as PROVISIONAL
with the three alternatives — (a) Go-compatible, (b) freeze-after-send alone,
(c) safe-by-type alone — and the reason each was rejected, so a reviewer can
reverse it cheaply. Rejection reasons: (a) = no race-prevention claim = no
reason to exist; (b) alone = partial claim, still permits shared-mutable
aliasing at spawn; (c) alone without freeze = move semantics incomplete
(sender could race on the moved value's aliases).

**Effect:** SPEC-LANGUAGE.md Tier-0 chapter is written under (c)+(b) with
items 1–6 above as normative requirements, not commentary.

### Q2 — Thread budget: derived-by-probe vs configured-by-default — **RESOLVED 2026-10-12 by the human; RECLASSIFIED as a design decision (process note)**

The human's process ruling: Q2 did not meet the SPEC §9 escalation bar — it
is a design choice reversible in an afternoon. It is recorded in PLAN.md's
Decision Log with the human-endorsed tightened design, and future questions
of this class stay out of QUESTIONS.md.

**Ruling: (b) — configurable default + probe — with tightening** (see PLAN.md
Decision Log 2026-10-12 for the full binding design): ceiling = configured
value only; probes and rlimit/pids.max may LOWER the effective budget, never
raise it (invariant, explicitly tested); default derived as
`min(512, 0.5 × pids.max)` when readable; effective budget + source
(`configured` / `lowered-by-probe` / `lowered-by-rlimit`) logged at startup;
failure mode at the budget documented (queue/backpressure/error); docs note
the ceiling is raisable (`max_threads`) on high-pid environments.
