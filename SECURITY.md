# Security policy

Hybrid is a safety-checked compiler. A program that Hybrid **accepts** but
that is **unsound** is a P0 by definition. If you find one, we want it.

## How to report

1. Open an issue with the
   [`soundness` template](https://github.com/limitlessprojects/Go-Hybrid/issues/new?template=soundness.yml).
2. Include the exact commit, the smallest `.hy` repro, and expected vs actual.
3. We acknowledge within **48 hours** with a first verdict and a reason.

Nothing here is a paid penetration target, a support channel, or a place for
bulk automated scanning. See
[BOUNTY.md](BOUNTY.md) for scope, rules of engagement, and the ineligible
list before you report.

## What happens next

- We reproduce or rule out every report. Nothing is closed as "cannot
  reproduce" without the reason written down.
- A confirmed soundness bug is a P0: it gets a corpus regression test
  (accepted-but-unsound before the fix, rejected after) and a public
  advisory entry in [GUARANTEES.md](GUARANTEES.md) once fixed.
- Valid reports are credited in the Hall of Fame
  ([BOUNTY.md](BOUNTY.md)) and are eligible for the bounty pool.

## Safe harbor

Good-faith security research that follows [BOUNTY.md](BOUNTY.md) is
authorized and we will not pursue legal action over it. Stay in scope, use
your own repos and test data, and stop and report the moment you find
something.

## Supported versions

Security fixes land on `main` first. Release v0.1.0 is the current tagged
line; we do not backport to older tags.
