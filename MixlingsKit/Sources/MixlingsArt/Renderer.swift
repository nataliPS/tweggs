// Swift port of art/render.py `render_raw(p, silhouette)` and everything it calls.
// Mirrors art/ts-port/render.ts line by line; that port is verified 146/146 against
// art/golden/renders.json. Keep the three in sync.
import Foundation

/// Grid size (Python `S`).
let S = 32

/// Growth stages (Python `EGG`, `BABY`, `TEEN`, `ADULT`).
let EGG = 0, BABY = 1, TEEN = 2, ADULT = 3

/// Phenotype: mirrors Python `Pheno` (expressed part variants + non-genetic layers).
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
    /// Expression layer, not a gene: 0 neutral (small smile), 1 "o", 2 hungry wobble.
    public var mood: Int
    /// Growth stage: 0 egg, 1 baby, 2 teen, 3 adult.
    public var stage: Int

    public init(body: Int, eyes: Int, head: Int, pattern: Int, tail: Int,
                palette: Int, aura: Int, shift: Int = 0, seed: Int = 0,
                mood: Int = 0, stage: Int = 3) {
        self.body = body; self.eyes = eyes; self.head = head; self.pattern = pattern
        self.tail = tail; self.palette = palette; self.aura = aura; self.shift = shift; self.seed = seed
        self.mood = mood; self.stage = stage
    }

    private enum CodingKeys: String, CodingKey {
        case body, eyes, head, pattern, tail, palette, aura, shift, seed, mood, stage
    }

    /// `shift`, `seed`, `mood` and `stage` are optional in JSON (defaults as in Python).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        body = try c.decode(Int.self, forKey: .body)
        eyes = try c.decode(Int.self, forKey: .eyes)
        head = try c.decode(Int.self, forKey: .head)
        pattern = try c.decode(Int.self, forKey: .pattern)
        tail = try c.decode(Int.self, forKey: .tail)
        palette = try c.decode(Int.self, forKey: .palette)
        aura = try c.decode(Int.self, forKey: .aura)
        shift = try c.decodeIfPresent(Int.self, forKey: .shift) ?? 0
        seed = try c.decodeIfPresent(Int.self, forKey: .seed) ?? 0
        mood = try c.decodeIfPresent(Int.self, forKey: .mood) ?? 0
        stage = try c.decodeIfPresent(Int.self, forKey: .stage) ?? 3
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

/// Symmetric mask from per-row half-widths: row y0+i covers x 16-k ..< 16+k.
func rowsMask(_ y0: Int, _ halves: [Int]) -> Mask {
    var m = Mask()
    for (i, k) in halves.enumerated() {
        var x = 16 - k
        while x < 16 + k { m.insert(x, y0 + i); x += 1 }
    }
    return m
}

/// Drop half-widths per stage (adult = the approved sin/pow curve, tabulated).
let DROP_ROWS: [Int: (y0: Int, halves: [Int])] = [
    ADULT: (y0: 9, halves: [3, 4, 4, 5, 6, 7, 7, 8, 8, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 8]),
    TEEN: (y0: 13, halves: [2, 3, 4, 5, 5, 6, 6, 7, 7, 7, 7, 7, 7, 7, 7, 6]),
    BABY: (y0: 17, halves: [2, 3, 3, 4, 5, 5, 5, 5, 5, 5, 5, 4]),
]
/// 14 x 18 egg (rows 11..28).
let EGG_ROWS: (y0: Int, halves: [Int]) = (y0: 11, halves: [2, 3, 4, 4, 5, 5, 6, 6, 6, 7, 7, 7, 7, 7, 6, 6, 5, 3])

func dropMask(_ stage: Int) -> Mask {
    let d = DROP_ROWS[stage]!
    return rowsMask(d.y0, d.halves)
}

