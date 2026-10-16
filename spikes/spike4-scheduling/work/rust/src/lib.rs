// hyblock — Spike 4 Rust side. stdlib-only, C ABI.
//
// Pieces:
//   * hy_block_ms        — the blocking payload (nanosleep) for M1/M2.
//   * bounded pool       — M3: std::thread workers (Tokio spawn_blocking shape),
//                          ticket slots with generation tags; no Go runtime
//                          internals anywhere near it.
//   * hy_spawn_detached  — M4 negative control: unbounded thread-per-call.
//   * hy_add             — non-blocking reference for dispatch-cost benches.
//
// Ticket encoding: (generation << 32) | slot_index. Generation makes a stale
// poll (after slot reuse) read as INVALID instead of a wrong result — the same
// discipline as the Spike 3 handle tables.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::sync::{Condvar, Mutex};
use std::thread;
use std::time::{Duration, Instant};

// ------------------------------------------------------------ stats

static STAT_BLOCK_CALLS: AtomicU64 = AtomicU64::new(0);
static STAT_BLOCKED_NS: AtomicU64 = AtomicU64::new(0);
static STAT_DETACHED: AtomicU64 = AtomicU64::new(0);
static STAT_DETACHED_FAILS: AtomicU64 = AtomicU64::new(0);

#[no_mangle]
pub extern "C" fn hy_block_ms(ms: u64) -> u64 {
    let t0 = Instant::now();
    thread::sleep(Duration::from_millis(ms));
    STAT_BLOCK_CALLS.fetch_add(1, Ordering::Relaxed);
    STAT_BLOCKED_NS.fetch_add(t0.elapsed().as_nanos() as u64, Ordering::Relaxed);
    ms
}

#[no_mangle]
pub extern "C" fn hy_stats_block_calls() -> u64 { STAT_BLOCK_CALLS.load(Ordering::Relaxed) }

#[no_mangle]
pub extern "C" fn hy_stats_blocked_ns() -> u64 { STAT_BLOCKED_NS.load(Ordering::Relaxed) }

#[no_mangle]
pub extern "C" fn hy_stats_detached() -> u64 { STAT_DETACHED.load(Ordering::Relaxed) }

#[no_mangle]
pub extern "C" fn hy_stats_detached_fails() -> u64 { STAT_DETACHED_FAILS.load(Ordering::Relaxed) }

#[no_mangle]
pub extern "C" fn hy_add(a: u64, b: u64) -> u64 { a.wrapping_add(b) }

// ------------------------------------------------------------ bounded pool (M3)

const POOL_SLOTS: usize = 1 << 18; // 262,144 outstanding tickets

struct Slot {
    state: AtomicU32,   // 0 free, 1 submitted/running, 2 done
    gen: AtomicU32,
    payload: AtomicU64, // packed (fn_id << 48) | arg while running; result when done
}

const fn zero_slot() -> Slot {
    Slot { state: AtomicU32::new(0), gen: AtomicU32::new(0), payload: AtomicU64::new(0) }
}

struct Pool {
    queue: Mutex<VecDeque<u64>>, // submitted tickets
    cv: Condvar,
    freelist: Mutex<Vec<u32>>,
    threads: AtomicU64,
    idle: AtomicU64,
    spawned_jobs: AtomicU64,
    done_jobs: AtomicU64,
    slots: [Slot; POOL_SLOTS],
}

const fn zero_pool() -> Pool {
    Pool {
        queue: Mutex::new(VecDeque::new()),
        cv: Condvar::new(),
        freelist: Mutex::new(Vec::new()),
        threads: AtomicU64::new(0),
        idle: AtomicU64::new(0),
        spawned_jobs: AtomicU64::new(0),
        done_jobs: AtomicU64::new(0),
        slots: [const { zero_slot() }; POOL_SLOTS],
    }
}

static POOL: Pool = zero_pool();
static POOL_INITED: AtomicBool = AtomicBool::new(false);

fn run_job(fn_id: u64, arg: u64) -> u64 {
    match fn_id {
        0 => { thread::sleep(Duration::from_millis(arg)); arg } // blocking job
        1 => arg.wrapping_add(1),                               // no-op job (dispatch floor)
        _ => 0,
    }
}

fn pool_worker() {
    loop {
        let ticket = {
            let mut q = POOL.queue.lock().unwrap();
            loop {
                if let Some(t) = q.pop_front() { break t; }
                POOL.idle.fetch_add(1, Ordering::Relaxed);
                q = POOL.cv.wait(q).unwrap();
                POOL.idle.fetch_sub(1, Ordering::Relaxed);
            }
        };
        let idx = (ticket & 0xFFFF_FFFF) as usize;
        let slot = &POOL.slots[idx];
        let packed = slot.payload.load(Ordering::Acquire);
        let fn_id = packed >> 48;
        let arg = packed & 0x0000_FFFF_FFFF_FFFF;
        let out = run_job(fn_id, arg);
        slot.payload.store(out, Ordering::Release);
        slot.state.store(2, Ordering::Release);
        POOL.done_jobs.fetch_add(1, Ordering::Relaxed);
    }
}

