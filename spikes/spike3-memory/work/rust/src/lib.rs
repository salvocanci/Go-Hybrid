//! Spike 3: Rust side — owning-side handle table, scoped arena, Go-pointer
//! view probes, counting allocator. Throwaway per SPEC §5.
//!
//! Invariants this crate demonstrates:
//! - Rust-owned objects are reached ONLY by integer id (never a raw pointer
//!   crossing back); refcount decides "freed when both sides release".
//! - Raw Go pointers may be stored in the view table ONLY as explicit hazard
//!   probes (P7 unpinned heap, P8 stack); the safe mode of the real bridge
//!   never does this — views exist to demonstrate what breaks.
//! - Nothing here ever calls back into Go; no unwinding out of extern fns
//!   (panic=abort in Cargo.toml).

use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{LazyLock, Mutex};

pub const INVALID: u64 = u64::MAX; // released/unknown id sentinel (P6)
const NULL_PTR: usize = 0;

// ---------------------------------------------------------------- allocator

static LIVE_BYTES: AtomicI64 = AtomicI64::new(0);

struct CountingAlloc;

unsafe impl GlobalAlloc for CountingAlloc {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let p = System.alloc(layout);
        if !p.is_null() {
            LIVE_BYTES.fetch_add(layout.size() as i64, Ordering::Relaxed);
        }
        p
    }
    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        System.dealloc(ptr, layout);
        LIVE_BYTES.fetch_sub(layout.size() as i64, Ordering::Relaxed);
    }
    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        let p = System.realloc(ptr, layout, new_size);
        if !p.is_null() {
            LIVE_BYTES.fetch_add(new_size as i64 - layout.size() as i64, Ordering::Relaxed);
        }
        p
    }
}

#[global_allocator]
static GLOBAL: CountingAlloc = CountingAlloc;

// ---------------------------------------------------------------- state

struct Obj {
    payload: u64,
    rc: u32,
}

/// A table slot. `gen` is bumped every time the slot is freed, and ids embed
/// the generation — a stale release (e.g. a late Go cleanup) on a REUSED slot
/// reads as INVALID instead of corrupting the new object (SPEC §12 finalizers).
struct ObjSlot {
    gen: u32,
    inner: Option<Obj>,
}

struct View {
    ptr: *mut u64,
    kind: u8, // 1 = unpinned heap probe, 2 = stack probe
}

// View holds a raw pointer BY DESIGN (hazard probes); it is only ever touched
// under the STATE mutex, so manual Send/Sync is sound here.
unsafe impl Send for View {}
unsafe impl Sync for View {}

struct ArenaScope {
    bump_off: usize, // bump pointer at scope entry
    slots: Vec<u32>, // slot indices allocated in this scope
}

struct State {
    objs: Vec<ObjSlot>,
    obj_free: Vec<u32>,
    views: Vec<Option<View>>,
    view_free: Vec<u32>,
    // scoped arena: one contiguous region, LIFO scopes
    arena: Vec<u64>, // payload slots (u64 each; keeps alignment trivial)
    arena_bump: usize,
    scopes: Vec<ArenaScope>,
    scope_live: bool,
}

impl State {
    fn new() -> Self {
        State {
            objs: Vec::new(),
            obj_free: Vec::new(),
            views: Vec::new(),
            view_free: Vec::new(),
            arena: Vec::with_capacity(1 << 16),
            arena_bump: 0,
            scopes: Vec::new(),
            scope_live: false,
        }
    }
}

static STATE: LazyLock<Mutex<State>> = LazyLock::new(|| Mutex::new(State::new()));

fn with_state<T>(f: impl FnOnce(&mut State) -> T) -> T {
    let mut st = STATE.lock().unwrap();
    f(&mut st)
}

// id encoding: (gen << 32) | (index+1). id 0 and low==0 are invalid.
fn split_obj_id(id: u64) -> Option<(u32, usize)> {
    let low = (id & 0xFFFF_FFFF) as u32;
    if low == 0 {
        return None;
    }
    Some((((id >> 32) as u32), (low - 1) as usize))
}

// ---------------------------------------------------------------- extern API

/// Create a Rust-owned object (rc=1). Returns its generation-tagged id.
#[no_mangle]
pub extern "C" fn hy_obj_create(init: u64) -> u64 {
    with_state(|st| {
        if let Some(i) = st.obj_free.pop() {
            let gen = st.objs[i as usize].gen;
            st.objs[i as usize].inner = Some(Obj { payload: init, rc: 1 });
            ((gen as u64) << 32) | ((i as u64) + 1)
        } else {
            st.objs.push(ObjSlot { gen: 0, inner: Some(Obj { payload: init, rc: 1 }) });
            let i = (st.objs.len() - 1) as u64;
            i + 1 // gen 0
        }
    })
}

