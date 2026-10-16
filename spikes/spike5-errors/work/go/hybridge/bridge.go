// Package hybridge: the Spike 5 Go side — the (T, error) mapping layer over
// the C-ABI HyResult two-word return. Sentinels are PRE-ALLOCATED and
// pointer-stable so errors.Is works by identity; payload errors wrap the
// sentinel with %w.
package hybridge

import (
	"errors"
	"fmt"
	"unsafe"

	"spike5/golink"
)

// needsDeep: sentinel for the fast path declining due to headroom.
const needsDeep = ^uint64(1)

//go:noescape
func callFast2(fn unsafe.Pointer, a1, a2 uintptr) uint64

//go:noescape
func callWide2(fn unsafe.Pointer, a1, a2 uintptr) (r1, r2 uint64)

//go:noescape
func callDeep2(fn unsafe.Pointer, a1, a2 uintptr, stack uintptr) uint64

//go:noescape
func callWideDeep2(fn unsafe.Pointer, a1, a2 uintptr, stack uintptr) (r1, r2 uint64)

func cross2(fn unsafe.Pointer, a1, a2 uintptr) uint64 {
	v := callFast2(fn, a1, a2)
	if v == needsDeep {
		i := acquireDeep()
		v = callDeep2(fn, a1, a2, deepTops[i])
		releaseDeep(i)
	}
	return v
}

func crossWide2(fn unsafe.Pointer, a1, a2 uintptr) (uint64, uint64) {
	r1, r2 := callWide2(fn, a1, a2)
	if r1 == needsDeep {
		i := acquireDeep()
		r1, r2 = callWideDeep2(fn, a1, a2, deepTops[i])
		releaseDeep(i)
	}
	return r1, r2
}

// ------------------------------------------------------------ error table

// Rust error codes (mirrors hyerr/src/lib.rs).
const (
	CodeOk         = 0
	CodeNotFound   = 1
	CodeInvalidArg = 2
	CodeOverflow   = 3
	CodeIo         = 4
)

// Pre-allocated, pointer-stable sentinels: errors.Is works by identity.
var (
	ErrNotFound   = errors.New("hybrid: not found")
	ErrInvalidArg = errors.New("hybrid: invalid argument")
	ErrOverflow   = errors.New("hybrid: overflow")
	ErrIo         = errors.New("hybrid: io")
)

var sentinels = map[uint32]error{
	CodeNotFound:   ErrNotFound,
	CodeInvalidArg: ErrInvalidArg,
	CodeOverflow:   ErrOverflow,
	CodeIo:         ErrIo,
}

// PayloadError carries the Rust payload AND wraps the sentinel so that
// errors.Is(err, ErrX) stays true and errors.As recovers the payload.
type PayloadError struct {
	Payload uint64
	Err     error // the sentinel (wrapped)
}

func (e *PayloadError) Error() string { return fmt.Sprintf("%v: payload %d", e.Err, e.Payload) }
func (e *PayloadError) Unwrap() error { return e.Err }

// mapErr: code 0 -> nil; known code -> sentinel; payload path -> wrapped.
// The sentinel arm performs ZERO allocations.
func mapErr(code uint32, payload uint64, withPayload bool) error {
	if code == CodeOk {
		return nil
	}
	base, ok := sentinels[code]
	if !ok {
		base = errors.New("hybrid: unknown error code") // 1 alloc, defensive only
	}
	if !withPayload {
		return base // 0 allocs
	}
	return &PayloadError{Payload: payload, Err: base} // 1 alloc
}

// ------------------------------------------------------------ typed API

// OkAdd: the (T, error) ok path — value + nil error, zero allocs.
func OkAdd(a, b uint64) (uint64, error) {
	c1, c2 := crossWide2(golink.FnOkAdd, uintptr(a), uintptr(b))
	if c1 != CodeOk {
		return 0, mapErr(uint32(c1), c2, true)
	}
	return c2, nil
}

// MayFail: flag==0 -> ok(payload=a); else error code (a%4)+1 payload a.
// withPayload selects the sentinel (0 alloc) vs wrapped (1 alloc) arm.
func MayFail(a, flag uint64, withPayload bool) (uint64, error) {
	c1, c2 := crossWide2(golink.FnMayFail, uintptr(a), uintptr(flag))
	if c1 != CodeOk {
		return 0, mapErr(uint32(c1), c2, withPayload)
	}
	return c2, nil
}

// ChainFail: errors with a defined Rust-side source chain.
func ChainFail(which uint64) (uint64, error) {
	c1, c2 := crossWide2(golink.FnChainFail, uintptr(which), 0)
	if c1 != CodeOk {
		return 0, mapErr(uint32(c1), c2, true)
	}
	return c2, nil
}

// Panic: invokes the Rust panic probe (abort contract; never returns).
func Panic() {
	crossWide2(golink.FnPanic, 0, 0)
}

// BenchResult: the Rust-side Result loop reference (E6).
func BenchResult(iters, errEvery uint64) uint64 {
	return cross2(golink.FnBenchResult, uintptr(iters), uintptr(errEvery))
}

// keep unsafe import used (crossing helpers take unsafe.Pointer)
var _ = unsafe.Pointer(nil)