#[no_mangle]
pub extern "C" fn hy_pool_init(n: u64) -> u64 {
    if POOL_INITED.swap(true, Ordering::SeqCst) {
        return POOL.threads.load(Ordering::Relaxed);
    }
    {
        let mut fl = POOL.freelist.lock().unwrap();
        for i in (0..POOL_SLOTS as u32).rev() {
            fl.push(i); // pop() yields 0, 1, 2, ... in order
        }
    }
    for _ in 0..n {
        let h = thread::Builder::new()
            .stack_size(256 * 1024)
            .name("hyblock-pool".into())
            .spawn(pool_worker)
            .expect("pool thread spawn");
        drop(h); // dropping the JoinHandle detaches: workers live for the process
        POOL.threads.fetch_add(1, Ordering::Relaxed);
    }
    POOL.threads.load(Ordering::Relaxed)
}

#[no_mangle]
pub extern "C" fn hy_pool_submit(fn_id: u64, arg: u64) -> u64 {
    // fn_id must fit 16 bits in this spike's packing (we only use 0/1);
    // a wider fn space would use a side table.
    assert!(fn_id < 0x1_0000, "fn_id must fit 16 bits in this spike");
    let mut fl = POOL.freelist.lock().unwrap();
    let idx = match fl.pop() {
        Some(i) => i,
        None => return u64::MAX, // full: caller records a drop (S4 requires 0)
    };
    drop(fl);
    let slot = &POOL.slots[idx as usize];
    let gen = slot.gen.fetch_add(1, Ordering::Relaxed).wrapping_add(1);
    let packed = (fn_id << 48) | (arg & 0x0000_FFFF_FFFF_FFFF);
    slot.payload.store(packed, Ordering::Release);
    slot.state.store(1, Ordering::Release);
    let ticket = ((gen as u64) << 32) | idx as u64;
    let mut q = POOL.queue.lock().unwrap();
    q.push_back(ticket);
    drop(q);
    POOL.cv.notify_one();
    POOL.spawned_jobs.fetch_add(1, Ordering::Relaxed);
    ticket
}

#[no_mangle]
pub extern "C" fn hy_pool_poll(ticket: u64) -> u64 {
    if ticket == u64::MAX { return u64::MAX; }
    let idx = (ticket & 0xFFFF_FFFF) as usize;
    let gen = (ticket >> 32) as u32;
    let slot = &POOL.slots[idx];
    if slot.gen.load(Ordering::Acquire) != gen { return u64::MAX; } // stale
    match slot.state.load(Ordering::Acquire) {
        2 => {
            // done: free the slot (only the ticket holder polls it)
            let mut fl = POOL.freelist.lock().unwrap();
            fl.push(idx as u32);
            1
        }
        1 => 0, // pending
        _ => u64::MAX,
    }
}

#[no_mangle]
pub extern "C" fn hy_pool_qdepth() -> u64 {
    POOL.queue.lock().map(|q| q.len() as u64).unwrap_or(u64::MAX)
}

#[no_mangle]
pub extern "C" fn hy_pool_threads() -> u64 { POOL.threads.load(Ordering::Relaxed) }

#[no_mangle]
pub extern "C" fn hy_pool_idle() -> u64 { POOL.idle.load(Ordering::Relaxed) }

#[no_mangle]
pub extern "C" fn hy_pool_done() -> u64 { POOL.done_jobs.load(Ordering::Relaxed) }

#[no_mangle]
pub extern "C" fn hy_pool_spawned() -> u64 { POOL.spawned_jobs.load(Ordering::Relaxed) }

// ------------------------------------------------------------ M4: detached

#[no_mangle]
pub extern "C" fn hy_spawn_detached(ms: u64) -> u64 {
    let h = thread::Builder::new()
        .name("hyblock-detached".into())
        .spawn(move || { thread::sleep(Duration::from_millis(ms)); });
    // default 2 MiB stacks (honest default-thread cost). Spawn FAILURES are
    // counted separately — never reported as successes (integrity rule).
    match h {
        Ok(handle) => { drop(handle); STAT_DETACHED.fetch_add(1, Ordering::Relaxed) + 1 }
        Err(_) => { STAT_DETACHED_FAILS.fetch_add(1, Ordering::Relaxed); u64::MAX }
    }
}