/// Read an object payload. INVALID if unknown/released (P6 sentinel).
#[no_mangle]
pub extern "C" fn hy_obj_get(id: u64) -> u64 {
    with_state(|st| match split_obj_id(id) {
        Some((gen, i)) => match st.objs.get(i) {
            Some(s) if s.inner.is_some() && s.gen == gen => unsafe {
                s.inner.as_ref().unwrap_unchecked().payload
            },
            _ => INVALID,
        },
        None => INVALID,
    })
}

/// rc+1. Returns new rc, INVALID if unknown.
#[no_mangle]
pub extern "C" fn hy_obj_retain(id: u64) -> u64 {
    with_state(|st| match split_obj_id(id) {
        Some((gen, i)) => match st.objs.get_mut(i) {
            Some(s) if s.inner.is_some() && s.gen == gen => {
                let o = s.inner.as_mut().unwrap();
                o.rc += 1;
                o.rc as u64
            }
            _ => INVALID,
        },
        None => INVALID,
    })
}

/// rc-1; at 0 the slot dies (gen bumps, returns to freelist). Returns rc
/// AFTER (0 = freed), INVALID if unknown — including stale-generation ids.
#[no_mangle]
pub extern "C" fn hy_obj_release(id: u64) -> u64 {
    with_state(|st| match split_obj_id(id) {
        Some((gen, i)) => match st.objs.get_mut(i) {
            Some(s) if s.inner.is_some() && s.gen == gen => {
                let o = s.inner.as_mut().unwrap();
                o.rc -= 1;
                let rc = o.rc;
                if rc == 0 {
                    s.gen = s.gen.wrapping_add(1);
                    s.inner = None;
                    st.obj_free.push(i as u32);
                }
                rc as u64
            }
            _ => INVALID,
        },
        None => INVALID,
    })
}

/// P7/P8 hazard probes: store a raw Go pointer (heap-unpinned or stack).
#[no_mangle]
pub extern "C" fn hy_view_hold(ptr: usize) -> u64 {
    if ptr == NULL_PTR {
        return INVALID;
    }
    with_state(|st| {
        let v = View { ptr: ptr as *mut u64, kind: 1 };
        if let Some(i) = st.view_free.pop() {
            st.views[i as usize] = Some(v);
            (i as u64) + 1
        } else {
            st.views.push(Some(v));
            st.views.len() as u64
        }
    })
}

#[no_mangle]
pub extern "C" fn hy_view_hold_stack(ptr: usize) -> u64 {
    if ptr == NULL_PTR {
        return INVALID;
    }
    with_state(|st| {
        let v = View { ptr: ptr as *mut u64, kind: 2 };
        if let Some(i) = st.view_free.pop() {
            st.views[i as usize] = Some(v);
            (i as u64) + 1
        } else {
            st.views.push(Some(v));
            st.views.len() as u64
        }
    })
}

/// Dereference a held view. This is the deliberate UB window of P7/P8.
#[no_mangle]
pub extern "C" fn hy_view_read(id: u64) -> u64 {
    with_state(|st| match st.views.get((id - 1) as usize) {
        Some(Some(v)) if id != 0 => unsafe { *v.ptr },
        _ => INVALID,
    })
}

#[no_mangle]
pub extern "C" fn hy_view_release(id: u64) -> u64 {
    with_state(|st| match st.views.get_mut((id - 1) as usize) {
        Some(Some(_)) if id != 0 => {
            let i = (id - 1) as u32;
            st.views[i as usize] = None;
            st.view_free.push(i);
            0
        }
        _ => INVALID,
    })
}

// ------------------------------------------------------- scoped arena (T6)

/// Enter a scope; returns scope id (index+1). Scopes are strictly LIFO.
#[no_mangle]
pub extern "C" fn hy_arena_scope_enter() -> u64 {
    with_state(|st| {
        let entry = ArenaScope { bump_off: st.arena_bump, slots: Vec::new() };
        st.scopes.push(entry);
        st.scope_live = true;
        st.scopes.len() as u64
    })
}

