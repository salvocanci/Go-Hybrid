package cgobench

/*
#include <stdint.h>

static int64_t c_add(int64_t a, int64_t b) { return a + b; }
static void c_noop(void) {}
*/
import "C"

// Plain cgo crossings: the reference points the asm trampolines are measured
// against. (cgo is not allowed in _test.go files, hence this package.)

func CgoAdd(a, b uint64) uint64 { return uint64(C.c_add(C.int64_t(a), C.int64_t(b))) }
func CgoNoop()                  { C.c_noop() }
