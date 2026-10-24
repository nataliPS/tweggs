// Palettes and colour math. Mirrors art/render.py `PALETTES`, `shift_hue`, `darken`, `palette`.

public struct RGB: Hashable, Sendable {
    public var r: Int
    public var g: Int
    public var b: Int
    public init(_ r: Int, _ g: Int, _ b: Int) { self.r = r; self.g = g; self.b = b }
    init(hex c: UInt32) { self.init(Int((c >> 16) & 0xFF), Int((c >> 8) & 0xFF), Int(c & 0xFF)) }
}

enum Role: Int, CaseIterable {
    case base = 0, shade, accent, light, outline, eye, white, blush
}

/// base, shade, accent, light(belly)
let PALETTES: [(UInt32, UInt32, UInt32, UInt32)] = [
    (0x7ED4A6, 0x4FA77E, 0xFFCB5C, 0xC9F2DA), // mint
    (0xF7A6C4, 0xD2759A, 0x7CC6FE, 0xFFD9E7), // bubblegum
    (0x8FB8FF, 0x5C86D6, 0xFF9F68, 0xD4E3FF), // sky
    (0xFFD36E, 0xE0A93D, 0xFF6F91, 0xFFF0C2), // sunny
    (0xC3A6FF, 0x9479D9, 0x7EF0C8, 0xE7DCFF), // lavender
    (0xFF9B7A, 0xD9704F, 0x6EE7F2, 0xFFD3C4), // coral
    (0x9BE15D, 0x6DB33A, 0xFF7AD9, 0xDDF7C4), // lime
    (0x6FD6E8, 0x3FA8BC, 0xFFE066, 0xCDF4FA), // aqua
    (0xE8E2D0, 0xBDB4A0, 0xFF8A5B, 0xFFFFFF), // cream
    (0xA0A8B8, 0x727B8E, 0xFFD166, 0xD9DEE7), // stone
    (0xFF7AA2, 0xD24F79, 0xFFE27A, 0xFFC6D7), // rose
    (0x5E6BFF, 0x3C46C9, 0xFF9EE5, 0xB9BFFF), // cobalt
    (0x3D3D4E, 0x26262F, 0x7DF9FF, 0x6A6A82), // night (rare)
    (0xFFB347, 0xD98A1F, 0x8E7CFF, 0xFFE0B0), // tangerine
    (0xB8F2E6, 0x7FC7B8, 0xFF8FAB, 0xE6FBF6), // seafoam
    (0xF2F2F2, 0xC9C9D6, 0xFFB3F0, 0xFFFFFF), // ghost (rare)
]

func shiftHue(_ rgb: RGB, _ amount: Double) -> RGB {
    let r = Double(rgb.r) / 255, g = Double(rgb.g) / 255, b = Double(rgb.b) / 255
    let hls = rgbToHls(r, g, b)
    let h = pyMod(hls.h + amount, 1.0)
    let out = hlsToRgb(h, hls.l, hls.s)
    return RGB(pyRound(out.r * 255), pyRound(out.g * 255), pyRound(out.b * 255))
}

func darken(_ rgb: RGB, _ f: Double) -> RGB {
    return RGB(max(0, pyRound(Double(rgb.r) * f)),
               max(0, pyRound(Double(rgb.g) * f)),
               max(0, pyRound(Double(rgb.b) * f)))
}

/// Resolved colours indexed by `Role.rawValue`.
struct ResolvedPalette {
    var colors: [RGB]
    subscript(_ role: Role) -> RGB { colors[role.rawValue] }
}

func makePalette(_ idx: Int, _ shift: Int) -> ResolvedPalette {
    let row = PALETTES[pyIntMod(idx, PALETTES.count)] // valid inputs: 0..15
    var base = RGB(hex: row.0), shade = RGB(hex: row.1), light = RGB(hex: row.3)
    let accent = RGB(hex: row.2)
    if shift != 0 {
        let amt = 0.035 * Double(shift)
        base = shiftHue(base, amt)
        shade = shiftHue(shade, amt)
        light = shiftHue(light, amt)
    }
    var outline = darken(shade, 0.45)
    let lum = 0.299 * Double(base.r) + 0.587 * Double(base.g) + 0.114 * Double(base.b)
    let dark = lum < 90
    if dark { outline = RGB(18, 18, 24) } // dark creatures get glowing eyes and a lighter outline
    var colors = [RGB](repeating: RGB(0, 0, 0), count: Role.allCases.count)
    colors[Role.base.rawValue] = base
    colors[Role.shade.rawValue] = shade
    colors[Role.accent.rawValue] = accent
    colors[Role.light.rawValue] = light
    colors[Role.outline.rawValue] = outline
    colors[Role.eye.rawValue] = dark ? accent : RGB(34, 30, 46)
    colors[Role.white.rawValue] = RGB(255, 255, 255)
    colors[Role.blush.rawValue] = RGB(255, 140, 160)
    return ResolvedPalette(colors: colors)
}
