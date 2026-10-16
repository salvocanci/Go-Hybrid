# Bounty program study: how the top programs actually run

Written 2026-10-14 to ground [BOUNTY.md](../BOUNTY.md) in what mature programs
do, before scaling ours up. Sources are public program pages and postmortems;
each lesson below names what we changed or confirmed.

## Programs studied

| Program | Model | What we took from it |
|---------|-------|----------------------|
| Google OSS VRP (bughunters.google.com) | Fixed rewards + public recognition across Google's open source projects | Public recognition is a first-class payout, not an afterthought. Also the cautionary tale: Google SUSPENDED submissions after an influx of invalid (AI-volume) reports. A queue that cannot pause dies loudly. |
| GitHub's own bug bounty (github.blog) | Two-tier, fixed amounts per severity; low-impact reports moved to swag after program review | Fixed per-severity amounts are easier to run and explain than ad-hoc negotiation. Low-impact reports need a non-cash lane or the cash pool drowns. |
| Intersect / Cardano OSS committee | Critical/High/Medium/Low tiers with published amounts, annual budget | Publish the tier SHAPES up front; the budget boundary is stated, not hidden. |
| Zcash ecosystem (ZCG $1M initiative, librustzcash + zebra SECURITY policies) | Dedicated fund; maintainers score to PRIORITIZE, "not a metric to be gamed"; structured disclosure goals (protect users, respect researchers) | Severity is assigned BY the maintainer. Reporters propose; maintainers decide. Written disclosure goals keep both sides honest. |
| disclose.io (community standard) | Standard safe-harbor language and disclosure terms | Our safe-harbor clause follows its shape: authorization, scope limits, stop-and-report, good faith. |
| OSS-Fuzz (Google) | Rewards for integration + bug bounties on found vulns; 10,000+ vulns across 1,000 projects | Payment follows the TOOL reproducing it, not a human believing it. Our CI-must-pass rule is the same idea at PR time. |
| Triage write-ups (zeropath, safeguard.sh, Sophos) | Reproduce or rule out EVERY report; check history for duplicates; safe harbor speeds up reporting | 60 to 80% of submissions in small programs end up invalid. The defense is a written ineligible list plus a report recipe, not patience. |

## Lessons we already had in place

- Pay only after reproduction (OSS-Fuzz's core rule, our #1 payment rule).
- Severity tiers published up front (GitHub, Intersect).
- Safe harbor in disclose.io shape.
- Duplicate rule: first reporter is paid, later reporters credited.
- Recognition ladder: report, triage, regular, trusted (community-ladder pattern).

## Lessons applied in this pass

1. **An explicit INELIGIBLE list** (zeropath/Sophos): crashes that produce a
   clean diagnostic are the fail-closed system working, not bugs; findings in
   dependencies go upstream; style preferences without functional impact are
   not security reports. This kills the largest invalid-report class before
   it costs anyone time.
2. **Scoring is the maintainer's call** (librustzcash): reporters propose a
   tier, maintainers assign it. One sentence, prevents tier-gaming arguments.
3. **Pause over die** (Google OSS VRP postmortem): if invalid volume floods
   the queue, the program pauses with an announcement instead of quietly
   rotting or banning everyone. The bounty survives its own success.
4. **A report recipe** (safeguard.sh): check the known-issues list, run
   against latest main, smallest `.hy` repro, expected vs actual. Reports
   written this way are the ones that survive triage.

## What we deliberately did NOT adopt

- Cash per report outside a ranked cycle (our $500 pool is fixed; per-report
  cash on a zero budget is how programs die owing money).
- A paid triage platform (HackerOne et al.) at our scale: Discussions +
  issues + a 48-hour SLA is the honest version of what we can staff.
- Bounty amounts that scale with lines of code or report length: meaning
  ranks contributions here, not size.
