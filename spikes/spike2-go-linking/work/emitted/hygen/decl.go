package hygen

// AsmDouble is implemented in trampoline_amd64.s (emitted assembly).
func asmDouble(x uint64) uint64

// AsmDouble doubles x through the emitted trampoline.
func AsmDouble(x uint64) uint64 { return asmDouble(x) }
