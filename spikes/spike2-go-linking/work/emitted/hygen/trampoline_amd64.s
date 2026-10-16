// Emitted Hybrid trampoline (spike-2 stand-in): proves go build links emitted .s.
#include "textflag.h"

TEXT ·asmDouble(SB), NOSPLIT, $0-16
	MOVQ	x+0(FP), AX
	ADDQ	AX, AX
	MOVQ	AX, ret+8(FP)
	RET
