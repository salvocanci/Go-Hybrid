package hybridge

// Pooled guarded Rust stacks (Spike 5 copy of the Spike 3 design): deep-path
// crossings run on a 1 MiB mmap'd stack with a guard page, exclusive per
// crossing via the atomic bitmap.

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
	deepTops [deepStacks]uintptr
	deepBits uint64
)

func init() {
	for i := 0; i < deepStacks; i++ {
		total := deepStackSz + pageSize
		b, err := syscall.Mmap(-1, 0, total, _protRead|_protWrite, _mapPrivate|_mapAnon)
		if err != nil {
			panic("spike5: mmap deep stack: " + err.Error())
		}
		if _, _, errno := syscall.Syscall(syscall.SYS_MPROTECT,
			uintptr(unsafe.Pointer(&b[0])), pageSize, _protNone); errno != 0 {
			panic("spike5: mprotect guard page: " + errno.Error())
		}
		deepTops[i] = uintptr(unsafe.Pointer(&b[0])) + uintptr(total)
	}
}

func acquireDeep() int {
	for {
		old := atomic.LoadUint64(&deepBits)
		if old == ^uint64(0) {
			runtime.Gosched()
			continue
		}
		i := bits.TrailingZeros64(^old)
		b := uint64(1) << uint(i)
		if atomic.CompareAndSwapUint64(&deepBits, old, old|b) {
			return i
		}
	}
}

func releaseDeep(i int) {
	atomic.AndUint64(&deepBits, ^(uint64(1) << uint(i)))
}
