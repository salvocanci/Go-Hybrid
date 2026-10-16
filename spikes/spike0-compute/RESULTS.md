# Spike 0: Compute smoke tests (Kaggle worker + GitHub Actions fleet)

**Status:** hypothesis pre-registered 2026-10-11 (before any run; per SPEC §14.7 "pre-register thresholds").
**Job:** `jobs/001-spike0-kaggle-smoke` (Kaggle) and `.github/workflows/heavy.yml` dispatch `spike0` (Actions).

## Hypothesis

The two remote tiers (Kaggle worker via API, GitHub Actions standard runners) are usable for
the compute roles SPEC §2 assigns them: Kaggle = one-big-machine jobs, Actions = embarrassingly
parallel shard fleet. Unverified specifics we expect to CORRECT: real Kaggle core count (SPEC
says "reportedly 16"), session limits, internet/secret availability in API-launched runs, and
real Actions runner hardware (reportedly 4 vCPU/16 GB public, 2 vCPU/7 GB private — repo is
public).

## Pass/fail thresholds (pre-registered)

**Part A — Kaggle worker (job 001):**
| # | Metric | PASS | FAIL |
|---|--------|------|------|
| A1 | End-to-end: job submitted→results fetched | completes | unusable after 2 retries |
| A2 | Wall clock (queue + install + run) | < 45 min | > 90 min |
| A3 | Pinned Go + Rust install (minimal) | both build hello-world | either fails |
| A4 | Internet from API-launched run | repo clone at SHA works | blocked |
| A5 | Reported cores / RAM / disk | recorded whatever is true | n/a (measurement) |

Decision table (from SPEC §5 Spike 0): works→adopt two-tier protocol; no internet→source via
private dataset; high friction→batch-only; unusable→Actions + sandbox-only fallback.

**Part B — Actions fleet (workflow `heavy`, dispatch `spike0`):**
| # | Metric | PASS | FAIL |
|---|--------|------|------|
| B1 | 4-shard matrix runs + reduce merges summary.json | yes | no |
| B2 | 20-shard run: measured concurrency | ≥ 16 concurrent | < 8 |
| B3 | Per-shard: pinned toolchains + Go/Rust hello-world | all green | any red |
| B4 | Artifact size per shard | < 1 MB | > 10 MB |
| B5 | Queue latency per shard (p50) | < 3 min | > 10 min |

Decision table: 20 concurrent + clean merge→adopt as written; fewer→lower default max-parallel;
minutes tight→(N/A: repo public, standard runners free); unusable→Kaggle + sandbox fallback.

## Method

- One generic runner (`tools/runner/runner.py`, stdlib-only Python) executes `job.json` on all
  tiers; Kaggle kernel (`worker/script.py`) and the Actions workflow are thin wrappers.
- Jobs always run a pinned commit SHA of this public repo (no secrets leave the sandbox; the
  worker clones anonymously).
- Kaggle: `kaggle kernels push` (private kernel, internet on, GPU off), poll with backoff,
  `kaggle kernels output` fetch.
- Actions: `workflow_dispatch` with `sha` + `shards` inputs; shards assigned deterministically
  (shard id = i % n); `reduce` job merges `summary.json` fragments.

## Results

### Part A — Kaggle (job 001, kernel v2, run at SHA f09dce93)
- Run at SHA: f09dce93de0b9fe7187cc307f6d98d6d4c58b6da (sha-check exit=0)
- Submitted (UTC): 17:58:43 → kernel log shows run start 17:58:54 → complete ≈17:59:25 → **end-to-end ≈ 42 s** (queue ≈ 11 s; kernel run 30.94 s)
- Queue latency / startup: ~11 s from `kaggle kernels push` to first log line
- Toolchain install: go **3.5 s** (67 MB tarball), rust **17.8 s** (rustup minimal, 1.99.0)
- Environment: **nproc = 4** (Xeon 2.2 GHz, 2 cores × 2 threads, KVM guest); RAM 32 GB seen / **cgroup limit 30 GB**; disk: overlay 8 TB visible (no per-kernel quota hit); zone europe-west4-c; run type Batch
- Internet: **works** (git clone of the public repo at the pinned SHA succeeded)
- Preexisting toolchains: gcc 13.3, git 2.43; **no Go, no Rust** (image ships Python 3.13)
- Hello-world Go: **pass** (9.2 s incl. first module fetch); Rust: **pass** (0.45 s)
- Output size seen / limit hit: ~10 KB; no limit hit
- Session limit observed: not reached (kernel finished in 31 s); Kaggle-documented CPU limit 12 h — UNVERIFIED this run

### Part B — Actions (workflow heavy / spike0, pinned SHA cd21089)
- Final 4-shard run (id 38163370515): **4/4 shards success**, gen 4 s, shards ≈25 s each, reduce 6 s, run total ≈35 s
- Final 20-shard run (id 38163372872): **20/20 shards success**, all 20 started within a 7 s window (full concurrency; no queuing), shard wall clock 12.3–17.9 s, merge clean (`fleet-summary.json` ok=true, all step exits 0)
- Queue latency: dispatch → first shard start ≈ **10–17 s** (p50 well under the 3 min threshold)
- Runner hardware (from shard env report): **4 vCPU, 16 GB RAM**, Ubuntu 24.04, Azure (westcentralus), runner 2.337.0
- Artifacts: ~3 KB per shard, 1.4 KB fleet summary (retention 1–3 days as configured)
- Hardening found + fixed 4 real bugs (each verified by a re-run): (1) `::set-output` disabled on current runners → `$GITHUB_OUTPUT`; (2) `strategy.max-parallel` needs `fromJson()` on string inputs — silently yields zero shards otherwise; (3) job input must be the `jobs/` dir name, not a shorthand; (4) runner needs `--repo-dir` on runners (checkout root ≠ `./repo`). Plus worker-side: `go mod init` needed for hello-world (module mode), runner `cwd:"repo"` double-join bug.

Threshold outcomes: A1–A5 all PASS; B1–B5 all PASS.

## Verdict

**Part A:** "End-to-end works with acceptable latency" → **adopt the two-tier protocol as written, with corrected facts** (worker = 4 cores / 30 GB cgroup / ~50 s round-trip for small jobs — it is a *modest* big-machine tier, not a 16-core monster; batch related commands accordingly).
**Part B:** "20 shards run concurrently and merge cleanly" → **adopt the shard protocol as written.** Runner fleet confirmed at 20 concurrent × (4 vCPU/16 GB), ~10 s queue, artifacts negligible.
Repo is public → standard-runner minutes free; record usage after each fleet run in PLAN.md anyway (ToS care).
