// Go ABI0 -> SysV amd64 trampolines for Spike 4.
//
// Same discipline as Spike 3 (load args before SP adjust, save old SP in RBX,
// 16-byte SysV alignment, restore SP before writing results, NOSPLIT), plus:
//
//   callSyswin1 — the SYSCALL-WINDOW call for M2a/M2b. After
//   runtime.entersyscall/entersyscallblock the runtime sets
//   g.stackguard0 = stackPreempt, so NO Go-style stack check may run inside
//   the window (it would loop into the preempt path while the goroutine is
//   _Gsyscall — a cgo-shaped situation, which is why cgo's own calls are
//   exactly this shape). The Go wrapper therefore pre-checks headroom
//   (>= syswinStackNeed) BEFORE entering the window and only then calls
//   callSyswin1, which does the raw aligned CALL with no guard read.

#include "textflag.h"

// get_tls/g macros inlined from $GOROOT/src/runtime/go_tls.h (GOARCH_amd64):
// the assembler's include path does not carry go_tls.h for user packages.
#define get_tls(r)      MOVQ TLS, r
#define g(r)            0(r)(TLS*1)

// go1.26.9 linux/amd64 runtime offsets (extracted by the Spike 3
// extract_offsets.py tool; same pin + canary discipline).
#define OFF_g_stackguard0 16

// func spHeadroom() uintptr  — SP - g.stackguard0 (bytes left above guard)
TEXT ·spHeadroom(SB), NOSPLIT, $0-8
        get_tls(BX)
        MOVQ    g(BX), BX
        MOVQ    OFF_g_stackguard0(BX), AX
        MOVQ    SP, DX
        SUBQ    AX, DX
        MOVQ    DX, ret+0(FP)
        RET

// ------------------------------- fast path (caller's goroutine stack)

// func callFast1(fn unsafe.Pointer, a1 uintptr) uint64
TEXT ·callFast1(SB), NOSPLIT, $0-24
        MOVQ    fn+0(FP), AX
        MOVQ    a1+8(FP), DI
        get_tls(BX)
        MOVQ    g(BX), BX
        MOVQ    OFF_g_stackguard0(BX), DX
        MOVQ    SP, R11
        SUBQ    DX, R11
        CMPQ    R11, $4096
        JLT     needsdeep1
        MOVQ    SP, BX
        SUBQ    $8, SP
        ANDQ    $-16, SP
        CALL    AX
        MOVQ    BX, SP
        MOVQ    AX, ret+16(FP)
        RET
needsdeep1:
        MOVQ    $-2, AX
        MOVQ    AX, ret+16(FP)
        RET

// func callFast2(fn unsafe.Pointer, a1, a2 uintptr) uint64
TEXT ·callFast2(SB), NOSPLIT, $0-32
        MOVQ    fn+0(FP), AX
        MOVQ    a1+8(FP), DI
        MOVQ    a2+16(FP), SI
        get_tls(BX)
        MOVQ    g(BX), BX
        MOVQ    OFF_g_stackguard0(BX), DX
        MOVQ    SP, R11
        SUBQ    DX, R11
        CMPQ    R11, $4096
        JLT     needsdeep2
        MOVQ    SP, BX
        SUBQ    $8, SP
        ANDQ    $-16, SP
        CALL    AX
        MOVQ    BX, SP
        MOVQ    AX, ret+24(FP)
        RET
needsdeep2:
        MOVQ    $-2, AX
        MOVQ    AX, ret+24(FP)
        RET

// ------------------------------- deep path (pooled guarded mmap stack)

// func callDeep1(fn unsafe.Pointer, a1 uintptr, stack uintptr) uint64
TEXT ·callDeep1(SB), NOSPLIT, $0-32
        MOVQ    fn+0(FP), AX
        MOVQ    a1+8(FP), DI
        MOVQ    stack+16(FP), R11
        MOVQ    SP, BX
        MOVQ    R11, SP
        ANDQ    $-16, SP
        CALL    AX
        MOVQ    BX, SP
        MOVQ    AX, ret+24(FP)
        RET

// func callDeep2(fn unsafe.Pointer, a1, a2 uintptr, stack uintptr) uint64
TEXT ·callDeep2(SB), NOSPLIT, $0-40
        MOVQ    fn+0(FP), AX
        MOVQ    a1+8(FP), DI
        MOVQ    a2+16(FP), SI
        MOVQ    stack+24(FP), R11
        MOVQ    SP, BX
        MOVQ    R11, SP
        ANDQ    $-16, SP
        CALL    AX
        MOVQ    BX, SP
        MOVQ    AX, ret+32(FP)
        RET

// ------------------------------- syscall-window call (M2a/M2b)
// NO guard check: the wrapper pre-checked headroom before entering the
// window; inside it, stackguard0 is stackPreempt and must not be consulted.

// func callSyswin1(fn unsafe.Pointer, a1 uintptr) uint64
TEXT ·callSyswin1(SB), NOSPLIT, $0-24
        MOVQ    fn+0(FP), AX
        MOVQ    a1+8(FP), DI
        MOVQ    SP, BX
        SUBQ    $8, SP
        ANDQ    $-16, SP
        CALL    AX
        MOVQ    BX, SP
        MOVQ    AX, ret+16(FP)
        RET