func bodyAdult(_ v: Int) -> Mask {
    switch v {
    case 0: return ellipse(16, 20, 9.5, 8.5)                              // round
    case 1: return ellipse(16, 19, 7.5, 10.5)                             // bean (tall)
    case 2: return ellipse(16, 15, 5, 6).union(ellipse(16, 22, 9.5, 7))   // pear
    case 3: return rrect(7, 11, 24, 28, 2)                                // block
    case 4: return dropMask(ADULT)                                        // drop
    default: return ellipse(16, 22, 11.5, 6.5)                            // mochi (wide)
    }
}

func bodyTeen(_ v: Int) -> Mask { // ~80 %
    switch v {
    case 0: return ellipse(16, 22, 7.5, 7)
    case 1: return ellipse(16, 21, 6, 8.5)
    case 2: return ellipse(16, 18.5, 4, 5).union(ellipse(16, 24, 7.5, 5.5))
    case 3: return rrect(9, 15, 22, 28, 2)
    case 4: return dropMask(TEEN)
    default: return ellipse(16, 23.5, 9.5, 5.5)
    }
}

func bodyBaby(_ v: Int) -> Mask { // ~60 %
    switch v {
    case 0: return ellipse(16, 23.5, 6, 5.5)
    case 1: return ellipse(16, 23, 4.5, 6.5)
    case 2: return ellipse(16, 21.5, 3, 3.5).union(ellipse(16, 25, 6, 4))
    case 3: return rrect(10, 18, 21, 28, 1)
    case 4: return dropMask(BABY)
    default: return ellipse(16, 25, 7.5, 4)
    }
}

func bodyMask(_ v: Int, _ stage: Int) -> Mask {
    if stage == EGG { return rowsMask(EGG_ROWS.y0, EGG_ROWS.halves) }
    var m = stage == ADULT ? bodyAdult(v) : (stage == TEEN ? bodyTeen(v) : bodyBaby(v))
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
    var solid: Bool  // participates in outline
    var knock: Bool  // eye pixel: transparent in silhouette mode
}

/// Python's `canvas` dict. Only membership and last-written value ever affect the
/// output (the final paint is per-pixel), so a flat grid is equivalent.
struct Canvas {
    var px = [Px?](repeating: nil, count: S * S)

