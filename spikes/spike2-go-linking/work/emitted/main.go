package main

import (
	"fmt"
	"os"

	"emitmod/hygen"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "boom" {
		hygen.Boom()
	}
	fmt.Println(hygen.Greet("spike2"))
	fmt.Println("asmDouble(21) =", hygen.AsmDouble(21))
}
