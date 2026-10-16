// Package golink: cgo address broker for the hyerr Rust staticlib (Spike 5).
// Same pattern as Spikes 1/3: links the lib, hands out C-ABI function
// addresses once at init; NO per-call cgo crossing.
package golink

/*
#cgo LDFLAGS: -L${SRCDIR}/../../rust/target/release -l:libhyerr.a -lpthread -ldl -lm
#include <stdint.h>

typedef struct { uint32_t code; uint64_t payload; } HyResult; // 16 bytes, RAX:RDX return

extern HyResult hy_ok_add(uint64_t a, uint64_t b);
extern HyResult hy_may_fail(uint64_t a, uint64_t flag);
extern HyResult hy_chain_fail(uint64_t which);
extern HyResult hy_panic(void);
extern uint64_t hy_bench_result(uint64_t iters, uint64_t err_every);

static void* a_ok_add(void)    { return (void*)&hy_ok_add; }
static void* a_may_fail(void)  { return (void*)&hy_may_fail; }
static void* a_chain_fail(void){ return (void*)&hy_chain_fail; }
static void* a_panic(void)     { return (void*)&hy_panic; }
static void* a_bench_result(void) { return (void*)&hy_bench_result; }
*/
import "C"

import "unsafe"

var (
	FnOkAdd       = unsafe.Pointer(C.a_ok_add())
	FnMayFail     = unsafe.Pointer(C.a_may_fail())
	FnChainFail   = unsafe.Pointer(C.a_chain_fail())
	FnPanic       = unsafe.Pointer(C.a_panic())
	FnBenchResult = unsafe.Pointer(C.a_bench_result())
)
