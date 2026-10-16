// Package rt5: linkname access to the pinned runtime's syscall-handoff pair
// (Spike 4, mechanism M2). This is the EXACT pattern stdlib uses in
// syscall/syscall_linux.go (runtime_entersyscall / runtime_exitsyscall) —
// same pinned go1.26.9, same legality. Canary tests pin the behavior:
// TestM2CanaryPReleased proves the P is actually handed back.
//
// Stdlib's "no wrapper inbetween" caveat: entersyscall captures the caller's
// PC/SP, so syscallsp lands in THIS wrapper's frame. Frames below it (this
// wrapper, the asm trampoline, Rust) hold no scannable Go pointers — the
// crossing passes only a code address and an integer — and the canary +
// deadlock tests + the race leg validate the behavior empirically.
package rt5

import _ "unsafe"

//go:linkname Entersyscall runtime.entersyscall
func Entersyscall()

//go:linkname Entersyscallblock runtime.entersyscallblock
func Entersyscallblock()

//go:linkname Exitsyscall runtime.exitsyscall
func Exitsyscall()
