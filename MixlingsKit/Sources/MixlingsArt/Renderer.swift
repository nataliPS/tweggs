// Swift port of art/render.py `render(p, scale=1)` and everything it calls.
// Mirrors art/ts-port/render.ts line by line; that port is verified 74/74 against
// art/golden/renders.json. Keep the three in sync.
import Foundation

/// Grid size (Python `S`).
let S = 32

/// Phenotype: mirrors Python `Pheno` (expressed part variants).
public struct Phenotype: Hashable, Sendable, Codable {
    public var body: Int
    public var eyes: Int
    public var head: Int
    public var pattern: Int
    public var tail: Int
    public var palette: Int
    public var aura: Int
    public var shift: Int
    public var seed: Int

    public init(body: Int, eyes: Int, head: Int, pattern: Int, tail: Int,
                palette: Int, aura: Int, shift: Int = 0, seed: Int = 0) {
        self.body = body; self.eyes = eyes; self.head = head; self.pattern = pattern
        self.tail = tail; self.palette = palette; self.aura = aura; self.shift = shift; self.seed = seed
    }
}

/// 32x32 RGBA, row-major, 4 bytes/pixel, straight (non-premultiplied) alpha.
public struct PixelBuffer: Hashable, Sendable {
    public let width: Int
    public let height: Int
    public var rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) {
        precondition(rgba.count == width * height * 4, "PixelBuffer: rgba.count must be width*height*4")
        self.width = width; self.height = height; self.rgba = rgba
    }
}

// MARK: - masks (32x32 bool grids, index y*S+x)

struct Mask {
    var bits = [Bool](repeating: false, count: S * S)

    func contains(_ x: Int, _ y: Int) -> Bool {
        return x >= 0 && x < S && y >= 0 && y < S && bits[y * S + x]
    }

    mutating func insert(_ x: Int, _ y: Int) { bits[y * S + x] = true }

    func union(_ o: Mask) -> Mask {
        var m = Mask()
        for i in 0..<(S * S) { m.bits[i] = bits[i] || o.bits[i] }
        return m
    }

    /// Points in Python `sorted()` order: by x, then y.
    func sortedPoints() -> [(x: Int, y: Int)] {
        var out: [(x: Int, y: Int)] = []
        for x in 0..<S { for y in 0..<S where bits[y * S + x] { out.append((x: x, y: y)) } }
        return out
    }
}

func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Mask {
    var m = Mask()
    for x in 0..<S {
        for y in 0..<S {
            let a = (Double(x) + 0.5 - cx) / rx
            let b = (Double(y) + 0.5 - cy) / ry
            if a * a + b * b <= 1.0 { m.insert(x, y) }
        }
    }
    return m
}

func rrect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ r: Int) -> Mask {
    var m = Mask()
    for x in x0...x1 {
        for y in y0...y1 {
            let cx = min(max(x, x0 + r), x1 - r)
            let cy = min(max(y, y0 + r), y1 - r)
            let d = (x - cx) * (x - cx) + (y - cy) * (y - cy)
            if Double(d) <= Double(r * r) + 0.5 { m.insert(x, y) }
        }
    }
    return m
}

func bodyMask(_ v: Int) -> Mask {
    var m: Mask
    switch v {
    case 0: m = ellipse(16, 20, 9.5, 8.5)                               // round
    case 1: m = ellipse(16, 19, 7.5, 10.5)                              // bean (tall)
    case 2: m = ellipse(16, 15, 6.5, 6).union(ellipse(16, 22, 9.5, 7))  // pear
    case 3: m = rrect(7, 11, 24, 28, 5)                                 // block
    case 4:                                                             // drop
        m = Mask()
        for y in 9..<29 {
            let t = Double(y - 9) / 19
            let w = 9.5 * pow(sin(Double.pi * min(1.0, t * 0.62 + 0.08)), 0.9)
            for x in 0..<S where abs(Double(x) + 0.5 - 16) <= w { m.insert(x, y) }
        }
    default: m = ellipse(16, 22, 11.5, 6.5)                             // mochi (wide)
    }
    // little feet
    var bottom = -1
    for p in m.sortedPoints() { bottom = max(bottom, p.y) }
    for fx in [11, 12, 19, 20] where m.contains(fx, bottom) {
        if bottom + 1 < S { m.insert(fx, bottom + 1) }
    }
    return m
}

