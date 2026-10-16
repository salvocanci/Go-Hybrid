// ============================================================================
// 04-pipeline-backpressure — Spike 6: examples/04-pipeline-backpressure under
// Tier-0 rules. Semantics and expected output unchanged (expected.txt):
// "total=204".
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `raw`/`sq` (bounded channels — concurrency-safe by
//   type; the size-2 buffers ARE the backpressure), `deadline` (channel from
//   time.after), `total` (main-local int), `v`/`ok` (received copies).
// Layer 2 (Rust-side owned): none.
// Layer 3 (boundary handles): none.
//
// ---- Sendability check sites (task spawn / channel send) ----
//   [S1] `task producer(raw)` — raw is a channel: GC value, no live lexical
//        borrow, safe by type: sendable (strictest reading A1c).
//   [S2] `task squarer(raw, sq)` — both channels: sendable. Note `raw` is
//        now shared by producer (send end) and squarer (receive end) — via
//        DIRECTIONAL channel types (`chan<-` / `<-chan`), the Go discipline
//        the model inherits.
//   [S3] `out <- i` / `out <- v * v` — int values: sendable (copies).
//   No mutable GC state other than the channels crosses a task boundary.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

fn producer(out chan<- int) {
    for i in 1..=8 {
        out <- i             // send site [S3]; blocks when stage 2 is slow:
    }                        // backpressure through the size-2 buffer
    close(out)
}

fn squarer(in <-chan int, out chan<- int) {
    for v in in {
        time.sleep(time.milliseconds(5)) // deliberately the slow stage
        out <- v * v        // send site [S3]
    }
    close(out)
}

fn main() {
    raw := make(chan int, 2) // SMALL buffer: backpressure is observable
    sq := make(chan int, 2)

    task producer(raw)       // spawn site [S1]
    task squarer(raw, sq)    // spawn site [S2]

    var total int
    deadline := time.after(time.seconds(2))
    loop {
        select {
            v, ok := <-sq:
                if !ok { break loop } // pipeline drained: sq closed upstream
                total += v
            <-deadline:
                panic "pipeline timed out" // never fires in the happy path
        }
    }
    fmt.println("total={total}") // 1+4+9+...+64 = 204
}