/// Allocate a u64 slot in the current scope; returns slot id (index+1).
#[no_mangle]
pub extern "C" fn hy_arena_slot(scope: u64, val: u64) -> u64 {
    with_state(|st| {
        if scope == 0 || (scope as usize) > st.scopes.len() {
            return INVALID;
        }
        let idx = st.arena_bump;
        if idx >= st.arena.len() {
            st.arena.push(val);
        } else {
            st.arena[idx] = val;
        }
        st.arena_bump += 1;
        let slot_id = (idx as u64) + 1;
        st.scopes[(scope - 1) as usize].slots.push(idx as u32);
        slot_id
    })
}

/// Read an arena slot by id. Slots past the live bump pointer are dead
/// (their scope exited) -> INVALID.
#[no_mangle]
pub extern "C" fn hy_arena_slot_read(slot: u64) -> u64 {
    with_state(|st| {
        if slot == 0 {
            return INVALID;
        }
        let idx = (slot - 1) as usize;
        if idx < st.arena_bump {
            st.arena[idx]
        } else {
            INVALID
        }
    })
}

/// Exit the innermost scope: all its slots die at once (scoped lifetime).
/// Returns 0 on success, INVALID on scope misuse (not innermost / none live).
#[no_mangle]
pub extern "C" fn hy_arena_scope_exit(scope: u64) -> u64 {
    with_state(|st| {
        if !st.scope_live || st.scopes.is_empty() {
            return INVALID;
        }
        if (scope as usize) != st.scopes.len() {
            return INVALID; // LIFO violation
        }
        let entry = st.scopes.pop().unwrap();
        st.arena_bump = entry.bump_off; // whole scope's bump reclaims
        st.scope_live = !st.scopes.is_empty();
        0
    })
}

// ---------------------------------------------------------------- stats

#[no_mangle]
pub extern "C" fn hy_stats_live_objects() -> u64 {
    with_state(|st| st.objs.iter().filter(|s| s.inner.is_some()).count() as u64)
}

#[no_mangle]
pub extern "C" fn hy_stats_live_views() -> u64 {
    with_state(|st| st.views.iter().filter(|v| v.is_some()).count() as u64)
}

#[no_mangle]
pub extern "C" fn hy_stats_arena_slots() -> u64 {
    with_state(|st| st.arena_bump as u64)
}

#[no_mangle]
pub extern "C" fn hy_stats_alloc_bytes() -> i64 {
    LIVE_BYTES.load(Ordering::Relaxed)
}

// ------------------------------------------------------- bench helpers

/// M4-baseline replica: plain add (P3 comparison anchor).
#[no_mangle]
pub extern "C" fn hy_add(a: u64, b: u64) -> u64 {
    a.wrapping_add(b)
}

/// Pinned-borrow read: one u64 through a pointer the CALLER pinned, valid
/// for the duration of this call only.
#[no_mangle]
pub extern "C" fn hy_read_u64(ptr: usize) -> u64 {
    if ptr == NULL_PTR {
        return INVALID;
    }
    unsafe { *(ptr as *const u64) }
}

/// Pinned-borrow buffer walk: sum `len` u64s (P3 measured op).
#[no_mangle]
pub extern "C" fn hy_sum_slice(ptr: usize, len: u64) -> u64 {
    if ptr == NULL_PTR {
        return INVALID;
    }
    let s = unsafe { std::slice::from_raw_parts(ptr as *const u64, len as usize) };
    s.iter().fold(0u64, |a, &b| a.wrapping_add(b))
}

/// Deep-path probe: recursion with a REAL ~64-byte stack frame (address of a
/// local array escapes via black_box, and the recursive result is used after
/// the call so LLVM cannot tail-call-optimize it away). 10k depth needs
/// ~0.9 MiB — only survivable on a pooled 1 MiB mmap stack, never on a
/// goroutine stack.
#[no_mangle]
pub extern "C" fn hy_deep_rec(depth: u64) -> u64 {
    fn rec(d: u64, acc: u64) -> u64 {
        let pad = [d; 8];
        std::hint::black_box(&pad as *const _); // forces pad onto the stack
        if d == 0 {
            return acc;
        }
        let sub = rec(d - 1, acc); // used below: NOT a tail call
        sub.wrapping_add(pad[(d % 8) as usize])
    }
    rec(depth, 0)
}

/// Rust-side reference: id resolve + payload read in a tight loop (P4
/// reference without the crossing), black_box'd.
#[no_mangle]
pub extern "C" fn hy_bench_obj_get(iters: u64, id: u64) -> u64 {
    let mut acc = 0u64;
    for _ in 0..iters {
        acc = acc.wrapping_add(hy_obj_get(id));
    }
    std::hint::black_box(acc)
}
