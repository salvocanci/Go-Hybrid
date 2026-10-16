// ============================================================================
// 03-worker-pool — Spike 6: examples/03-worker-pool under Tier-0 rules.
// Semantics and expected output unchanged (expected.txt): "[2 2 4 6 8 10 12 18]".
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `jobs`/`results` (channels — concurrency-safe BY
//   TYPE), `job`/`result` structs (sent as FRESH literals: no aliases exist
//   at the send site), `inputs`, `got`, `j`, `r` (received copies).
// Layer 2 (Rust-side owned): none.
// Layer 3 (boundary handles): none.
//
// ---- Sendability check sites (task spawn / channel send) ----
//   [S1] 4x `task worker(i, jobs, results)` — spawn-site checks:
//        i (int, value copy): sendable.
//        jobs, results (channels): GC values with no live lexical borrow AND
//        concurrency-safe by type: sendable under the STRICTEST reading
//        (A1c in RESULTS.md). Sharing a channel across tasks is exactly what
//        channels are for; main later sends on / closes `jobs` — legal.
//   [S2] `jobs <- job{input: v, cost_ms: (v % 3)}` — send-site check: fresh
//        struct literal, no other reference exists: sendable (all readings).
//   [S3] `results <- result{...}` inside workers — fresh literal: sendable.
//   No mutable GC value other than the channels is aliased across any spawn
//   or send: `got`, `inputs`, `total`-shaped locals are single-task.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

struct job {
    input   int
    cost_ms int
}

struct result {
    worker int
    value  int
}

fn worker(id int, jobs <-chan job, results chan<- result) {
    for j in jobs {          // ranges until channel close
        // simulate uneven work
        time.sleep(time.milliseconds(j.cost_ms))
        results <- result{worker: id, value: j.input * 2} // send site [S3]
    }
}

fn main() {
    const n_workers = 4
    jobs := make(chan job, 16)    // buffered: the submit loop never blocks
    results := make(chan result, 16)

    for i in 0..n_workers {
        task worker(i, jobs, results) // spawn site [S1]
    }

    inputs := [3, 1, 4, 1, 5, 9, 2, 6]
    for _, v in inputs {
        jobs <- job{input: v, cost_ms: (v % 3)} // send site [S2]
    }
    close(jobs)              // no more work; workers drain and exit

    var got []int
    for len(got) < len(inputs) {   // deterministic join: count, not WaitGroup
        r := <-results
        got = append(got, r.value)
    }

    sort.ints(got)
    fmt.println(got)         // [2 2 4 6 8 10 12 18]
}
