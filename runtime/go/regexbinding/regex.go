package regexbinding

import (
	"errors"
	"runtime"
	"unsafe"

	"hybrid.program/hybridge"
)

// The binding's error surface (Spike 5 sentinel shape).
var ErrRegex = errors.New("regex: pattern or text invalid")

// pinString: the copy-small pinned borrow for one string argument.
func pinString(s string) (uintptr, uintptr, *runtime.Pinner, []byte) {
	b := []byte(s)
	var p runtime.Pinner
	if len(b) > 0 {
		p.Pin(&b[0])
		return uintptr(unsafe.Pointer(&b[0])), uintptr(len(b)), &p, b
	}
	return 0, 0, &p, b
}

// IsMatch reports whether text matches pattern (compile per call — the
// example surface calls it once; hot loops pin the compiled form post-MVP).
func IsMatch(pattern, text string) (bool, error) {
	pptr, plen, pp, pb := pinString(pattern)
	tptr, tlen, tp, tb := pinString(text)
	v := int64(hybridge.Cross4(FnIsMatch, pptr, plen, tptr, tlen))
	pp.Unpin()
	tp.Unpin()
	runtime.KeepAlive(pp)
	runtime.KeepAlive(pb)
	runtime.KeepAlive(tp)
	runtime.KeepAlive(tb)
	if v < 0 {
		return false, ErrRegex
	}
	return v == 1, nil
}

// IsValid reports whether the pattern compiles (validity as a bool — no
// error channel; example 09's simple_pattern surface).
func IsValid(pattern string) bool {
	pptr, plen, pp, pb := pinString(pattern)
	v := hybridge.Cross2(FnIsValid, pptr, plen)
	pp.Unpin()
	runtime.KeepAlive(pp)
	runtime.KeepAlive(pb)
	return v == 1
}
