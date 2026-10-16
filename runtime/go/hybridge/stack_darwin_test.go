package hybridge

import (
	"runtime/debug"
	"syscall"
	"testing"
	"unsafe"
)

func TestDarwinDeepStackPool(t *testing.T) {
	seen := make(map[int]bool)
	for range deepStacks {
		i := acquireDeep()
		defer releaseDeep(i)
		if seen[i] {
			t.Fatalf("stack %d acquired twice before release", i)
		}
		seen[i] = true
		top := deepTops[i]
		if top%uintptr(syscall.Getpagesize()) != 0 {
			t.Fatalf("stack %d top is not native-page aligned", i)
		}
		// Both ends of the usable region must be writable. In particular,
		// using a 4 KiB guard offset on Apple Silicon must not protect it.
		mapping := deepMappings[i]
		if top != uintptr(unsafe.Pointer(&mapping[len(mapping)-1]))+1 {
			t.Fatal("stack top does not match the mapping end")
		}
		mapping[syscall.Getpagesize()] = byte(i)
		mapping[len(mapping)-1] = byte(i)
	}
}

func TestDarwinDeepStackGuard(t *testing.T) {
	i := acquireDeep()
	defer releaseDeep(i)
	old := debug.SetPanicOnFault(true)
	defer debug.SetPanicOnFault(old)
	defer func() {
		if recover() == nil {
			t.Error("write below the usable stack did not fault: guard is unprotected")
		}
	}()
	deepMappings[i][syscall.Getpagesize()-1] = 1
}
