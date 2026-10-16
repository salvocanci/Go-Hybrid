// Package golink is the cgo bridge that (a) links the Rust staticlib and
// (b) hands out C-ABI function ADDRESSES. It performs NO per-call cgo
// crossing: addresses are fetched once at package init.
//
// This is the Go-1.26-compatible replacement for the 2017 rustgo
// //go:cgo_import_static + //go:linkname trick, which modern Go rejects
// ("only allowed in cgo-generated code").
package golink

/*
#cgo LDFLAGS: -L${SRCDIR}/../../rustrt/target/release -l:librustrt.a -lpthread -ldl -lm
#include <stdint.h>

extern uint64_t hybrid_add(uint64_t a, uint64_t b);
extern void     hybrid_noop(void);
extern uint64_t hybrid_tree_sum(uint64_t depth);

static void* addr_add(void)  { return (void*)&hybrid_add; }
static void* addr_noop(void) { return (void*)&hybrid_noop; }
static void* addr_tree(void) { return (void*)&hybrid_tree_sum; }
*/
import "C"

import "unsafe"

// Function addresses (C ABI), resolved once. The asm trampolines in package
// bench CALL these pointers without any cgo runtime involvement.
var (
	FnAdd  = unsafe.Pointer(C.addr_add())
	FnNoop = unsafe.Pointer(C.addr_noop())
	FnTree = unsafe.Pointer(C.addr_tree())
)
