// Python-semantics helpers for the MixlingsArt port. Mirrors art/ts-port/render.ts.
import Foundation

/// Python `round(x)` on a float: round-half-to-even (banker's rounding).
@inline(__always)
func pyRound(_ x: Double) -> Int {
    return Int(x.rounded(.toNearestOrEven))
}

/// Python float `%` (CPython float_rem): result takes the sign of the divisor.
func pyMod(_ a: Double, _ b: Double) -> Double {
    var m = a.truncatingRemainder(dividingBy: b) // C fmod
    if m != 0 {
        if (b < 0) != (m < 0) { m += b }
    } else {
        m = b < 0 ? -0.0 : 0.0
    }
    return m
}

/// Python int `//` (floor division).
@inline(__always)
func floorDiv(_ a: Int, _ b: Int) -> Int {
    let q = a / b
    return (a % b != 0 && ((a < 0) != (b < 0))) ? q - 1 : q
}

/// Python int `%` (result has the sign of the divisor).
@inline(__always)
func pyIntMod(_ a: Int, _ b: Int) -> Int {
    let r = a % b
    return (r != 0 && ((r < 0) != (b < 0))) ? r + b : r
}

/// Python `(seed * mult) & 0xFFFFFFFF` for big ints. Wrapping 64-bit multiply then
/// truncation is exact mod 2^32 for any Int seed (also negative, two's complement).
@inline(__always)
func mask32(_ v: Int) -> UInt32 {
    return UInt32(truncatingIfNeeded: v)
}

/// mulberry32, identical to art/render.py `Mulberry` (and genome-spec §3).
struct ArtMulberry {
    var s: UInt32

    init(_ seed: UInt32) { s = seed }

    mutating func next() -> UInt32 {
        s = s &+ 0x6D2B_79F5
        var t = s
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return t ^ (t >> 14)
    }

    mutating func int(_ n: Int) -> Int {
        precondition(n > 0, "ArtMulberry.int(n): n must be > 0")
        return Int(next() % UInt32(n))
    }

    mutating func randrange(_ a: Int, _ b: Int) -> Int {
        return a + int(b - a)
    }
}

// MARK: - colorsys (CPython Lib/colorsys.py, verbatim, Double precision)

private let ONE_THIRD = 1.0 / 3.0
private let ONE_SIXTH = 1.0 / 6.0
private let TWO_THIRD = 2.0 / 3.0

func rgbToHls(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, l: Double, s: Double) {
    let maxc = max(r, g, b)
    let minc = min(r, g, b)
    let sumc = maxc + minc
    let rangec = maxc - minc
    let l = sumc / 2.0
    if minc == maxc { return (0.0, l, 0.0) }
    let s: Double
    if l <= 0.5 {
        s = rangec / sumc
    } else {
        s = rangec / (2.0 - maxc - minc) // Not always 2.0-sumc: gh-106498.
    }
    let rc = (maxc - r) / rangec
    let gc = (maxc - g) / rangec
    let bc = (maxc - b) / rangec
    var h: Double
    if r == maxc {
        h = bc - gc
    } else if g == maxc {
        h = 2.0 + rc - bc
    } else {
        h = 4.0 + gc - rc
    }
    h = pyMod(h / 6.0, 1.0)
    return (h, l, s)
}

private func colorsysV(_ m1: Double, _ m2: Double, _ hueIn: Double) -> Double {
    let hue = pyMod(hueIn, 1.0)
    if hue < ONE_SIXTH { return m1 + (m2 - m1) * hue * 6.0 }
    if hue < 0.5 { return m2 }
    if hue < TWO_THIRD { return m1 + (m2 - m1) * (TWO_THIRD - hue) * 6.0 }
    return m1
}

func hlsToRgb(_ h: Double, _ l: Double, _ s: Double) -> (r: Double, g: Double, b: Double) {
    if s == 0.0 { return (l, l, l) }
    let m2: Double
    if l <= 0.5 {
        m2 = l * (1.0 + s)
    } else {
        m2 = l + s - (l * s)
    }
    let m1 = 2.0 * l - m2
    return (colorsysV(m1, m2, h + ONE_THIRD), colorsysV(m1, m2, h), colorsysV(m1, m2, h - ONE_THIRD))
}

/// CPython math.radians: x * (pi / 180).
@inline(__always)
func radians(_ d: Double) -> Double {
    return d * (Double.pi / 180.0)
}
