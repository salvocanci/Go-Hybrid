#!/usr/bin/env bash
# Spike 3 build + run (sandbox tier; also run verbatim by jobs/003 on the worker).
# Usage: bash spikes/spike3-memory/work/run.sh
# No ripgrep dependency (the Kaggle image has no rg); grep -E everywhere.
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
ls -la rust/target/release/libhyarena.a

cd go

# 2. gofmt + vet gates (generated-looking code must be clean)
gofmt -l . | tee ../fmt.out
test ! -s ../fmt.out
go vet ./... 2>&1 | tee ../vet.out
test ! -s ../vet.out

# 3. escape-analysis evidence for the P7/P8 probes (heap vs stack placement)
go test -gcflags='-m -l' -c -o /dev/null ./spike3/ 2> ../escape.out || true
grep -E "moved to heap" ../escape.out | head -20 || true

# 4. correctness probes (safe set, WITH race detector)
echo "=== safe probes (race) ==="
go test ./spike3/ -race -count=1 -v 2>&1 | tee ../probe.out | grep -E "^(--- (PASS|FAIL|SKIP)|ok|FAIL)" || true
if grep -q "^--- FAIL" ../probe.out; then echo "PROBES FAILED"; exit 1; fi

# 5. hazard probes (deliberate UB; NO race detector, gated)
echo "=== hazard probes (P7/P8) ==="
SPIKE3_UNSAFE=1 go test ./spike3/ -run 'TestUnpinnedHeapHazard|TestStackHazard' -count=1 -v 2>&1 | tee ../hazard.out | grep -E "^(--- (PASS|FAIL|SKIP)|P7|P8|ok)" || true

# 6. benchmarks (count=10, both packages: spike3 suite + hybridge direct crossings)
# NOTE: no pipes into `head` on the live producer — SIGPIPE would silently kill
# go test mid-suite (found the hard way). Write the file, then display from it.
echo "=== benchmarks (count=10) ==="
go test ./hybridge/ -run '^$' -bench . -benchmem -count=10 > ../bench.sandbox.out 2>&1 || { cat ../bench.sandbox.out; exit 1; }
go test ./spike3/ -run '^$' -bench . -benchmem -count=10 >> ../bench.sandbox.out 2>&1 || { cat ../bench.sandbox.out; exit 1; }
grep -E "^Benchmark" ../bench.sandbox.out | head -40

# 7. medians + derived figures for RESULTS.md
python3 ../analyze.py ../bench.sandbox.out || true
echo "done: bench.sandbox.out, probe.out, hazard.out, escape.out, fmt.out, vet.out"
