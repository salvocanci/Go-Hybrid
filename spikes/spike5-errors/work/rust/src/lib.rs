//! Spike 5: error representation probes. Throwaway per SPEC §5.
//!
//! Contract under test: a C-ABI two-word return `{ code: u32, payload: u64 }`
//! in RAX:RDX (SysV INTEGER pair), code 0 = ok. Panics abort (panic=abort in
//! Cargo.toml) — they must NEVER unwind into Go frames.

use std::hint::black_box;

pub const E_OK: u32 = 0;
pub const E_NOT_FOUND: u32 = 1;
pub const E_INVALID_ARG: u32 = 2;
pub const E_OVERFLOW: u32 = 3;
pub const E_IO: u32 = 4; // carries a payload (errno-ish)

/// Ok-path probe: a+b, never fails. (code, payload) = (0, a+b).
#[no_mangle]
pub extern "C" fn hy_ok_add(a: u64, b: u64) -> HyResult {
    HyResult { code: E_OK, payload: a.wrapping_add(b) }
}

/// Error-path probe: flag==0 -> ok with payload a; else the error code is
/// (a % 4)+1 with payload a. Exercises both arms through one crossing.
#[no_mangle]
pub extern "C" fn hy_may_fail(a: u64, flag: u64) -> HyResult {
    if flag == 0 {
        HyResult { code: E_OK, payload: a }
    } else {
        let code = (a % 4) as u32 + 1;
        HyResult { code, payload: a }
    }
}

/// Error-with-source-chain probe: returns (code, payload) where code has a
/// defined parent chain (E_IO -> E_NOT_FOUND) for identity tests.
#[no_mangle]
pub extern "C" fn hy_chain_fail(which: u64) -> HyResult {
    match which % 2 {
        0 => HyResult { code: E_IO, payload: 77 },
        _ => HyResult { code: E_OVERFLOW, payload: 88 },
    }
}

/// Panic-contract probe: panics; with panic=abort this aborts the process at
/// the Rust edge (SIGABRT), never unwinding into Go frames.
#[no_mangle]
pub extern "C" fn hy_panic() -> HyResult {
    panic!("hyerr: deliberate panic at the boundary")
}

/// Rust-side reference: a Result-returning loop without any crossing.
/// black_box on EVERY result prevents LLVM from closed-forming the sum.
#[no_mangle]
pub extern "C" fn hy_bench_result(iters: u64, err_every: u64) -> u64 {
    fn work(i: u64, err_every: u64) -> Result<u64, u32> {
        if err_every != 0 && i % err_every == 0 {
            Err(E_IO)
        } else {
            Ok(i.wrapping_mul(3))
        }
    }
    let mut acc = 0u64;
    for i in 0..iters {
        let r = work(i, err_every);
        acc = acc.wrapping_add(match r {
            Ok(v) => v,
            Err(e) => e as u64,
        });
        acc = black_box(acc);
    }
    acc
}

/// The C-ABI return struct: { u32, u32-pad, u64 } — two 8-byte INTEGER
/// class words, returned in RAX:RDX per SysV.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct HyResult {
    pub code: u32,
    pub payload: u64,
}

// keep the struct exactly 16 bytes for the RAX:RDX return
const _: () = {
    assert!(std::mem::size_of::<HyResult>() == 16);
};