    func get(_ x: Int, _ y: Int) -> Px? { px[y * S + x] }
    func has(_ x: Int, _ y: Int) -> Bool { px[y * S + x] != nil }
    mutating func set(_ x: Int, _ y: Int, _ role: Role, _ solid: Bool = true, _ knock: Bool = false) {
        px[y * S + x] = Px(role: role, solid: solid, knock: knock)
    }
    /// Python `put`: bounds-checked set.
    mutating func put(_ x: Int, _ y: Int, _ role: Role, _ solid: Bool = true, _ knock: Bool = false) {
        if x >= 0 && x < S && y >= 0 && y < S { set(x, y, role, solid, knock) }
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

/// Python `ROLE`. Lower-case "a" = accent that floats (not outlined).
func roleFor(_ ch: Character) -> Role {
    switch ch {
    case "B": return .base
    case "S": return .shade
    case "A", "a": return .accent
    case "L": return .light
    case "K": return .eye
    case "W": return .white
    case "M": return .mouth
    default: return .outline
    }
}

/// Right eye; the left eye is its mirror (x -> 31 - x) when EYE_MIRROR, else a shifted copy.
let EYES: [Int: Sprite] = [
    0: sprite(["KK", "KK", "KK"]),                                    // dots 2x3
    1: sprite([".KK.", "KWKK", "KKKK", ".KK."]),                      // big round 4x4
    2: sprite(["KKKK", "...K"]),                                      // sleepy 4x2 + lash
    3: sprite([".KKK.", "K...K", "K...K"]),                           // happy arch 5x3
    4: sprite([".WK.", "WWWK", "KWKK", ".KK."]),                      // sparkle 4x4 + glint
    5: sprite([".K.", "WKK", "KKK", ".K."]),                          // oval 3x4
    6: sprite([".K.", "KAK", ".K."]),                                 // star
    7: sprite([".KKKK.", "KWWKKK", "KWKKKK", "KKKKKK", ".KKKK."]),     // cyclops (single)
]
let EYE_MIRROR: [Int: Bool] = [0: false, 1: false, 2: true, 3: true, 4: false, 5: false, 6: false, 7: false]

/// Mood layer: (x0, mouth sprite).
let MOODS: [Int: (x0: Int, spr: Sprite)] = [
    0: (x0: 14, spr: sprite(["M..M", ".MM."])),           // neutral: small smile
    1: (x0: 14, spr: sprite([".MM.", "M..M", ".MM."])),   // "o"
    2: (x0: 13, spr: sprite([".M..M.", "M.MM.M"])),       // hungry wobble
]

/// A stamped part: top-left x0 (heads: absolute; tails: relative to the tail anchor),
/// dy0 relative to the body top (heads) or the tail anchor (tails), ASCII rows.
struct Part {
    let x0: Int
    let dy0: Int
    let rows: [String]
}

// Heads / tails per stage: stage -> variant -> Part. Babies have no tail.
let HEADS: [Int: [Int: Part]] = [
    ADULT: [
        1: Part(x0: 8, dy0: -4, rows: ["...B........B...", "..BAB......BAB..", "..BAB......BAB..", ".BAAAB....BAAAB.", ".BAAAB....BAAAB.", "BBBBBBB..BBBBBBB"]),
        2: Part(x0: 11, dy0: -5, rows: ["BBB....BBB", "BLB....BLB", "BLB....BLB", "BLB....BLB", "BLB....BLB", "BLB....BLB", "BBB....BBB"]),
        3: Part(x0: 7, dy0: -5, rows: ["A................A", "AA..............AA", ".AA............AA.", ".AAA..........AAA.", "..LLL........LLL..", "..LLLL......LLLL.."]),
        4: Part(x0: 15, dy0: -7, rows: [".A.", "AAA", ".A.", ".S.", ".S.", ".S.", ".S."]),
        5: Part(x0: 13, dy0: -4, rows: ["AAA....", ".AA.AAA", "...SAA.", "...S..."]),
        6: Part(x0: 10, dy0: -5, rows: [".....AA.....", "....AAAA....", ".A..AAAA..A.", ".AA.AAAA.AA.", ".AAAAAAAAAA.", ".SSSSSSSSSS."]),
        7: Part(x0: 10, dy0: -5, rows: [".aaaaaaaaaa.", "a..........a", ".aaaaaaaaaa."]),
    ],
    TEEN: [
        1: Part(x0: 9, dy0: -3, rows: ["..B........B..", ".BAB......BAB.", ".BAAB....BAAB.", "BBBBB....BBBBB"]),
        2: Part(x0: 11, dy0: -4, rows: ["BBB....BBB", "BLB....BLB", "BLB....BLB", "BBB....BBB"]),
        3: Part(x0: 8, dy0: -3, rows: ["A..............A", "AA............AA", ".LL..........LL.", ".LLL........LLL."]),
        4: Part(x0: 15, dy0: -5, rows: [".A.", "AAA", ".A.", ".S.", ".S."]),
        5: Part(x0: 13, dy0: -3, rows: ["AA..AA", ".AASA.", "...S.."]),
        6: Part(x0: 12, dy0: -4, rows: ["...AA...", ".A.AA.A.", ".AAAAAA.", "SSSSSSSS"]),
        7: Part(x0: 12, dy0: -5, rows: [".aaaaaa.", "a......a", ".aaaaaa."]),
    ],
    BABY: [
        1: Part(x0: 10, dy0: -2, rows: ["..B......B..", ".BAB....BAB."]),
        2: Part(x0: 11, dy0: -3, rows: [".BB....BB.", ".BL....LB.", ".BB....BB."]),
        3: Part(x0: 10, dy0: -2, rows: ["A..........A", ".LL......LL."]),
        4: Part(x0: 15, dy0: -3, rows: [".A.", "AAA", ".S."]),
        5: Part(x0: 14, dy0: -2, rows: ["AA.A", "..S."]),
        6: Part(x0: 13, dy0: -2, rows: [".AA.", "AAAA"]),
        7: Part(x0: 13, dy0: -4, rows: [".aaaa.", "a....a", ".aaaa."]),
    ],
]
let TAILS: [Int: [Int: Part]] = [
    ADULT: [
        1: Part(x0: -1, dy0: -2, rows: [".BBB.", "BLBBB", "BBBBS", "BBBSS", ".SSS."]),
        2: Part(x0: 0, dy0: -5, rows: ["..BBBB.", ".B....B", ".B.BB.B", ".B.B..B", "BB..BB.", "B......"]),
        3: Part(x0: 0, dy0: -6, rows: [".....AAA", ".....AAA", ".....AAA", "....BB..", "...BB...", "..BB....", "BBB.....", "BB......"]),
        4: Part(x0: 0, dy0: -6, rows: ["....A", "...AA", "..ABA", ".ABBA", "ABBB.", "BBB..", "BB..."]),
        5: Part(x0: 0, dy0: -6, rows: [".....A", "...AAA", "...AA.", ".AAA..", ".AA...", ".AA...", "AA...."]),
    ],
    TEEN: [
        1: Part(x0: -1, dy0: -1, rows: ["BBB", "BBS", ".S."]),
        2: Part(x0: 0, dy0: -2, rows: [".BB", "B.B", "BB."]),
        3: Part(x0: 0, dy0: -2, rows: ["..A", ".B.", "B.."]),
        4: Part(x0: 0, dy0: -2, rows: [".A", "BA", "B."]),
        5: Part(x0: 0, dy0: -2, rows: ["..A", ".A.", "AA."]),
    ],
]

func stamp(_ c: inout Canvas, _ x0: Int, _ y0: Int, _ rows: [String]) {
    for s in sprite(rows) { c.put(x0 + s.x, y0 + s.y, roleFor(s.ch), s.ch != "a") }
}

func drawHead(_ c: inout Canvas, _ v: Int, _ a: Anchors, _ stage: Int) {
    if let part = HEADS[stage]?[v] { stamp(&c, part.x0, a.top + part.dy0, part.rows) }
}

func drawTail(_ c: inout Canvas, _ v: Int, _ a: Anchors, _ stage: Int) {
    if let part = TAILS[stage]?[v] { stamp(&c, a.tailX + part.x0, a.tailY + part.dy0, part.rows) }
}

/// Spots on a fixed grid around (16, midY); at most 4, in table order.
let SPOT_GRID: [(Int, Int)] = [(-7, -2), (5, -3), (-3, 2), (4, 3), (-8, 4), (0, 6), (6, -7), (-5, 7)]

func applyPattern(_ c: inout Canvas, _ m: Mask, _ v: Int, _ a: Anchors) {
    let top = a.top, bottom = a.bottom
    let pts = m.sortedPoints()
    switch v {
    case 1: // belly
        let cy = Double(a.midY) + Double(bottom - a.midY) * 0.45
        let e = ellipse(16, cy, 5, Double(bottom - top) * 0.28)
        for p in e.sortedPoints() where m.contains(p.x, p.y) { c.set(p.x, p.y, .light) }
    case 2: // spots
        var spots = 0
        for (dx, dy) in SPOT_GRID {
            if spots == 4 { break }
            let x = 16 + dx, y = a.midY + dy
            if y <= a.eyeY + 2 && -7 <= dx && dx <= 5 { continue }
            if m.contains(x, y) && m.contains(x + 1, y) && m.contains(x, y + 1) && m.contains(x + 1, y + 1) {
                for i in [0, 1] { for j in [0, 1] { c.set(x + i, y + j, .accent) } }
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
    case 5: // freckles: 3 accent dots per cheek
        for (dx, dy) in [(0, 0), (2, 0), (1, 1)] {
            let x = 16 + a.eyeDx + 1 + dx, y = a.eyeY + 3 + dy
            for px in [x, 31 - x] where m.contains(px, y) { c.set(px, y, .accent) }
        }
    default: break
    }
}

let EGG_SPOTS: [(Int, Int)] = [(12, 14), (18, 12), (16, 18), (11, 21), (19, 22), (15, 25)]
let EGG_FRECKLES: [(Int, Int)] = [(13, 14), (18, 13), (20, 18), (11, 19), (16, 22), (19, 25)]

/// The egg shows the creature's pattern on its shell.
func eggPattern(_ c: inout Canvas, _ m: Mask, _ v: Int) {
    let pts = m.sortedPoints()
    switch v {
    case 1: // belly: pale lower shell
        for p in pts where p.y >= 22 { c.set(p.x, p.y, .light) }
    case 2: // spots
        for (x, y) in EGG_SPOTS {
            for i in [0, 1] { for j in [0, 1] where m.contains(x + i, y + j) { c.set(x + i, y + j, .accent) } }
        }
    case 3: // zig-zag band
        for p in pts {
            let z = floorDiv(p.x, 2) % 2
            if p.y == 18 + z || p.y == 19 + z || p.y == 23 + z { c.set(p.x, p.y, .accent) }
        }
    case 4: // cap
        for p in pts where p.y < 16 { c.set(p.x, p.y, .accent) }
    case 5: // freckles
        for (x, y) in EGG_FRECKLES where m.contains(x, y) { c.set(x, y, .accent) }
    default: break
    }
}

func shadeBody(_ c: inout Canvas, _ m: Mask) {
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
    // highlight: middle of the points with minimal x + y (sorted order), offset inwards
    var best = Int.max
    for p in pts { best = min(best, p.x + p.y) }
    let ties = pts.filter { $0.x + $0.y == best }
    let tl = ties[floorDiv(ties.count - 1, 2)]
    for (px, py) in [(tl.x + 2, tl.y + 2), (tl.x + 3, tl.y + 2), (tl.x + 2, tl.y + 3)] {
        if m.contains(px, py) && c.get(px, py)!.role == .base { c.set(px, py, .white) }
    }
}

struct EyeLayout {
    let spr: Sprite
    let x0: Int, y0: Int, w: Int, h: Int, dx: Int
}

func eyeLayout(_ v: Int, _ a: Anchors) -> EyeLayout {
    let spr = EYES[v] ?? EYES[0]! // python: KeyError for unknown variants (invalid input)
    let w = spr.map { $0.x }.max()! + 1
    let h = spr.map { $0.y }.max()! + 1
    let dx = max(a.eyeDx, floorDiv(w, 2) + 1)
    return EyeLayout(spr: spr, x0: 16 + dx - floorDiv(w, 2), y0: a.eyeY - floorDiv(h, 2), w: w, h: h, dx: dx)
}

func drawEyes(_ c: inout Canvas, _ v: Int, _ a: Anchors) {
    let e = eyeLayout(v, a)
    if v == 7 { // cyclops: one centred eye (x 13..18)
        for s in e.spr { c.put(13 + s.x, e.y0 + s.y, roleFor(s.ch), true, true) }
        return
    }
    let mirror = EYE_MIRROR[v] ?? false
    for s in e.spr {
        c.put(e.x0 + s.x, e.y0 + s.y, roleFor(s.ch), true, true)
        let lx = mirror ? 31 - (e.x0 + s.x) : 31 - (e.x0 + e.w - 1) + s.x
        c.put(lx, e.y0 + s.y, roleFor(s.ch), true, true)
    }
}

/// Mood mouth + blush (colour mode only).
func drawFace(_ c: inout Canvas, _ m: Mask, _ eyes: Int, _ mood: Int, _ a: Anchors) {
    let e = eyeLayout(eyes, a)
    let my = e.y0 + e.h + (e.h >= 3 ? 1 : 2)
    let mouth = MOODS[mood] ?? MOODS[0]!
    for s in mouth.spr { c.put(mouth.x0 + s.x, my + s.y, roleFor(s.ch)) }
    let by = a.eyeY + 2
    let bx = eyes != 7 ? 16 + e.dx + floorDiv(e.w + 1, 2) + 1 : 21
    for x in [bx, 31 - bx] where m.contains(x, by) { c.put(x, by, .blush) }
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
    for i in 0..<(S * S) where out[i] { c.px[i] = Px(role: .outline, solid: false, knock: false) }
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
    case 2: // glow ring (drawn behind), dashed: 3 dots on, 2 off
        var a = 0
        while a < 360 {
            if floorDiv(a, 9) % 5 < 3 {
                let r = 14.5
                let x = pyRound(16 + r * cos(radians(Double(a))))
                let y = pyRound(18 + r * 0.85 * sin(radians(Double(a))))
                extra.append((x: x, y: y, role: Role.light))
            }
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

/// Python `build`: the role canvas.
func build(_ p: Phenotype, _ silhouette: Bool) -> Canvas {
    let stage = p.stage
    let mask = bodyMask(p.body, stage)
    var c = Canvas()
    if stage == EGG {
        for pt in mask.sortedPoints() { c.set(pt.x, pt.y, .base) }
        eggPattern(&c, mask, p.pattern)
        shadeBody(&c, mask)
        outline(&c)
        return c
    }
    let a = anchors(mask)
    drawTail(&c, p.tail, a, stage)
    putMask(&c, mask, .base)
    drawHead(&c, p.head, a, stage)
    for pt in mask.sortedPoints() where !c.has(pt.x, pt.y) { c.set(pt.x, pt.y, .base) } // setdefault
    applyPattern(&c, mask, p.pattern, a)
    shadeBody(&c, mask)
    outline(&c)
    drawEyes(&c, p.eyes, a)
    if !silhouette { drawFace(&c, mask, p.eyes, p.mood, a) }
    return c
}

func putMask(_ c: inout Canvas, _ m: Mask, _ role: Role) {
    for p in m.sortedPoints() { c.put(p.x, p.y, role) }
}

// MARK: - public API

public enum MixlingsRenderer {
    /// Canvas size in pixels (32).
    public static let size = S

    /// Render at scale 1 (honours `p.stage` and `p.mood`).
    /// Pixel-identical to Python `render_raw(p).tobytes()`.
    public static func render(_ p: Phenotype) -> PixelBuffer {
        let c = build(p, false)
        let pal = makePalette(p.palette, p.shift)
        var buf = [UInt8](repeating: 0, count: S * S * 4)
        if p.stage == ADULT {
            for e in drawAura(p.aura, p.seed) {
                if e.x >= 0 && e.x < S && e.y >= 0 && e.y < S && !c.has(e.x, e.y) {
                    let col = pal[e.role], i = (e.y * S + e.x) * 4
                    buf[i] = UInt8(col.r); buf[i + 1] = UInt8(col.g); buf[i + 2] = UInt8(col.b)
                    buf[i + 3] = 255
                }
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

    /// Lock Screen silhouette: white on transparent, knocked-out eyes, no aura, no face.
    /// Pixel-identical to Python `render_raw(p, silhouette=True).tobytes()`.
    public static func renderSilhouette(_ p: Phenotype) -> PixelBuffer {
        let c = build(p, true)
        var buf = [UInt8](repeating: 0, count: S * S * 4)
        for i in 0..<(S * S) {
            guard let px = c.px[i], !px.knock else { continue }
            buf[i * 4] = 255; buf[i * 4 + 1] = 255; buf[i * 4 + 2] = 255; buf[i * 4 + 3] = 255
        }
        return PixelBuffer(width: S, height: S, rgba: buf)
    }
}
