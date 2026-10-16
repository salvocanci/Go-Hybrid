// Go ABI0 -> SysV amd64 trampolines. Discipline (same rules the Hybrid
// compiler must emit):
//   1. load all Go-frame inputs BEFORE any SP switch;
//   2. save old SP in a SysV callee-saved register (RBX);
//   3. restore SP BEFORE writing results to the Go frame;
//   4. 16-byte-align the foreign SP before CALL (callee entry rsp%16==8);
//   5. NOSPLIT: no Go stack growth while on the foreign stack.

#include "textflag.h"

// func callRustDirect(fn unsafe.Pointer, a, b uint64) uint64
// Runs the callee on the GOROUTINE stack. Only safe for leaf-ish Rust code
// that uses little stack (lower-bound measurement). No alignment fix (Go
// guarantees 8; callee must tolerate 16-misalignment — ours does).
TEXT ·callRustDirect(SB), NOSPLIT, $0-32
	MOVQ	fn+0(FP), AX
	MOVQ	a+8(FP), DI
	MOVQ	b+16(FP), SI
	CALL	AX
	MOVQ	AX, ret+24(FP)
	RET

// func callRustDirectNoop(fn unsafe.Pointer)
TEXT ·callRustDirectNoop(SB), NOSPLIT, $0-8
	MOVQ	fn+0(FP), AX
	CALL	AX
	RET

// func callRustStack(fn unsafe.Pointer, a, b uint64) uint64
// Switch to the mmap'd Rust stack, call, restore. The SAFE design.
TEXT ·callRustStack(SB), NOSPLIT, $0-32
	MOVQ	fn+0(FP), AX            // target
	MOVQ	a+8(FP), DI             // SysV arg0
	MOVQ	b+16(FP), SI            // SysV arg1
	MOVQ	·rustStackTop(SB), R11  // new stack top
	MOVQ	SP, BX                  // save Go SP (RBX: SysV callee-saved)
	MOVQ	R11, SP                 // SWITCH
	ANDQ	$-16, SP                // SysV alignment before CALL pushes ret
	CALL	AX                      // -> RAX
	MOVQ	BX, SP                  // RESTORE before touching FP
	MOVQ	AX, ret+24(FP)
	RET

// func callRustStackNoop(fn unsafe.Pointer)
TEXT ·callRustStackNoop(SB), NOSPLIT, $0-8
	MOVQ	fn+0(FP), AX
	MOVQ	·rustStackTop(SB), R11
	MOVQ	SP, BX
	MOVQ	R11, SP
	ANDQ	$-16, SP
	CALL	AX
	MOVQ	BX, SP
	RET

// func callRustTreeStack(fn unsafe.Pointer, depth uint64) uint64
TEXT ·callRustTreeStack(SB), NOSPLIT, $0-24
	MOVQ	fn+0(FP), AX
	MOVQ	a+8(FP), DI
	MOVQ	·rustStackTop(SB), R11
	MOVQ	SP, BX
	MOVQ	R11, SP
	ANDQ	$-16, SP
	CALL	AX
	MOVQ	BX, SP
	MOVQ	AX, ret+16(FP)
	RET