struct Anchors {
    var top: Int, bottom: Int, eyeY: Int, eyeDx: Int, tailX: Int, tailY: Int, midY: Int
}

func anchors(_ m: Mask) -> Anchors {
    let pts = m.sortedPoints()
    let top = pts.filter { $0.x == 16 }.map { $0.y }.min()!
    let bottom = pts.map { $0.y }.max()!
    let h = bottom - top
    let eyeY = top + max(3, pyRound(Double(h) * 0.38))
    let row = pts.filter { $0.y == eyeY }.map { $0.x }
    let half = Double(row.max()! - row.min()!) / 2
    let eyeDx = max(2, min(4, pyRound(half * 0.42)))
    let tailY = top + pyRound(Double(h) * 0.68)
    let tailX = pts.filter { $0.y == tailY }.map { $0.x }.max()! + 1
    return Anchors(top: top, bottom: bottom, eyeY: eyeY, eyeDx: eyeDx,
                   tailX: tailX, tailY: tailY, midY: top + floorDiv(h, 2))
}

// MARK: - canvas

struct Px {
    var role: Role
    var solid: Bool // participates in outline
}

/// Python's `canvas` dict. Only membership and last-written value ever affect the
/// output (the final paint is per-pixel), so a flat grid is equivalent.
struct Canvas {
    var px = [Px?](repeating: nil, count: S * S)

    func get(_ x: Int, _ y: Int) -> Px? { px[y * S + x] }
    func has(_ x: Int, _ y: Int) -> Bool { px[y * S + x] != nil }
    mutating func set(_ x: Int, _ y: Int, _ role: Role, _ solid: Bool = true) {
        px[y * S + x] = Px(role: role, solid: solid)
    }
    /// Python `put`: bounds-checked set.
    mutating func put(_ x: Int, _ y: Int, _ role: Role, _ solid: Bool = true) {
        if x >= 0 && x < S && y >= 0 && y < S { set(x, y, role, solid) }
    }
}

// MARK: - sprites

typealias Sprite = [(x: Int, y: Int, ch: Character)]

func sprite(_ rows: [String]) -> Sprite {
    var out: Sprite = []
    for (y, row) in rows.enumerated() {
        for (x, ch) in row.enumerated() where ch != "." { out.append((x: x, y: y, ch: ch)) }
    }
    return out
}

let EYES: [Int: Sprite] = [
    0: sprite(["KK", "KK"]),                       // dots
    1: sprite([".KK.", "KWKK", "KKKK", ".KK."]),   // big round
    2: sprite(["KKK"]),                            // sleepy
    3: sprite([".K.", "K.K"]),                     // happy ^
    4: sprite(["KKK", "KWK", "KKK"]),              // sparkle
    5: sprite(["KK", "WK", "KK"]),                 // oval
    6: sprite([".K.", "KAK", ".K."]),              // star
]
let CYCLOPS = sprite([".KKKK.", "KWWKKK", "KWKKKK", "KKKKKK", ".KKKK."])

func roleFor(_ ch: Character) -> Role {
    switch ch {
    case "B": return .base
    case "S": return .shade
    case "A": return .accent
    case "L": return .light
    case "K": return .eye
    case "W": return .white
    default: return .outline // "O"
    }
}

// MARK: - parts

