import Foundation

/// PRNG mulberry32 — porting bit-esatto dell'implementazione JS normativa (README §7.2).
///
/// Semantica 32-bit replicata con UInt32 e operatori wrapping:
/// - JS `a |= 0; a = (a + K) | 0`      → `a = a &+ K` su UInt32 (stesso bit pattern)
/// - JS `Math.imul(x, y)`              → `x &* y` su UInt32 (32 bit bassi del prodotto)
/// - JS `x >>> n`                      → `x >> n` su UInt32 (shift logico)
/// - JS `(t + Math.imul(...)) ^ t`     → la somma float è esatta (< 2^33) e il ToInt32
///                                       finale equivale al wrap mod 2^32 → `&+`
public struct Mulberry32 {
    private var a: UInt32

    public init(seed: Int) {
        self.a = UInt32(truncatingIfNeeded: seed)
    }

    /// Ritorna un Double in [0, 1), identico a `rng()` del JS.
    public mutating func next() -> Double {
        a = a &+ 0x6D2B79F5
        var t = (a ^ (a >> 15)) &* (a | 1)
        t = (t &+ ((t ^ (t >> 7)) &* (t | 61))) ^ t
        return Double(t ^ (t >> 14)) / 4294967296.0
    }
}
