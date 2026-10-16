// Package golink is the cgo address broker for the hyarena Rust staticlib
// (Spike 3). Same pattern as Spike 1: links the lib, hands out C-ABI function
// ADDRESSES once at init; NO per-call cgo crossing ever happens.
package golink

/*
#cgo LDFLAGS: -L${SRCDIR}/../../rust/target/release -l:libhyarena.a -lpthread -ldl -lm
#include <stdint.h>

extern uint64_t hy_obj_create(uint64_t init);
extern uint64_t hy_obj_get(uint64_t id);
extern uint64_t hy_obj_retain(uint64_t id);
extern uint64_t hy_obj_release(uint64_t id);
extern uint64_t hy_view_hold(uintptr_t ptr);
extern uint64_t hy_view_hold_stack(uintptr_t ptr);
extern uint64_t hy_view_read(uint64_t id);
extern uint64_t hy_view_release(uint64_t id);
extern uint64_t hy_arena_scope_enter(void);
extern uint64_t hy_arena_slot(uint64_t scope, uint64_t val);
extern uint64_t hy_arena_slot_read(uint64_t slot);
extern uint64_t hy_arena_scope_exit(uint64_t scope);
extern uint64_t hy_stats_live_objects(void);
extern uint64_t hy_stats_live_views(void);
extern uint64_t hy_stats_arena_slots(void);
extern int64_t  hy_stats_alloc_bytes(void);
extern uint64_t hy_add(uint64_t a, uint64_t b);
extern uint64_t hy_read_u64(uintptr_t ptr);
extern uint64_t hy_sum_slice(uintptr_t ptr, uint64_t len);
extern uint64_t hy_bench_obj_get(uint64_t iters, uint64_t id);
extern uint64_t hy_deep_rec(uint64_t depth);

static void* a_obj_create(void) { return (void*)&hy_obj_create; }
static void* a_obj_get(void)    { return (void*)&hy_obj_get; }
static void* a_obj_retain(void) { return (void*)&hy_obj_retain; }
static void* a_obj_release(void){ return (void*)&hy_obj_release; }
static void* a_view_hold(void)  { return (void*)&hy_view_hold; }
static void* a_view_hold_stack(void) { return (void*)&hy_view_hold_stack; }
static void* a_view_read(void)  { return (void*)&hy_view_read; }
static void* a_view_release(void){ return (void*)&hy_view_release; }
static void* a_arena_enter(void){ return (void*)&hy_arena_scope_enter; }
static void* a_arena_slot(void) { return (void*)&hy_arena_slot; }
static void* a_arena_slot_read(void) { return (void*)&hy_arena_slot_read; }
static void* a_arena_exit(void) { return (void*)&hy_arena_scope_exit; }
static void* a_stats_obj(void)  { return (void*)&hy_stats_live_objects; }
static void* a_stats_view(void) { return (void*)&hy_stats_live_views; }
static void* a_stats_arena(void){ return (void*)&hy_stats_arena_slots; }
static void* a_stats_alloc(void){ return (void*)&hy_stats_alloc_bytes; }
static void* a_add(void)        { return (void*)&hy_add; }
static void* a_read_u64(void)   { return (void*)&hy_read_u64; }
static void* a_sum_slice(void)  { return (void*)&hy_sum_slice; }
static void* a_bench_obj_get(void) { return (void*)&hy_bench_obj_get; }
static void* a_deep_rec(void)    { return (void*)&hy_deep_rec; }
*/
import "C"

import "unsafe"

// Function addresses (C ABI), resolved once at package init.
var (
	FnObjCreate     = unsafe.Pointer(C.a_obj_create())
	FnObjGet        = unsafe.Pointer(C.a_obj_get())
	FnObjRetain     = unsafe.Pointer(C.a_obj_retain())
	FnObjRelease    = unsafe.Pointer(C.a_obj_release())
	FnViewHold      = unsafe.Pointer(C.a_view_hold())
	FnViewHoldStack = unsafe.Pointer(C.a_view_hold_stack())
	FnViewRead      = unsafe.Pointer(C.a_view_read())
	FnViewRelease   = unsafe.Pointer(C.a_view_release())
	FnArenaEnter    = unsafe.Pointer(C.a_arena_enter())
	FnArenaSlot     = unsafe.Pointer(C.a_arena_slot())
	FnArenaSlotRead = unsafe.Pointer(C.a_arena_slot_read())
	FnArenaExit     = unsafe.Pointer(C.a_arena_exit())
	FnStatsObj      = unsafe.Pointer(C.a_stats_obj())
	FnStatsView     = unsafe.Pointer(C.a_stats_view())
	FnStatsArena    = unsafe.Pointer(C.a_stats_arena())
	FnStatsAlloc    = unsafe.Pointer(C.a_stats_alloc())
	FnAdd           = unsafe.Pointer(C.a_add())
	FnReadU64       = unsafe.Pointer(C.a_read_u64())
	FnSumSlice      = unsafe.Pointer(C.a_sum_slice())
	FnBenchObjGet   = unsafe.Pointer(C.a_bench_obj_get())
	FnDeepRec       = unsafe.Pointer(C.a_deep_rec())
)
