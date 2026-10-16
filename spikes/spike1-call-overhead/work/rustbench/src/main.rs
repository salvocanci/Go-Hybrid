//! Rust-side reference numbers for Spike 1 (manual timing; criterion skipped —
//! 2-core/4GB box, deviation logged in PLAN.md).

#[inline(never)]
fn rust_add(a: u64, b: u64) -> u64 {
    a.wrapping_add(b)
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn c_abi_add(a: u64, b: u64) -> u64 {
    a.wrapping_add(b)
}

fn bench<F: FnMut(u64, u64) -> u64>(name: &str, mut f: F) {
    const N: u64 = 100_000_000;
    // warm-up
    for i in 0..1_000_000u64 {
        std::hint::black_box(f(i, i));
    }
    let t0 = std::time::Instant::now();
    for i in 0..N {
        std::hint::black_box(f(i, i));
    }
    let d = t0.elapsed().as_nanos() as f64 / N as f64;
    println!("{:<24} {:>8.3} ns/op  (N={})", name, d, N);
}

fn main() {
    println!("rustbench: rust 1.99.0, release, black_box'd, 1e8 iters");
    bench("rust->rust direct", |a, b| rust_add(a, b));
    bench("rust->extern_C", |a, b| {
        let p = c_abi_add as extern "C" fn(u64, u64) -> u64;
        p(a, b)
    });
    // The indirect-call variant that mirrors what the Go trampoline does
    // (CALL AX with the function address loaded from memory).
    bench("rust->indirect_C", |a, b| {
        let p = unsafe { std::mem::transmute::<usize, extern "C" fn(u64, u64) -> u64>(c_abi_add as usize) };
        p(a, b)
    });
}
