// ============================================================================
// 07-lru-generics — Spike 6: examples/07-lru-generics under Tier-0 rules.
// Semantics and expected output unchanged (expected.txt):
//     b evicted
//     a=1
//
// ---- Tier-0 rule set applied to each value ----
// Layer 1 (Go-side GC): the cache struct, `entries` (map), `order` (slice),
//   all keys/values. THE load-bearing rule (RESULTS A4): Go-heap reads are
//   COPIES, not loans — `v, ok := c.entries[key]` yields a copied `v`, so
//   the subsequent `c.touch(key)` (unique-write receiver loan) does NOT
//   conflict. In Rust the same shape (`map.get`) would hold a loan through
//   the if-body; in Hybrid it does not, because the read is a copy.
// Layer 2 (Rust-side owned): none.
// Layer 3 (boundary handles): none.
//
// Loans traced (all function-local, non-lexical):
//   - `(c *lru_cache)` receivers: unique-write loan per call; `get` calls
//     `touch` AFTER its map read completed (the read is a copy — no overlap).
//   - `touch` mutates `c.order` while iterating `for i, ek in c.order`:
//     legal because the range reads the slice ONCE (a copy of the header,
//     rule A4) and the loop breaks immediately after the splice.
//   - `evict := c.order[0]` — copied out; the following `c.order = c.order[1:]`
//     mutation does not invalidate it.
//
// ---- Sendability check sites (task spawn / channel send) ----
//   NONE.
//
// ---- Annotations / managed ----
//   lifetime annotations: 0 (target met). `managed` blocks: 0 (target met).
// ============================================================================

struct lru_cache[k comparable, v any] {
    cap     int
    entries map[k]v
    order   []k             // simplest possible LRU order tracking
}

fn lru_cache.new[k comparable, v any](cap int) lru_cache[k, v] {
    return lru_cache[k, v]{cap: cap, entries: map[k]v{}, order: []k{}}
}

fn (c *lru_cache[k, v]) get(key k) option[v] {  // no nil: some(v) or none
    if v, ok := c.entries[key]; ok { // map read: v is a COPY — not a loan (A4)
        c.touch(key)                 // receiver loan AFTER the read: no overlap
        return some(v)
    }
    return none
}

fn (c *lru_cache[k, v]) put(key k, value v) {
    if _, ok := c.entries[key]; !ok && len(c.order) == c.cap {
        evict := c.order[0]          // copied out (A4): evict stays valid
        c.order = c.order[1:]        // mutation after the copy: legal
        delete(c.entries, evict)
    }
    c.entries[key] = value
    c.touch(key)
}

fn (c *lru_cache[k, v]) touch(key k) {
    // move `key` to the back of the recency order
    for i, ek in c.order {           // range reads c.order once (header copy)
        if ek == key {
            c.order = append(c.order[..i], c.order[i+1:]...) // splice out
            break                    // loop leaves immediately after mutation
        }
    }
    c.order = append(c.order, key)
}

fn main() {
    c := lru_cache.new[string, int](2) // instantiates for (string, int)
    c.put("a", 1)
    c.put("b", 2)
    _ = c.get("a")                   // "a" becomes most recent
    c.put("c", 3)                    // evicts "b"

    match c.get("b") {
        some(v): fmt.println("b={v}") // NOT taken
        none:     fmt.println("b evicted")
    }
    match c.get("a") {
        some(v): fmt.println("a={v}")
        none:     fmt.println("a evicted")
    }
}
