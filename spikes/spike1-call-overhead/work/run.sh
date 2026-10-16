#!/usr/bin/env bash
# Spike 1 build + run (sandbox tier). Usage: bash spikes/spike1-call-overhead/work/run.sh
set -e
cd "$(dirname "$0")"

# 1. Rust staticlib (respects CARGO_TARGET_DIR if set; falls back to ./target)
(cd rustrt && cargo build --release -j2)
if [ -n "$CARGO_TARGET_DIR" ]; then
  LIBDIR="$CARGO_TARGET_DIR/release"
else
  LIBDIR="$(pwd)/rustrt/target/release"
fi
echo "librustrt.a: $LIBDIR/librustrt.a"

# 2. Expose the lib at the conventional path the Go module's LDFLAGS expects
#    (a symlink so both sandbox [redirected target dir] and remote tiers work).
mkdir -p rustrt/target
ln -sfn "$LIBDIR" rustrt/target/release
ls -la rustrt/target/release/librustrt.a

# 3. Rust-side reference (direct call + C-ABI call cost from the Rust side)
echo "=== rustbench (Rust->Rust / Rust->C-ABI reference) ==="
(cd rustbench && cargo run --release -q 2>/dev/null || cargo run --release) | tee rustbench.out

# 4. Go benchmarks: correctness probes first, then 10x bench runs
cd go
echo "=== correctness + stability probes ==="
go test ./bench/ -run 'TestAsm' -v -count=1 2>&1 | tee ../probe.out

echo "=== benchmarks (count=10, both packages) ==="
go test ./... -run '^$' -bench . -benchmem -count=10 2>&1 | tee ../bench.sandbox.out

echo "=== race-detector pass over the stack-switch path (record honestly) ==="
go test ./bench/ -race -run 'TestAsmStability|TestAsmCorrectness' -count=1 2>&1 | tee ../race.out | tail -5 || true

echo "done: bench.sandbox.out, probe.out, race.out"
