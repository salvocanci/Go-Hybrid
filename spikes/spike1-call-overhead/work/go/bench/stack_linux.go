package bench

// The mmap'd Rust stack: 1 MiB + 4 KiB guard page, outside the Go heap so the
// GC never scans it. Allocated once. This mirrors rustgo's original design
// (a Hybrid-owned stack pool generalizes it; spike keeps one stack).

import (
        "syscall"
        "unsafe"
)

const (
        rustStackSize = 1 << 20
        pageSize      = 4096

        _protRead   = 0x1
        _protWrite  = 0x2
        _protNone   = 0x0
        _mapPrivate = 0x02
        _mapAnon    = 0x20
)

var (
        rustStack    unsafe.Pointer // base; guard page at [base, base+4096)
        rustStackTop uintptr        // grows down toward the guard
)

func init() {
        total := rustStackSize + pageSize
        b, err := syscall.Mmap(-1, 0, total, _protRead|_protWrite, _mapPrivate|_mapAnon)
        if err != nil {
                panic("spike1: mmap rust stack: " + err.Error())
        }
        // guard page at the bottom
        if _, _, errno := syscall.Syscall(syscall.SYS_MPROTECT,
                uintptr(unsafe.Pointer(&b[0])), pageSize, _protNone); errno != 0 {
                panic("spike1: mprotect guard page: " + errno.Error())
        }
        rustStack = unsafe.Pointer(&b[0])
        rustStackTop = uintptr(rustStack) + uintptr(total)
}