func drawHead(_ c: inout Canvas, _ v: Int, _ a: Anchors) {
    let t = a.top
    switch v {
    case 1: // cat ears
        for side in [-1, 1] {
            let cx = 16 + side * 5
            for i in 0..<4 {
                for dx in -(3 - i)...(3 - i) { c.put(cx + dx, t - i + 1, .base) }
            }
            c.put(cx, t, .accent)
            c.put(cx, t - 1, .accent)
        }
    case 2: // bunny ears
        for side in [-1, 1] {
            let cx = 16 + side * 4
            for i in 0..<7 {
                for dx in [-1, 0, 1] { c.put(cx + dx, t - i + 1, .base) }
                if 1 <= i && i <= 5 { c.put(cx, t - i + 1, .light) }
            }
        }
    case 3: // horns
        let rows: [(Int, [Int])] = [(0, [3, 4, 5, 6]), (-1, [4, 5, 6]), (-2, [5, 6, 7]),
                                    (-3, [6, 7]), (-4, [7, 8]), (-5, [8])]
        for side in [-1, 1] {
            for (dy, xs) in rows {
                for dx in xs { c.put(16 + side * dx, t + dy, dy > -2 ? .light : .accent) }
            }
        }
    case 4: // antenna
        for i in 1..<5 { c.put(16, t - i, .shade) }
        for dx in [-1, 0, 1] {
            for dy in [-1, 0, 1] where abs(dx) + abs(dy) < 2 { c.put(16 + dx, t - 6 + dy, .accent) }
        }
    case 5: // leaf sprout
        c.put(16, t - 1, .shade)
        c.put(16, t - 2, .shade)
        for p in [(-1, -3), (-2, -3), (-2, -4), (-3, -4), (-1, -4)] { c.put(16 + p.0, t + p.1, .accent) }
        for p in [(1, -2), (2, -3), (2, -2), (3, -3), (1, -3)] { c.put(16 + p.0, t + p.1, .accent) }
    case 6: // crest spikes
        for dx in [-4, 0, 4] {
            let hgt = dx != 0 ? 3 : 4
            for k in 0..<hgt {
                let n = hgt - 1 - k
                // python: range(-(n) // 2 - 1 + 1, n // 2 + 1)  (unary minus binds before //)
                let lo = floorDiv(-n, 2) - 1 + 1
                let hi = floorDiv(n, 2) + 1
                var w = lo
                while w < hi { c.put(16 + dx + w, t - k, .accent); w += 1 }
            }
        }
    case 7: // halo (floating)
        for x in 11..<22 {
            if x == 11 || x == 21 { continue }
            c.put(x, t - 5, .accent, false)
            c.put(x, t - 3, .accent, false)
        }
        c.put(11, t - 4, .accent, false)
        c.put(21, t - 4, .accent, false)
    default: break
    }
}

/// Stamp a 2px-thick stroke so diagonal tails don't break into checkers.
func thick(_ c: inout Canvas, _ tx: Int, _ ty: Int, _ pts: [(Int, Int)], _ role: Role) {
    for (dx, dy) in pts {
        c.put(tx + dx, ty + dy, role)
        c.put(tx + dx, ty + dy + 1, role)
    }
}

func putMask(_ c: inout Canvas, _ m: Mask, _ role: Role) {
    for p in m.sortedPoints() { c.put(p.x, p.y, role) }
}

func drawTail(_ c: inout Canvas, _ v: Int, _ a: Anchors) {
    let tx = a.tailX, ty = a.tailY
    switch v {
    case 1: // puff
        putMask(&c, ellipse(Double(tx) + 1.5, Double(ty) + 0.5, 2.4, 2.4), .light)
    case 2: // curly
        thick(&c, tx, ty, [(0, 0), (1, 0), (2, -1), (3, -2), (3, -3), (2, -4), (1, -4)], .base)
    case 3: // long, with a tuft
        thick(&c, tx, ty, [(0, 0), (1, 0), (2, -1), (3, -2), (4, -3), (5, -4)], .base)
        putMask(&c, ellipse(Double(tx) + 6.5, Double(ty) - 4.5, 1.6, 1.6), .accent)
    case 4: // flame
        let pts = [(0, 0), (1, 0), (1, -1), (2, -1), (2, -2), (3, -2), (2, -3), (3, -4), (1, -2),
                   (0, -1), (3, -3), (4, -3), (3, -5)]
        for (dx, dy) in pts { c.put(tx + dx, ty + dy, .accent) }
    case 5: // lightning
        let pts = [(0, 0), (1, 0), (1, -1), (2, -1), (2, -2), (1, -2), (1, -3), (2, -3), (3, -3),
                   (3, -4), (4, -4), (4, -5), (3, -5), (5, -5), (5, -6)]
        for (dx, dy) in pts { c.put(tx + dx, ty + dy, .accent) }
    default: break
    }
}

