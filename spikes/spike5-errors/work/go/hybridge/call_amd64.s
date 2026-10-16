// Go ABI0 -> SysV amd64 trampolines for Spike 5. Copy of the Spike 3
// discipline plus the WIDE variant: HyResult {code:u32, payload:u64} is a
// 16-byte two-INTEGER-class struct, returned in RAX:RDX — callWide2 returns
// both words to the Go frame.
//
// Discipline (bridge-generator rules): inputs loaded before SP adjustment;
// old SP in RBX (SysV callee-saved); 16-byte alignment at callee entry;
// SP restored before writing results; NOSPLIT throughout.

#include "textflag.h"

// get_tls/g macros inlined from $GOROOT/src/runtime/go_tls.h (GOARCH_amd64).
#define get_tls(r)      MOVQ TLS, r
#define g(r)            0(r)(TLS*1)

// go1.26.9 linux/amd64 runtime offsets (spikes/spike3-memory/work/extract_offsets.py).
#define OFF_g_stackguard0 16

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

// func callWide2(fn unsafe.Pointer, a1, a2 uintptr) (r1, r2 uint64)
// Callee returns HyResult in RAX (code word) and RDX (payload).
TEXT ·callWide2(SB), NOSPLIT, $0-40
        MOVQ    fn+0(FP), AX
        MOVQ    a1+8(FP), DI
        MOVQ    a2+16(FP), SI
        get_tls(BX)
        MOVQ    g(BX), BX
        MOVQ    OFF_g_stackguard0(BX), DX
        MOVQ    SP, R11
        SUBQ    DX, R11
        CMPQ    R11, $4096
        JLT     needswide2
        MOVQ    SP, BX
        SUBQ    $8, SP
        ANDQ    $-16, SP
        CALL    AX
        MOVQ    BX, SP
        MOVQ    AX, r1+24(FP)
        MOVQ    DX, r2+32(FP)
        RET
needswide2:
        MOVQ    $-2, AX
        MOVQ    AX, r1+24(FP)
        MOVQ    AX, r2+32(FP)
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

// func callWideDeep2(fn unsafe.Pointer, a1, a2 uintptr, stack uintptr) (r1, r2 uint64)
TEXT ·callWideDeep2(SB), NOSPLIT, $0-48
        MOVQ    fn+0(FP), AX
        MOVQ    a1+8(FP), DI
        MOVQ    a2+16(FP), SI
        MOVQ    stack+24(FP), R11
        MOVQ    SP, BX
        MOVQ    R11, SP
        ANDQ    $-16, SP
        CALL    AX
        MOVQ    BX, SP
        MOVQ    AX, r1+32(FP)
        MOVQ    DX, r2+40(FP)
        RET
