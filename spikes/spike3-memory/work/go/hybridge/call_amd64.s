// Go ABI0 -> SysV amd64 trampolines for Spike 3.
//
// DESIGN (fixes the shared-stack collision found by TestConcurrentCrossing —
// Spike 1's single mmap stack is NOT safe when two goroutines cross at the
// same time on different Ms):
//
//   FAST path: run the callee on the CALLER'S OWN goroutine stack, but only
//   after a manual stackguard check guarantees headroom (the Go compiler
//   would normally do this in the prologue; our NOSPLIT asm must do it via
//   the Go wrapper calling ·spHeadroom). Per-goroutine stack = concurrent by
//   construction, preemption-safe (the goroutine stack is a normal stack),
//   and GC-safe (pinned borrows keep objects alive; unknown PCs terminate
//   stack walks, exactly like cgo frames).
//
//   DEEP path (callDeepN): switch to one of the bitmap-pooled guarded mmap
//   stacks (1 MiB + guard page each, exclusive per crossing) for callees
//   flagged deep-capable or when headroom is missing.
//
// Trampoline discipline (both paths — the rules the bridge generator emits):
//   1. load all Go-frame inputs BEFORE any SP adjustment;
//   2. save old SP in a SysV callee-saved register (RBX);
//   3. 16-byte SysV alignment before CALL (callee entry rsp%16==8);
//   4. restore SP BEFORE writing results to the Go frame;
//   5. NOSPLIT: no Go stack growth inside.

#include "textflag.h"

// get_tls/g macros inlined from $GOROOT/src/runtime/go_tls.h (GOARCH_amd64):
// the assembler's include path does not carry go_tls.h for user packages.
#define get_tls(r)      MOVQ TLS, r
#define g(r)            0(r)(TLS*1)

// go1.26.9 linux/amd64 runtime offsets (extracted by ../extract_offsets.py;
// a Go version bump regenerates them — CI canary is the offsets test).
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
// The stackguard check is INLINED here (what the bridge generator emits per
// call site — no extra Go wrapper layer). If headroom < 4096, the callee is
// NOT invoked: the sentinel NEEDS_DEEP (0xFF..FE) is returned and the Go
// wrapper retries on a pooled deep stack. Production uses a dedicated flag
// register instead of a value sentinel.

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

// func callFast3(fn unsafe.Pointer, a1, a2, a3 uintptr) uint64
TEXT ·callFast3(SB), NOSPLIT, $0-40
        MOVQ    fn+0(FP), AX
        MOVQ    a1+8(FP), DI
        MOVQ    a2+16(FP), SI
        MOVQ    a3+24(FP), DX
        get_tls(BX)
        MOVQ    g(BX), BX
        MOVQ    OFF_g_stackguard0(BX), R11
        MOVQ    SP, R12
        SUBQ    R11, R12
        CMPQ    R12, $4096
        JLT     needsdeep3
        MOVQ    SP, BX
        SUBQ    $8, SP
        ANDQ    $-16, SP
        CALL    AX
        MOVQ    BX, SP
        MOVQ    AX, ret+32(FP)
        RET
needsdeep3:
        MOVQ    $-2, AX
        MOVQ    AX, ret+32(FP)
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

// func callDeep3(fn unsafe.Pointer, a1, a2, a3 uintptr, stack uintptr) uint64
TEXT ·callDeep3(SB), NOSPLIT, $0-48
        MOVQ    fn+0(FP), AX
        MOVQ    a1+8(FP), DI
        MOVQ    a2+16(FP), SI
        MOVQ    a3+24(FP), DX
        MOVQ    stack+32(FP), R11
        MOVQ    SP, BX
        MOVQ    R11, SP
        ANDQ    $-16, SP
        CALL    AX
        MOVQ    BX, SP
        MOVQ    AX, ret+40(FP)
        RET