func applyPattern(_ c: inout Canvas, _ m: Mask, _ v: Int, _ a: Anchors, _ seed: Int) {
    var rnd = ArtMulberry(mask32(seed &* 2_654_435_761))
    let top = a.top, bottom = a.bottom
    let pts = m.sortedPoints()
    switch v {
    case 1: // belly
        let cy = Double(a.midY) + Double(bottom - a.midY) * 0.45
        let e = ellipse(16, cy, 5, Double(bottom - top) * 0.28)
        for p in e.sortedPoints() where m.contains(p.x, p.y) { c.set(p.x, p.y, .light) }
    case 2: // spots
        var spots = 0, tries = 0
        while spots < 4 && tries < 60 {
            tries += 1
            let p = pts[rnd.int(pts.count)] // rnd.choice(sorted(mask))
            let x = p.x, y = p.y
            if y <= a.eyeY + 1 && abs(x - 16) < 6 { continue }
            let ok = m.contains(x, y) && m.contains(x + 1, y) && m.contains(x, y + 1) && m.contains(x + 1, y + 1)
            if ok {
                for dx in [0, 1] { for dy in [0, 1] { c.set(x + dx, y + dy, .accent) } }
                spots += 1
            }
        }
    case 3: // stripes
        for p in pts where p.y > a.eyeY + 3 && [0, 1].contains(pyIntMod(p.y - top, 5)) {
            c.set(p.x, p.y, .accent)
        }
    case 4: // two-tone cap
        for p in pts where Double(p.y) < Double(top) + Double(bottom - top) * 0.3 {
            c.set(p.x, p.y, .accent)
        }
    case 5: // freckles
        for dx in [-1, 1] {
            for k in [0, 2] {
                let px = 16 + dx * (a.eyeDx + 1 + floorDiv(k, 2))
                let py = a.eyeY + 2 + (k % 2)
                if m.contains(px, py) { c.set(px, py, .shade) }
            }
        }
    default: break
    }
}

/// Python picks the highlight anchor with `sorted(mask, key=...)[:1]`. The key ties
/// for every body variant, so CPython returns the first tied point in *set iteration
/// order* (hash-table layout) - not portable. The mask depends only on the body
/// variant, so the winner is a per-body constant, recorded from CPython 3.11-3.13.
/// Index 5 covers every body >= 5 (mochi, Python's `else`).
let HIGHLIGHT_TIE_WINNER: [(x: Int, y: Int)] = [(9, 14), (13, 9), (10, 12), (9, 12), (13, 9), (6, 18)]

func shadeBody(_ c: inout Canvas, _ m: Mask, _ bodyVariant: Int) {
    let pts = m.sortedPoints()
    let xs = pts.map { $0.x }, ys = pts.map { $0.y }
    let cx = Double(xs.min()! + xs.max()!) / 2
    let cy = Double(ys.min()! + ys.max()!) / 2
    for p in pts {
        let x = p.x, y = p.y
        // lower-right rim shading
        if !m.contains(x + 1, y + 1) || (!m.contains(x + 1, y) && Double(y) > cy) {
            if Double(x) >= cx - 1 || Double(y) >= cy + 2 {
                if c.get(x, y)!.role == .base { c.set(x, y, .shade) }
            }
        }
    }
    // highlight upper-left: minimum key; tie-break per HIGHLIGHT_TIE_WINNER, else lexicographic
    func key(_ x: Int, _ y: Int) -> Double { (Double(x) - cx) + (Double(y) - cy) }
    var best = Double.infinity
    for p in pts { best = min(best, key(p.x, p.y)) }
    let ties = pts.filter { key($0.x, $0.y) == best }
    guard var tl = ties.first else { return }
    let w = HIGHLIGHT_TIE_WINNER[(bodyVariant >= 0 && bodyVariant <= 4) ? bodyVariant : 5]
    if ties.contains(where: { $0.x == w.x && $0.y == w.y }) { tl = w }
    for (px, py) in [(tl.x + 2, tl.y + 2), (tl.x + 3, tl.y + 2), (tl.x + 2, tl.y + 3)] {
        if m.contains(px, py) && c.get(px, py)!.role == .base { c.set(px, py, .white) }
    }
}

func drawEyes(_ c: inout Canvas, _ v: Int, _ a: Anchors) {
    let ey = a.eyeY, dx = a.eyeDx
    if v == 7 {
        for s in CYCLOPS { c.put(16 - 3 + s.x, ey - 2 + s.y, roleFor(s.ch)) }
        return
    }
    guard let spr = EYES[v] else { return } // python: KeyError for unknown variants
    let w = spr.map { $0.x }.max()! + 1
    let h = spr.map { $0.y }.max()! + 1
    for side in [-1, 1] {
        let cx = 16 + side * dx
        let x0 = side < 0 ? cx - floorDiv(w, 2) : cx - floorDiv(w - 1, 2)
        for s in spr {
            let xx = side > 0 ? s.x : (w - 1 - s.x)
            c.put(x0 + xx, ey - floorDiv(h, 2) + s.y, roleFor(s.ch))
        }
    }
    // blush
    for side in [-1, 1] { c.put(16 + side * (dx + 2), ey + 2, .blush) }
}

