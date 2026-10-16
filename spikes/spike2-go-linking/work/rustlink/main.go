package main

/*
#cgo LDFLAGS: -L${SRCDIR}/../../../spike1-call-overhead/work/rustrt/target/release -l:librustrt.a -lpthread -ldl -lm
#include <stdint.h>
extern uint64_t hybrid_add(uint64_t a, uint64_t b);
*/
import "C"

import "fmt"

func main() {
	fmt.Println("rustlink: hybrid_add(40,2) =", uint64(C.hybrid_add(40, 2)))
}
