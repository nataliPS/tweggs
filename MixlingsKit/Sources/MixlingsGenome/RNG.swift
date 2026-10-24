// mulberry32 (genome-spec §3). Mirrors engine-ts/src/rng.ts.
//
// Semantics notes vs. JavaScript:
//  - All values are UInt32. On UInt32, Swift `>>` is a LOGICAL shift, i.e. JS `>>>`.
//  - `&+` / `&*` wrap mod 2^32, i.e. JS `(x + y) >>> 0` / `Math.imul(x, y) >>> 0`.
//  - `^` and `|` on UInt32 are bit-identical to JS once the JS result is taken `>>> 0`.

@inline(__always)
func imul(_ a: UInt32, _ b: UInt32) -> UInt32 {
    return UInt32(truncatingIfNeeded: a) &* b
}

public struct Mulberry32: Sendable {
    public private(set) var state: UInt32

    public init(seed: UInt32) {
        self.state = seed
    }

    /// Next UInt32.
    public mutating func next() -> UInt32 {
        state = state &+ 0x6D2B_79F5
        var t: UInt32 = state
        t = imul(t ^ (t >> 15), t | 1)
        t ^= t &+ imul(t ^ (t >> 7), t | 61)
        return t ^ (t >> 14)
    }

    /// Float in [0, 1): next() / 2^32. Exact in Double, identical to JS.
    public mutating func float() -> Double {
        return Double(next()) / 4_294_967_296.0
    }

    /// Integer in [0, n): next() % n. `n` must be in 1...UInt32.max.
    public mutating func int(_ n: Int) -> Int {
        guard n > 0, let un = UInt32(exactly: n) else {
            preconditionFailure("Mulberry32.int(n): n must be in 1...UInt32.max, got \(n)")
        }
        let r: UInt32 = next() % un
        return Int(r)
    }
}
