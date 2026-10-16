// ============================================================================
// 14-a7-use-after-consuming — Checker corpus #14 (pre-registered BEFORE any
// checker exists; human ruling 2026-10-12, QUESTIONS.md Q1).
//
// PURPOSE: exercise A7 on its REJECT side: USE AFTER a CONSUMING API call.
// `enc.finish()` is flagged `consume` in the boundary descriptor
// (interfaces/abi-types.md): the call takes OWNERSHIP of the handle
// (own-transfer INTO the API) and returns the flushed bytes. Using `enc`
// afterwards is use-after-own-transfer. Realistic porting bug: appending
// the trailer AFTER closing the compression stream — the kind of thing
// Go surfaces as a nil/panic at runtime and Tier 0 must surface at
// compile time.
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): `payload` (const string), `chunk` (string view —
//   one-call pinned view, never stored), `total` (int), `out` ([]byte —
//   fresh from finish).
// Layer 2 (Rust-side owned): the flate2 encoder state — behind Layer 3.
// Layer 3 (boundary handles): `enc` = OWN handle (writer). `enc.write`
//   = mutating call (call-scoped loan). `enc.finish()` = CONSUMING call
//   — the own-transfer site; after it, `enc` is moved-from.
//
// ---- Sendability / check sites (task spawn / channel send) ----
//   NONE — single-task program; the violation is the handle transfer.
//
// ---- Expected verdict (PRE-REGISTERED 2026-10-12, before any checker) ----
// EXPECTED-VERDICT: REJECT A7
//   REJECT — A7 (use-after-own-transfer at a consuming call). Not
//   contested on the verdict itself; the consuming-flag DECLARATION
//   surface is flagged (OQ8: where `consume` is declared — boundary
//   descriptor per interfaces/abi-types.md here — and whether Hybrid-side
//   non-boundary methods can be consuming). Fix: write the trailer BEFORE
//   finish(), or create a new writer for it. The diagnostic must point at
//   the TRANSFER site (the finish() line), not just the failing use —
//   Q1 item 3: the message teaches where ownership left.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0. `managed` blocks: 0.
// ============================================================================

import "rust/flate2"    // pinned crate; `finish` flagged `consume` in the
                        // boundary descriptor (interfaces/abi-types.md)

const payload = "hybrid emits go source zero install adoption story " +
    "one build command pinned toolchain trailer checksum follows"

fn main() {
    enc := flate2.new_writer(6)?      // OWN handle: compression encoder

    var total int
    for i in 0..len(payload) / 32 {
        chunk := payload[i * 32: i * 32 + 32]  // string view: ONE call,
        total += enc.write(chunk)?             // never stored
    }

    out := enc.finish()?              // [C1] CONSUMING call: own-transfer
                                      // INTO the API — `enc` is moved-from
                                      // as of this line
    fmt.println("compressed {total}B -> {len(out)}B")

    enc.write([]byte("trailer"))?     // VIOLATION (A7): use-after-consume —
                                      // ownership left at the finish() line
}
