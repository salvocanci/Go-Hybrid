package cgobench

import "testing"

var csink uint64

func BenchmarkCgoTrivial(b *testing.B) {
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		CgoNoop()
	}
}

func BenchmarkCgoPlain(b *testing.B) {
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		csink = CgoAdd(uint64(i), uint64(i))
	}
}
