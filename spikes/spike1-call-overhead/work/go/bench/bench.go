// Package bench: asm trampolines Go-ABI0 -> SysV, three stack strategies.
// No cgo in THIS package (Go 1.26 forbids cgo+asm in one package); function
// addresses come from package golink.
package bench

import "unsafe"

// Assembly implementations (call_amd64.s). fn is a C-ABI function pointer.
//
//go:noescape
func callRustDirect(fn unsafe.Pointer, a, b uint64) uint64 // on the goroutine stack (callee must not use stack)

//go:noescape
func callRustStack(fn unsafe.Pointer, a, b uint64) uint64 // on the 1 MiB mmap'd Rust stack

//go:noescape
func callRustStackNoop(fn unsafe.Pointer)

//go:noescape
func callRustDirectNoop(fn unsafe.Pointer)

//go:noescape
func callRustTreeStack(fn unsafe.Pointer, depth uint64) uint64 // deep recursion probe
