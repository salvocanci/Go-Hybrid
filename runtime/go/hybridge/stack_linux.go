package hybridge

// Pooled guarded Rust stacks (Spike 3): the deep-path crossing runs Rust on a
// 1 MiB mmap'd stack with a 4 KiB guard page, OUTSIDE the Go heap (never
// scanned by the GC). Slots are exclusive per crossing via a 64-bit atomic
// bitmap — the fix for the shared-stack collision that Spike 1's single
// mmap stack exhibited under concurrent cleanups (two goroutines on different
// Ms crossing at the same instant overwrite each other's Rust frames).
//
// The fast path does not use these stacks at all: shallow callees run on the
// caller's own goroutine stack after a stackguard headroom check.

import (
	"math/bits"
	"runtime"
	"sync/atomic"
	"syscall"
	"unsafe"
)

const (
	deepStacks  = 64      // pool size (one bit each)
	deepStackSz = 1 << 20 // 1 MiB per stack
	pageSize    = 4096    // guard page size

	_protRead   = 0x1
	_protWrite  = 0x2
	_protNone   = 0x0
	_mapPrivate = 0x02
	_mapAnon    = 0x20
)

var (
	deepTops [deepStacks]uintptr // stack tops (base + guard + size)
	deepBits uint64              // bitmap: bit i set = stack i in use
)

func init() {
	for i := 0; i < deepStacks; i++ {
		total := deepStackSz + pageSize
		b, err := syscall.Mmap(-1, 0, total, _protRead|_protWrite, _mapPrivate|_mapAnon)
		if err != nil {
			panic("hybridge: mmap deep stack: " + err.Error())
		}
		// guard page at the bottom (stack grows down toward it)
		if _, _, errno := syscall.Syscall(syscall.SYS_MPROTECT,
			uintptr(unsafe.Pointer(&b[0])), pageSize, _protNone); errno != 0 {
			panic("hybridge: mprotect guard page: " + errno.Error())
		}
		deepTops[i] = uintptr(unsafe.Pointer(&b[0])) + uintptr(total)
	}
}

// acquireDeep returns the index of an exclusively-held pooled stack.
func acquireDeep() int {
	for {
		old := atomic.LoadUint64(&deepBits)
		if old == ^uint64(0) {
			runtime.Gosched() // pool exhausted (64 concurrent deep calls): back off
			continue
		}
		i := bits.TrailingZeros64(^old)
		b := uint64(1) << uint(i)
		if atomic.CompareAndSwapUint64(&deepBits, old, old|b) {
			return i
		}
	}
}

// releaseDeep frees a pooled stack acquired by acquireDeep.
func releaseDeep(i int) {
	atomic.AndUint64(&deepBits, ^(uint64(1) << uint(i)))
}
