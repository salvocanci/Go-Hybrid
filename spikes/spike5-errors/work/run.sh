#!/usr/bin/env bash
# Spike 5 build + run (sandbox tier; also run verbatim by jobs/004 on the worker).
# Usage: bash spikes/spike5-errors/work/run.sh
# No pipes into `head` on live producers (SIGPIPE lesson from Spike 3's run.sh).
set -e
cd "$(dirname "$0")"

# 1. Rust staticlib
(cd rust && cargo build --release -j2)
if [ -n "$CARGO_TARGET_DIR" ]; then
  LIBDIR="$CARGO_TARGET_DIR/release"
else
  LIBDIR="$(pwd)/rust/target/release"
fi
mkdir -p rust/target
ln -sfn "$LIBDIR" rust/target/release
ls -la rust/target/release/libhyerr.a

cd go

# 2. gofmt + vet gates
gofmt -l . | tee ../fmt.out
test ! -s ../fmt.out
go vet ./... 2>&1 | tee ../vet.out
test ! -s ../vet.out

# 3. correctness probes (safe set, WITH race detector; panic probe spawns a child)
echo "=== safe probes (race) ==="
go test ./spike5/ -race -count=1 -v 2>&1 | tee ../probe.out | grep -E "^(--- (PASS|FAIL|SKIP)|ok|FAIL)" || true
if grep -q "^--- FAIL" ../probe.out; then echo "PROBES FAILED"; exit 1; fi

# 4. benchmarks (count=10, both packages)
echo "=== benchmarks (count=10) ==="
go test ./hybridge/ -run '^$' -bench . -benchmem -count=10 > ../bench.sandbox.out 2>&1 || { cat ../bench.sandbox.out; exit 1; }
go test ./spike5/ -run '^$' -bench . -benchmem -count=10 >> ../bench.sandbox.out 2>&1 || { cat ../bench.sandbox.out; exit 1; }
grep -E "^Benchmark" ../bench.sandbox.out | head -40

python3 ../analyze.py ../bench.sandbox.out || true
echo "done: bench.sandbox.out, probe.out, fmt.out, vet.out"
