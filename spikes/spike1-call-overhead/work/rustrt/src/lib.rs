//! Spike 1 Rust side: C-ABI functions linked into a Go binary.
//! panic=abort per the boundary rule (SPEC §5 Spike 5 / §12).

#[no_mangle]
pub extern "C" fn hybrid_noop() {}

#[no_mangle]
pub extern "C" fn hybrid_add(a: u64, b: u64) -> u64 {
    a.wrapping_add(b)
}

/// A slightly deeper Rust frame to sanity-check the switched stack.
#[no_mangle]
pub extern "C" fn hybrid_tree_sum(depth: u64) -> u64 {
    fn rec(d: u64) -> u64 {
        if d == 0 {
            0
        } else {
            d.wrapping_add(rec(d.wrapping_sub(1)))
        }
    }
    // defeat must-tail heuristics; ~depth * 32B of real stack
    std::hint::black_box(rec(std::hint::black_box(depth)))
}
