// ============================================================================
// 02-cli-cat — Spike 6: examples/02-cli-cat under Tier-0 rules.
// Semantics and expected output unchanged (expected.txt): stdout = the input
// file's bytes verbatim, exit 0; on missing file: stderr
// "cat: open <file>: no such file or directory", exit 1.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `args`/`path` (strings), `f` (*os.File), `buf`
//   (64 KiB []byte), `n`/`total` (ints), `r`/`w` (io interface values).
//   All GC'd; reads are copies. `buf` passed to `r.read` is a write-view for
//   ONE call; `buf[..n]` passed to `w.write` is a read-view for ONE call —
//   call-argument views of GC values, never stored, never loans.
// Layer 2 (Rust-side owned): none.
// Layer 3 (boundary handles): none — os/io are GO packages; Hybrid→Go calls
//   are ordinary calls after Go-source emission (Spike 2), not the checked
//   Rust boundary.
//
// ---- Sendability check sites (task spawn / channel send) ----
//   NONE.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
//
// Non-ownership flag for SPEC-LANGUAGE.md (A8 in RESULTS.md): the top-level
// `?` defines process behavior — exit 1 + stderr "cat: {err}" — the expected
// output pins that contract.
// ============================================================================

fn copy_stream(r io.reader, w io.writer) (total int, err error) {
    buf := make([]byte, 64*1024)   // GC slice, reused across reads: one buffer
    loop {
        n, rerr := r.read(buf)     // write-view of buf for THIS call only
        if n > 0 {
            _, werr := w.write(buf[..n]) // read-view of buf[..n] for THIS call
            if werr != nil {
                return total, werr
            }
            total += n
        }
        if rerr == io.eof {
            return total, nil      // clean EOF ends the copy
        }
        if rerr != nil {
            return total, rerr
        }
    }
}

fn main() (code int) {
    args := os.args()
    if len(args) < 2 {
        fmt.eprintln("usage: cat <file>")
        return 1
    }
    path := args[1]

    f := os.open(path)?      // `?`: (T, error) propagates upward; at main's
                             // top level: stderr "cat: open <path>: ...", exit 1
    defer f.close()          // deferred call runs on main's return path

    _, err := copy_stream(f, os.stdout())
    if err != nil {
        fmt.eprintln("cat: {err}")
        return 1
    }
    return 0
}
