// Package sha3binding — the Go side of the `rust/sha3` bridge (example 10).
//
// Generated-shape file: this is what the bridge generator emits for a
// pinned crate (abi-types.md §5). The cgo broker below is the ONLY cgo in
// the binary — it links the staticlib and resolves C-ABI function
// ADDRESSES once at init; zero per-call cgo ever happens (spike-1's
// measured 2.8–4.4 ns crossing is the trampoline, not cgo).
package sha3binding

/*
#cgo LDFLAGS: -L${SRCDIR}/../lib -lhyrt
#cgo !windows LDFLAGS: -lpthread -ldl -lm
#cgo windows LDFLAGS: -lwinpthread -lntdll -lws2_32 -lbcrypt -luserenv -lole32 -loleaut32 -lsynchronization -ladvapi32
#include <stdint.h>

extern uint64_t hy_sha3_digest256(uint64_t data, uint64_t len, uint64_t out);
extern uint64_t hy_sha3_stream_checksum(uint64_t iters, uint64_t seed);
extern uint64_t hyrt_abi_word(void);

static void* a_digest256(void)       { return (void*)&hy_sha3_digest256; }
static void* a_stream_checksum(void) { return (void*)&hy_sha3_stream_checksum; }
static void* a_abi_word(void)        { return (void*)&hyrt_abi_word; }
*/
import "C"

import "unsafe"

// Function addresses (C ABI), resolved once at package init.
var (
	FnDigest256      = unsafe.Pointer(C.a_digest256())
	FnStreamChecksum = unsafe.Pointer(C.a_stream_checksum())
	FnAbiWord        = unsafe.Pointer(C.a_abi_word())
)

// abiWordExpected is hyrt_abi_word() for this binding generation. A mismatch
// at init means the Go binding and the Rust staticlib disagree about the
// ABI — abort loudly, never quietly mis-call (M6's handshake).
const abiWordExpected = 0x68795f61626931 // "hy_abi1"
