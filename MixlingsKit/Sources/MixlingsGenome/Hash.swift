// FNV-1a 32-bit over UTF-8 bytes (genome-spec §3).
// Mirrors engine-ts/src/hash.ts.

public enum Hash {
    public static let fnvOffset: UInt32 = 0x811C_9DC5
    public static let fnvPrime: UInt32 = 0x0100_0193

    public static func fnv1a32(_ input: String) -> UInt32 {
        let bytes: [UInt8] = Array(input.utf8)
        var h: UInt32 = fnvOffset
        for b in bytes {
            h ^= UInt32(b)
            h = h &* fnvPrime // wrapping multiply == Math.imul(...) >>> 0
        }
        return h
    }

    /// 8-char lowercase hex, zero padded.
    public static func hex8(_ n: UInt32) -> String {
        let s = String(n, radix: 16, uppercase: false)
        if s.count >= 8 { return s }
        return String(repeating: "0", count: 8 - s.count) + s
    }
}
