// ============================================================================
// 10-rust-crate-import — Spike 6: examples/10-rust-crate-import under Tier-0
// rules. Semantics and expected output unchanged (expected.txt):
//     hybrid: 7b1a3b…
//     go: 62d34d…
//     rust: d216dd…
//     1M hashes in <200ms, checksum=<deterministic per pinned crate>
// (digest prefixes and checksum are pinned by the pinned crate at MVP-0.)
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `words` ([]string), `w` (copied per iteration), the
//   32-byte `digest` buffers (Hybrid-owned, function-scoped), `t0`/`dt`.
// Layer 2 (Rust-side owned): none manipulated directly — sha3 state lives
//   inside the callee.
// Layer 3 (boundary handles / views, abi-types.md):
//   - `w` crosses as a string: "hybrid"=6 B, "go"=2 B, "rust"=4 B — all
//     ≤ 16 B → BY-VALUE COPY (spike-3 copy-small path). Contrast 09, where
//     longer strings take the pinned-view path.
//   - `digest` is written by the callee through a call-scoped OUT-view
//     (pinned ptr+len for ONE call — the crate's `out: *mut u8 /*32*/`
//     parameter); the buffer itself is a plain GC value owned by the
//     enclosing scope, so `digest[..3]` afterward is a local read (A4).
//   - `checksum` (u64) and `seed` (u64) cross by value.
//   - Errors: HyResult two-word return → `?` (Spike 5).
//   The hot loop runs INSIDE the Rust callee — ONE boundary crossing total
//   for 1M iterations (the §6 budget point).
//
// ---- Sendability check sites (task spawn / channel send) ----
//   NONE.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

import "rust/sha3"          // pins sha3 0.10; API extracted via rustdoc JSON

fn main() {
    let words = ["hybrid", "go", "rust"] // GC slice of short strings
    for w in words {
        digest := sha3.digest256(w)?     // Go-side 32 B buffer; callee writes
                                         // it via a call-scoped out-view
        fmt.println("{w}: {hex.encode(digest[..3])}…") // local read view
    }

    // hot loop in Rust: one boundary crossing, a million iterations inside
    t0 := time.now()
    checksum := sha3.stream_checksum(1_000_000, seed=7)?
    dt := time.since(t0)
    fmt.println("1M hashes in {dt.milliseconds}ms, checksum={checksum}")
}

// ---- the pinned Rust crate surface (rust/sha3), for reference ----
// #[no_mangle] pub extern "C" fn hybrid_sha3_digest256(data: *const u8, len: usize,
//     out: *mut u8 /*32*/) -> i32 /*0=ok, 1=err*/
// #[no_mangle] pub extern "C" fn hybrid_sha3_stream_checksum(iters: u64, seed: u64) -> u64;
