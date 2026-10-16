// Package golink4 is the cgo address broker for the hyblock Rust staticlib
// (Spike 4). Same pattern as Spikes 1/3: links the lib once at init and hands
// out C-ABI function ADDRESSES; NO per-call cgo crossing ever happens.
package golink4

/*
#cgo LDFLAGS: -L${SRCDIR}/../../rust/target/release -l:libhyblock.a -lpthread -ldl -lm
#include <stdint.h>

extern uint64_t hy_block_ms(uint64_t ms);
extern uint64_t hy_add(uint64_t a, uint64_t b);
extern uint64_t hy_pool_init(uint64_t n);
extern uint64_t hy_pool_submit(uint64_t fn_id, uint64_t arg);
extern uint64_t hy_pool_poll(uint64_t ticket);
extern uint64_t hy_pool_qdepth(void);
extern uint64_t hy_pool_threads(void);
extern uint64_t hy_pool_idle(void);
extern uint64_t hy_pool_done(void);
extern uint64_t hy_pool_spawned(void);
extern uint64_t hy_spawn_detached(uint64_t ms);
extern uint64_t hy_stats_block_calls(void);
extern uint64_t hy_stats_blocked_ns(void);
extern uint64_t hy_stats_detached(void);
extern uint64_t hy_stats_detached_fails(void);

static void* a_block_ms(void)     { return (void*)&hy_block_ms; }
static void* a_add(void)          { return (void*)&hy_add; }
static void* a_pool_init(void)    { return (void*)&hy_pool_init; }
static void* a_pool_submit(void)  { return (void*)&hy_pool_submit; }
static void* a_pool_poll(void)    { return (void*)&hy_pool_poll; }
static void* a_pool_qdepth(void)  { return (void*)&hy_pool_qdepth; }
static void* a_pool_threads(void) { return (void*)&hy_pool_threads; }
static void* a_pool_idle(void)    { return (void*)&hy_pool_idle; }
static void* a_pool_done(void)    { return (void*)&hy_pool_done; }
static void* a_pool_spawned(void) { return (void*)&hy_pool_spawned; }
static void* a_spawn_detached(void) { return (void*)&hy_spawn_detached; }
static void* a_stats_block_calls(void) { return (void*)&hy_stats_block_calls; }
static void* a_stats_blocked_ns(void) { return (void*)&hy_stats_blocked_ns; }
static void* a_stats_detached(void)   { return (void*)&hy_stats_detached; }
static void* a_stats_detached_fails(void) { return (void*)&hy_stats_detached_fails; }
*/
import "C"

import "unsafe"

// Function addresses (C ABI), resolved once at package init.
var (
	FnBlockMs       = unsafe.Pointer(C.a_block_ms())
	FnAdd           = unsafe.Pointer(C.a_add())
	FnPoolInit      = unsafe.Pointer(C.a_pool_init())
	FnPoolSubmit    = unsafe.Pointer(C.a_pool_submit())
	FnPoolPoll      = unsafe.Pointer(C.a_pool_poll())
	FnPoolQdepth    = unsafe.Pointer(C.a_pool_qdepth())
	FnPoolThreads   = unsafe.Pointer(C.a_pool_threads())
	FnPoolIdle      = unsafe.Pointer(C.a_pool_idle())
	FnPoolDone      = unsafe.Pointer(C.a_pool_done())
	FnPoolSpawned   = unsafe.Pointer(C.a_pool_spawned())
	FnSpawnDetached = unsafe.Pointer(C.a_spawn_detached())
	FnStatsBlkCalls = unsafe.Pointer(C.a_stats_block_calls())
	FnStatsBlkNs    = unsafe.Pointer(C.a_stats_blocked_ns())
	FnStatsDetached = unsafe.Pointer(C.a_stats_detached())
	FnStatsDetFails = unsafe.Pointer(C.a_stats_detached_fails())
)