/// Order-independent: `out` is a union computed before any write.
func outline(_ c: inout Canvas) {
    var out = [Bool](repeating: false, count: S * S)
    for y in 0..<S {
        for x in 0..<S {
            guard let p = c.get(x, y), p.solid, p.role != .outline else { continue }
            for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] {
                if nx >= 0 && nx < S && ny >= 0 && ny < S && !c.has(nx, ny) { out[ny * S + nx] = true }
            }
        }
    }
    for i in 0..<(S * S) where out[i] { c.px[i] = Px(role: .outline, solid: false) }
}

func drawAura(_ v: Int, _ seed: Int) -> [(x: Int, y: Int, role: Role)] {
    if v == 0 { return [] }
    var rnd = ArtMulberry(mask32(seed &* 7 &+ v))
    var extra: [(x: Int, y: Int, role: Role)] = []
    switch v {
    case 1: // sparkles
        for _ in 0..<5 {
            let x = rnd.randrange(1, S - 1)
            let y = rnd.randrange(1, 14)
            extra.append((x: x, y: y, role: Role.white))
            extra.append((x: x - 1, y: y, role: Role.accent))
            extra.append((x: x + 1, y: y, role: Role.accent))
            extra.append((x: x, y: y - 1, role: Role.accent))
            extra.append((x: x, y: y + 1, role: Role.accent))
        }
    case 2: // glow ring (drawn behind)
        var a = 0
        while a < 360 {
            let r = 14.5
            let x = pyRound(16 + r * cos(radians(Double(a))))
            let y = pyRound(18 + r * 0.85 * sin(radians(Double(a))))
            extra.append((x: x, y: y, role: Role.light))
            a += 9
        }
    case 3: // tiny hearts
        let heart = [(0, 0), (2, 0), (0, 1), (1, 1), (2, 1), (1, 2)]
        for _ in 0..<3 {
            let x = rnd.randrange(2, S - 4)
            let y = rnd.randrange(1, 10)
            for (dx, dy) in heart { extra.append((x: x + dx, y: y + dy, role: Role.blush)) }
        }
    default: break
    }
    return extra
}

// MARK: - public API

public enum MixlingsRenderer {
    /// Canvas size in pixels (32).
    public static let size = S

    /// Render at scale 1. Pixel-identical to Python `render(p, 1).tobytes()`.
    public static func render(_ p: Phenotype) -> PixelBuffer {
        let pal = makePalette(p.palette, p.shift)
        let mask = bodyMask(p.body)
        let a = anchors(mask)
        var c = Canvas()
        drawTail(&c, p.tail, a)
        putMask(&c, mask, .base)
        drawHead(&c, p.head, a)
        for pt in mask.sortedPoints() where !c.has(pt.x, pt.y) { c.set(pt.x, pt.y, .base) } // setdefault
        applyPattern(&c, mask, p.pattern, a, p.seed)
        shadeBody(&c, mask, p.body)
        outline(&c)
        drawEyes(&c, p.eyes, a)

        var buf = [UInt8](repeating: 0, count: S * S * 4)
        for e in drawAura(p.aura, p.seed) {
            if e.x >= 0 && e.x < S && e.y >= 0 && e.y < S && !c.has(e.x, e.y) {
                let col = pal[e.role], i = (e.y * S + e.x) * 4
                buf[i] = UInt8(col.r); buf[i + 1] = UInt8(col.g); buf[i + 2] = UInt8(col.b)
                buf[i + 3] = p.aura == 2 ? 170 : 255
            }
        }
        for i in 0..<(S * S) {
            guard let px = c.px[i] else { continue }
            let col = pal[px.role]
            buf[i * 4] = UInt8(col.r); buf[i * 4 + 1] = UInt8(col.g); buf[i * 4 + 2] = UInt8(col.b)
            buf[i * 4 + 3] = 255
        }
        return PixelBuffer(width: S, height: S, rgba: buf)
    }
}
