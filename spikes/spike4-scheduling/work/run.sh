#!/usr/bin/env bash
# Spike 4 build + run (sandbox tier; also run verbatim by jobs/005 on the worker
# with SPIKE4_WORKER=1). No ripgrep dependency (the Kaggle image has no rg).
# INFRA LESSON (session 2): never pipe live producers into head/tail — SIGPIPE
# silently kills suites and masks exit codes. Write files, then display.
set -e
cd "$(dirname "$0")"

# 1. Rust staticlib (respects CARGO_TARGET_DIR; symlink the conventional path)
(cd rust && cargo build --release -j2)
if [ -n "$CARGO_TARGET_DIR" ]; then
  LIBDIR="$CARGO_TARGET_DIR/release"
else
  LIBDIR="$(pwd)/rust/target/release"
fi
mkdir -p rust/target
ln -sfn "$LIBDIR" rust/target/release
ls -la rust/target/release/libhyblock.a

cd go

# 2. gofmt + vet gates
gofmt -l . | tee ../fmt.out
test ! -s ../fmt.out
go vet ./... 2>&1 | tee ../vet.out
test ! -s ../vet.out

# 3. canary + safety tests, WITH race detector (the M2 linkname behavior pin)
echo "=== canary + safety (race) ==="
go test ./spike4/ -race -count=1 -v \
  -run 'TestOffsetsCanary|TestM2CanaryPReleased|TestM2NoDeadlock|TestPoolRoundTrip|TestPoolNoTicketLoss' \
  > ../canary.out 2>&1 || { cat ../canary.out; exit 1; }
grep -E "^(--- (PASS|FAIL)|ok|FAIL)" ../canary.out

# 4. race leg (1k safety cells per mechanism)
echo "=== race leg (1k cells) ==="
go test ./spike4/ -race -count=1 -v -run 'TestRaceLeg' > ../race.out 2>&1 || { cat ../race.out; exit 1; }
grep -E "^(--- (PASS|FAIL)|ok|FAIL)" ../race.out

# 5. M4 exhaustion demo (sandbox: 2000 threads; worker overrides via SPIKE4_M4N)
echo "=== M4 thread-per-call demo ==="
go test ./spike4/ -count=1 -v -run 'TestM4ExhaustionDemo' > ../m4.out 2>&1 || { cat ../m4.out; exit 1; }
grep -E "^(--- (PASS|FAIL)|ok|FAIL|.*spawning|.*spawned|.*spawn wall)" ../m4.out

# 6. the load matrix (sandbox leg: 1k + 10k; worker leg: anchor + 100k via env;
#    the worker SKIPS the sandbox legs — the worker's own anchor cells carry the
#    cross-tier comparison, and job 005's first run showed the duplicated legs
#    cost ~20 min of worker time for data the anchors already provide)
echo "=== load matrix ==="
rm -f ../matrix.sandbox.jsonl ../matrix.race.jsonl ../matrix.worker.jsonl
if [ "${SPIKE4_WORKER:-0}" != "1" ]; then
  go test ./spike4/ -count=1 -v -run 'TestMatrixSandbox' -timeout 2400s > ../matrix.out 2>&1 || { cat ../matrix.out; exit 1; }
  grep -E "^(--- (PASS|FAIL)|ok|FAIL)|^ *matrix_test.go:" ../matrix.out | head -90
else
  : > ../matrix.out
fi
if [ "${SPIKE4_WORKER:-0}" = "1" ]; then
  go test ./spike4/ -count=1 -v -run 'TestMatrixWorker' -timeout 3000s >> ../matrix.out 2>&1 || { cat ../matrix.out; exit 1; }
  grep -E "^(--- (PASS|FAIL)|ok|FAIL)|^ *matrix_test.go:" ../matrix.out | tail -40
fi

# 7. dispatch-cost benchmarks (count=10)
echo "=== dispatch benches (count=10) ==="
go test ./spike4/ -run '^$' -bench . -benchmem -count=10 > ../bench.sandbox.out 2>&1 || { cat ../bench.sandbox.out; exit 1; }
grep -E "^Benchmark" ../bench.sandbox.out

# 8. medians + S1-S6 verdicts
python3 ../analyze.py 2>&1 | tee ../verdicts.out
echo "done: matrix.sandbox.jsonl, matrix.race.jsonl, canary.out, race.out, m4.out, matrix.out, bench.sandbox.out, verdicts.out"
